defmodule OrchidDBTest do
  use ExUnit.Case

  def request(query) do
    %{
      version: 1,
      dialect: "duckdb",
      language: "cypher",
      query: query,
      tables: [
        %{
          name: "people",
          columns: [%{name: "id", data_type: "int64"}, %{name: "name", data_type: "string"}]
        }
      ],
      nodes: [%{label: "Person", table: "people", id: "id", properties: %{name: "name"}}]
    }
  end

  test "native compile, parameters and compiler errors" do
    assert {:ok, plan} = OrchidDB.compile(request("MATCH (p:Person) RETURN p.name AS name"))
    assert plan["fields"] == ["name"]
    assert plan["sql"] =~ "people"

    assert {:ok, plan} =
             OrchidDB.compile(Map.put(request("RETURN $n AS n"), :parameters, %{n: 42}))

    assert plan["sql"] =~ "42"
    assert {:error, _} = OrchidDB.compile(request("MATCH (p:Person) DELETE p"))
  end

  test "bad library returns explicit error" do
    assert {:error, _} = OrchidDB.compile(request("RETURN 1"), library: "/missing/compiler.so")
  end

  test "caller-owned SQLite ADBC Arrow stream can be ingested without row conversion" do
    :ok = Adbc.download_driver(:sqlite)
    {:ok, db} = Adbc.Database.start_link(driver: :sqlite)
    {:ok, source} = Adbc.Connection.start_link(database: db)
    {:ok, sink} = Adbc.Connection.start_link(database: db)

    try do
      {:ok, _} = Adbc.Connection.query(source, "CREATE TABLE people(id INTEGER, name TEXT)")
      {:ok, _} = Adbc.Connection.query(source, "INSERT INTO people VALUES (1, 'Ada')")
      # SQLite accepts this DuckDB-targeted simple SELECT. No SQLite compiler dialect is claimed.
      assert {:ok, _} =
               OrchidDB.query_arrow(
                 source,
                 request("MATCH (p:Person) RETURN p.name AS name"),
                 fn stream ->
                   Adbc.Connection.bulk_insert!(sink, stream, table: "copied")
                 end
               )

      assert {:ok, result} = Adbc.Connection.query(sink, "SELECT name FROM copied")
      assert Adbc.Result.to_map(result) == %{"name" => ["Ada"]}

      assert_raise RuntimeError, "consumer failed", fn ->
        OrchidDB.query_arrow(source, request("RETURN 1 AS answer"), fn _stream ->
          raise "consumer failed"
        end)
      end

      assert {:ok, _} = Adbc.Connection.query(source, "SELECT 1")
    after
      GenServer.stop(source)
      GenServer.stop(sink)
      GenServer.stop(db)
    end
  end
end

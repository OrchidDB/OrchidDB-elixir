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
      nodes: [%{label: "Person", table: "people", id: "id", properties: %{id: "id", name: "name"}}]
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

  test "caller-owned DuckDB ADBC Arrow stream can be ingested without row conversion" do
    :ok = Adbc.download_driver(:duckdb)
    {:ok, db} = Adbc.Database.start_link(driver: :duckdb)
    {:ok, source} = Adbc.Connection.start_link(database: db)
    {:ok, sink} = Adbc.Connection.start_link(database: db)

    try do
      {:ok, _} = Adbc.Connection.query(source, "CREATE TABLE people(id BIGINT, name VARCHAR)")
      {:ok, _} = Adbc.Connection.query(source, "INSERT INTO people VALUES (9007199254740993, 'Ada'), (2, NULL)")
      assert {:ok, _} =
               OrchidDB.query_arrow(
                 source,
                 request("MATCH (p:Person) RETURN p.id AS id, p.name AS name ORDER BY id"),
                 fn stream ->
                   Adbc.Connection.bulk_insert!(sink, stream, table: "copied")
                 end
               )

      assert {:ok, result} = Adbc.Connection.query(sink, "SELECT id, name FROM copied ORDER BY id")
      assert Adbc.Result.to_map(result) == %{"id" => [2, 9007199254740993], "name" => [nil, "Ada"]}

      assert_raise RuntimeError, "consumer failed", fn ->
        OrchidDB.query_arrow(source, request("RETURN 1 AS answer"), fn _stream ->
          raise "consumer failed"
        end)
      end

      assert {:ok, _} = Adbc.Connection.query(source, "BEGIN")
      assert {:ok, _} = Adbc.Connection.query(source, "INSERT INTO people VALUES (3, 'transaction')")
      assert {:ok, _} = OrchidDB.query_arrow(source, request("MATCH (p:Person) RETURN p.id AS id"), fn stream ->
        Adbc.Connection.bulk_insert!(sink, stream, table: "transaction_snapshot")
      end)
      assert {:ok, result} = Adbc.Connection.query(sink, "SELECT count(*) AS n FROM transaction_snapshot")
      assert Adbc.Result.to_map(result) == %{"n" => [3]}
      assert {:ok, _} = Adbc.Connection.query(source, "ROLLBACK")
      assert {:ok, result} = Adbc.Connection.query(source, "SELECT count(*) AS n FROM people")
      assert Adbc.Result.to_map(result) == %{"n" => [2]}
      assert {:ok, result} = Adbc.Connection.query(source, "SELECT version() AS version")
      assert %{"version" => ["v" <> _]} = Adbc.Result.to_map(result)
    after
      GenServer.stop(source)
      GenServer.stop(sink)
      GenServer.stop(db)
    end
  end
end

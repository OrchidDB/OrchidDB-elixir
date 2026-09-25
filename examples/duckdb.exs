# The application owns database configuration and connection lifetime.
Adbc.download_driver!(:duckdb)
{:ok, database} = Adbc.Database.start_link(driver: :duckdb)
{:ok, connection} = Adbc.Connection.start_link(database: database)
{:ok, destination} = Adbc.Connection.start_link(database: database)

try do
  Adbc.Connection.query!(connection, "CREATE TABLE people(id BIGINT, name VARCHAR)")

  Adbc.Connection.query!(
    connection,
    "INSERT INTO people VALUES (9007199254740993, 'Ada'), (2, NULL)"
  )

  request = %{
    version: 1,
    dialect: "duckdb",
    language: "cypher",
    query: "MATCH (p:Person) RETURN p.id AS id, p.name AS name ORDER BY id",
    tables: [
      %{
        name: "people",
        columns: [%{name: "id", data_type: "int64"}, %{name: "name", data_type: "string"}]
      }
    ],
    nodes: [%{label: "Person", table: "people", id: "id", properties: %{id: "id", name: "name"}}]
  }

  {:ok, _} =
    OrchidDB.query_arrow(connection, request, fn stream ->
      # Native Arrow transfer; the pointer must not escape this callback.
      Adbc.Connection.bulk_insert!(destination, stream, table: "graph_result")
    end)

  # Materialize rows only to display this small example.
  destination
  |> Adbc.Connection.query!("SELECT * FROM graph_result ORDER BY id")
  |> Adbc.Result.to_map()
  |> IO.inspect()
after
  GenServer.stop(connection)
  GenServer.stop(destination)
  GenServer.stop(database)
end

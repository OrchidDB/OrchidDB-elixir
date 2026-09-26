# OrchidDB for Elixir

Compile graph queries to SQL with the shared database-free compiler. Optionally
execute on a caller-owned ADBC connection, exposing the native **Arrow C Stream**
to a callback. No DuckDB or other engine is bundled. No result data passes through
the compiler NIF, and no row or IPC conversion is required.

```elixir
# mix.exs
{:orchiddb, "~> 0.1.0"}
# Add {:adbc, "~> 0.12"} when using the Arrow execution convenience function.
```

Version 0.1.0 is published on Hex. Run the standalone example against that package:

```sh
cd examples
mix deps.get
export ORCHIDDB_NATIVE_LIBRARY=/absolute/path/liborchiddb_compiler.dylib
mix run compile.exs
mix run duckdb.exs
```

The small C NIF builds with your system compiler (`make`, Erlang headers and `cc`).
The [macOS ARM64 compiler archive](https://github.com/OrchidDB/OrchidDB-native/releases/download/v0.1.0/orchiddb-compiler-v0.1.0-aarch64-apple-darwin.tar.gz) supplies the library without a Rust build. Extract it and set the variable above to its `lib/liborchiddb_compiler.dylib`. For other platforms, build the matching compiler from
[OrchidDB-native](https://github.com/OrchidDB/OrchidDB-native) at `NATIVE_REVISION`;
its core revision must match `CORE_REVISION`. No compiler binary is downloaded
implicitly. The compiler uses a dirty CPU scheduler and its own Rust runtime.
One shared library remains loaded for the VM lifetime; switching it requires a VM restart.

```elixir
request = %{
  version: 1, dialect: "duckdb", language: "cypher",
  query: "MATCH (p:Person) RETURN p.name AS name",
  tables: [%{name: "people", columns: [
    %{name: "id", data_type: "int64"}, %{name: "name", data_type: "string"}]}],
  nodes: [%{label: "Person", table: "people", id: "id", properties: %{name: "name"}}]
}
{:ok, plan} = OrchidDB.compile(request)
# conn and destination are your configured ADBC connections.
OrchidDB.query_arrow(conn, request, fn arrow_stream ->
  Adbc.Connection.bulk_insert!(destination, arrow_stream, table: "result")
end)
```

The stream can be consumed once and is valid **only inside the callback**.
Do not return or retain its pointer. ADBC owns statement/stream cleanup; OrchidDB
never stops your connection or database process or alters transactions. Register
extensions/UDFs yourself, declaring matching function signatures in the request.
See [ADBC query_pointer](https://adbc.hexdocs.pm/Adbc.Connection.html#query_pointer/5).

Requests support `cypher`, `gremlin`, and `sparql`; mapping, schema, ontology and
function signatures follow core's JSON v1 compiler contract. DuckDB and PostgreSQL
SQL rendering are supported; no federation or native Gremlin executor is included.
Parameters are literals specialized into SQL; compile again after changing them.
Errors return `{:error, reason}`. The integration suite uses the real DuckDB ADBC driver to execute compiled graph
queries and ingest Arrow C Streams directly. It verifies int64 values, nulls,
caller transactions/rollback, connection reuse, and consumer-error cleanup.
Run `mix test` to download the DuckDB test driver and exercise the complete path.

## Release

`mix hex.build` creates the source package including the C NIF. Workflow
`release.yml` validates the matching version tag and publishes with the repository
secret `HEX_API_KEY` in environment `hex`. Hex package `orchiddb` version 0.1.0 is published. Compiler binaries are independently
released from OrchidDB-native and pinned here.

[GPL-3.0-only license](LICENSE.md).

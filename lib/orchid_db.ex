defmodule OrchidDB do
  @moduledoc """
  Compile graph queries against explicit table metadata. No database is opened by
  the compiler. `query_arrow/4` borrows a caller-owned ADBC connection and exposes
  its Arrow C Stream only for the duration of the callback.
  """
  @external_resource Path.expand("../CORE_REVISION", __DIR__)
  @core_revision File.read!(Path.expand("../CORE_REVISION", __DIR__)) |> String.trim()
  @doc "Compile a v1 request map to SQL. Requires ORCHIDDB_NATIVE_LIBRARY or :library."
  def compile(request, opts \\ []) when is_map(request) do
    path = Keyword.get(opts, :library) || System.get_env("ORCHIDDB_NATIVE_LIBRARY")

    if is_nil(path) do
      {:error, "Set ORCHIDDB_NATIVE_LIBRARY to the compiler shared library"}
    else
      with {:ok, json} <- Jason.encode(request),
           {:ok, response, revision} <- OrchidDB.Native.compile_json(to_string(path), json),
           :ok <- check_revision(revision),
           {:ok, decoded} <- Jason.decode(response) do
        case decoded do
          %{"ok" => true, "result" => %{"version" => 1} = result} -> {:ok, result}
          %{"ok" => false, "error" => error} -> {:error, error}
          _ -> {:error, "Unsupported compiler response"}
        end
      end
    end
  end

  defp check_revision(@core_revision), do: :ok
  defp check_revision(revision) when revision == @core_revision <> "-dirty", do: :ok
  defp check_revision(_), do: {:error, "Compiler core revision does not match this client"}

  @doc "Borrow a connection. The Arrow stream must be consumed inside callback."
  def query_arrow(connection, request, callback, opts \\ []) when is_function(callback, 1) do
    with {:ok, plan} <- compile(request, opts) do
      Adbc.Connection.query_pointer(connection, plan["sql"], callback)
    end
  end
end

defmodule OrchidDB.Example.MixProject do
  use Mix.Project
  def project do
    [app: :orchiddb_example, version: "0.1.0", elixir: "~> 1.15",
     deps: [{:orchiddb, "== 0.1.0"}, {:adbc, "~> 0.12"}]]
  end
  def application, do: [extra_applications: [:logger]]
end

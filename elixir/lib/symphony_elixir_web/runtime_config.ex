defmodule SymphonyElixirWeb.RuntimeConfig do
  @moduledoc false

  @endpoint Module.concat(["SymphonyElixirWeb", "Endpoint"])

  @spec orchestrator() :: GenServer.name()
  def orchestrator do
    endpoint_config(:orchestrator) || SymphonyElixir.Orchestrator
  end

  @spec snapshot_timeout_ms() :: pos_integer()
  def snapshot_timeout_ms do
    endpoint_config(:snapshot_timeout_ms) || 15_000
  end

  defp endpoint_config(key) when is_atom(key) do
    :symphony_elixir
    |> Application.get_env(@endpoint, [])
    |> Keyword.get(key)
  end
end

defmodule SymphonyElixir.AgentProvider.Capabilities do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Config
  alias SymphonyElixir.AgentProvider.ConfigResolver

  @spec adapter_capabilities(module()) :: [String.t()]
  def adapter_capabilities(adapter) when is_atom(adapter) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :capabilities, 0) do
      adapter.capabilities()
    else
      []
    end
  end

  @spec config_capabilities(Config.t()) :: [String.t()]
  def config_capabilities(%Config{} = config) do
    config
    |> ConfigResolver.adapter_for_config()
    |> adapter_capabilities()
  end

  @spec stateful_config?(Config.t()) :: boolean()
  def stateful_config?(%Config{} = config) do
    config
    |> config_capabilities()
    |> Enum.member?("agent.session.stateful")
  end

  @spec session_type(Config.t()) :: String.t()
  def session_type(%Config{} = config) do
    if stateful_config?(config), do: "stateful", else: "logical"
  end
end

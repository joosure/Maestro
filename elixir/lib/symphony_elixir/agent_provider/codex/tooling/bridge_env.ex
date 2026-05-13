defmodule SymphonyElixir.AgentProvider.Codex.Tooling.BridgeEnv do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.DynamicToolBridge

  @spec runtime(keyword()) :: {:ok, map()} | {:error, term()}
  def runtime(opts) when is_list(opts) do
    case Keyword.get(opts, :dynamic_tool_bridge_runtime) do
      %{daemon_bridge: _daemon_bridge} ->
        {:ok, %{}}

      _runtime ->
        DynamicToolBridge.runtime_env(opts)
    end
  end

  @spec remote(keyword()) :: map()
  def remote(opts) when is_list(opts) do
    case runtime(opts) do
      {:ok, env} -> env
      {:error, _reason} -> %{}
    end
  end
end

defmodule SymphonyElixir.Agent.Runtime.DynamicToolBridge.Environment do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Context

  @spec current_env(keyword()) :: {:ok, map()} | {:error, term()}
  def current_env(opts \\ []) when is_list(opts) do
    opts
    |> Context.from_opts()
    |> context_env()
    |> then(&{:ok, &1})
  rescue
    error ->
      {:error, {:agent_runtime_dynamic_tool_bridge_environment_failed, Exception.message(error)}}
  end

  @spec context_env(map()) :: map()
  def context_env(%{tool_environment: tool_environment}) when is_map(tool_environment), do: tool_environment
  def context_env(_context), do: %{}
end

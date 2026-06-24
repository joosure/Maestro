defmodule SymphonyElixir.Agent.Runtime.DynamicToolBridge do
  @moduledoc """
  Runtime-owned entrypoint for the Agent Dynamic Tool HTTP bridge.

  The Dynamic Tool bridge itself owns authentication and execution. This module
  owns the provider-process bridge lifecycle, runtime environment, transport
  selection, and metadata.
  """

  alias SymphonyElixir.Agent.DynamicTool.Bridge
  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.Runtime.DynamicToolBridge.Transport

  @type transport :: Transport.transport()
  @type runtime :: Transport.runtime()

  @spec start(keyword()) :: {:ok, runtime()} | {:error, term()}
  def start(opts \\ []) when is_list(opts) do
    with {:ok, runtime} <- Transport.build(opts),
         {:ok, tunnel} <- Transport.start_tunnel(runtime, opts) do
      {:ok, Map.put(runtime, :tunnel, tunnel)}
    end
  end

  @spec runtime_env(keyword()) :: {:ok, map()} | {:error, term()}
  def runtime_env(opts \\ []) when is_list(opts) do
    case Keyword.get(opts, :dynamic_tool_bridge_runtime) do
      %{env: env} when is_map(env) ->
        {:ok, env}

      _runtime ->
        runtime_env_without_runtime(opts)
    end
  end

  @spec stop(term()) :: :ok
  def stop(%{tunnel: tunnel, bridge_token: bridge_token}) do
    Transport.stop_tunnel(tunnel)
    Bridge.unregister_context(bridge_token)
  end

  def stop(%{bridge_token: bridge_token}), do: Bridge.unregister_context(bridge_token)
  def stop(%{tunnel: tunnel}), do: Transport.stop_tunnel(tunnel)
  def stop(_runtime), do: :ok

  @spec metadata(term()) :: map()
  defdelegate metadata(runtime), to: Transport

  @spec transport(keyword()) :: {:ok, transport()} | {:error, term()}
  defdelegate transport(opts), to: Transport, as: :resolve

  @spec transport_name(transport()) :: String.t()
  defdelegate transport_name(transport), to: Transport, as: :name

  defp runtime_env_without_runtime(opts) do
    if managed_runtime_required?(opts) do
      {:error, :dynamic_tool_bridge_runtime_required}
    else
      with {:ok, runtime} <- Transport.build(opts) do
        {:ok, runtime.env}
      end
    end
  end

  defp managed_runtime_required?(opts) do
    case Keyword.get(opts, :tool_context) do
      %Context{tool_specs: [_tool_spec | _rest]} -> true
      %{"tool_specs" => [_tool_spec | _rest]} -> true
      _tool_context -> false
    end
  end
end

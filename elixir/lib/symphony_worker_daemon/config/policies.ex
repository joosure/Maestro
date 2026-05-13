defmodule SymphonyWorkerDaemon.Config.Policies do
  @moduledoc false

  alias SymphonyWorkerDaemon.BridgeProxy.UpstreamPolicy
  alias SymphonyWorkerDaemon.CommandPolicy
  alias SymphonyWorkerDaemon.Config.Options

  @spec executable(keyword()) :: {:ok, map()} | {:error, String.t()}
  def executable(opts) when is_list(opts) do
    allow_any_executable? = Keyword.get(opts, :allow_any_executable, false)
    entries = Keyword.get_values(opts, :allow_executable)

    cond do
      allow_any_executable? and entries != [] ->
        {:error, "Pass either --allow-executable or --allow-any-executable, not both."}

      allow_any_executable? ->
        {:ok, %{allowed_executables: [], allow_any_executable?: true}}

      entries == [] ->
        {:error, "At least one --allow-executable is required for the worker daemon. Use --allow-any-executable only for isolated local development."}

      true ->
        case CommandPolicy.prepare_allowed_executables(entries) do
          {:ok, specs} -> {:ok, %{allowed_executables: specs, allow_any_executable?: false}}
          {:error, reason} -> {:error, "Invalid worker daemon executable allowlist: #{inspect(reason)}"}
        end
    end
  end

  @spec dynamic_tool_bridge(keyword()) :: {:ok, map()} | {:error, String.t()}
  def dynamic_tool_bridge(opts) when is_list(opts) do
    entries =
      opts
      |> Keyword.get_values(:allow_dynamic_tool_bridge_upstream)
      |> Enum.map(&Options.normalize_optional_string/1)
      |> Enum.reject(&is_nil/1)

    enabled? = Keyword.get(opts, :enable_dynamic_tool_bridge_proxy, false) or entries != []

    cond do
      enabled? and entries == [] ->
        {:error, "At least one --allow-dynamic-tool-bridge-upstream is required when the Dynamic Tool bridge proxy is enabled."}

      true ->
        case UpstreamPolicy.prepare_allowed_upstreams(entries) do
          {:ok, allowed_upstreams} ->
            {:ok,
             %{
               enable_dynamic_tool_bridge_proxy?: enabled?,
               allowed_dynamic_tool_bridge_upstreams: allowed_upstreams,
               allow_private_dynamic_tool_bridge_upstreams?: Keyword.get(opts, :allow_private_dynamic_tool_bridge_upstream, false)
             }}

          {:error, reason} ->
            {:error, "Invalid Dynamic Tool bridge upstream allowlist: #{inspect(reason)}"}
        end
    end
  end
end

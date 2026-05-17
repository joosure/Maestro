defmodule SymphonyElixir.AgentProvider.RuntimeStart do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential
  alias SymphonyElixir.Agent.DynamicTool.WorkflowPlan
  alias SymphonyElixir.Agent.Quota
  alias SymphonyElixir.Agent.Runtime
  alias SymphonyElixir.AgentProvider.Capabilities
  alias SymphonyElixir.AgentProvider.Config
  alias SymphonyElixir.AgentProvider.ConfigResolver
  alias SymphonyElixir.AgentProvider.Error
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Workflow.CapabilityNames

  @remote_worker_capability CapabilityNames.agent_runtime_remote_worker()

  @spec provider_start_opts(Config.t(), Path.t(), keyword()) :: {:ok, keyword()} | {:error, term()}
  def provider_start_opts(%Config{} = config, workspace, opts) when is_list(opts) do
    capabilities = Capabilities.config_capabilities(config)
    adapter = ConfigResolver.adapter_for_config(config)

    with {:ok, opts} <- put_provider_runtime_context(config, workspace, opts),
         {:ok, opts} <- put_dynamic_tool_context(config, opts),
         {:ok, opts} <- validate_runtime_capability(config, capabilities, workspace, opts),
         {:ok, opts} <- Credential.prepare_provider_start(config, adapter, capabilities, opts),
         {:ok, opts} <- Quota.preflight(config, adapter, capabilities, opts) do
      {:ok, opts}
    end
  end

  defp put_provider_runtime_context(%Config{} = config, workspace, opts) do
    if Keyword.has_key?(opts, :provider_runtime_context) do
      {:ok, opts}
    else
      runtime_opts = Keyword.put(opts, :agent_provider_kind, config.kind)

      case Runtime.provider_runtime_context(workspace, runtime_opts) do
        {:ok, runtime_context} ->
          executor_opts = runtime_context |> map_value(:executor_opts) |> normalize_executor_opts()

          {:ok,
           executor_opts
           |> Keyword.merge(opts)
           |> Keyword.put(:provider_runtime_context, runtime_context)
           |> Keyword.put(:agent_runtime_target, Map.get(runtime_context, :agent_runtime_target))}

        {:error, reason} ->
          {:error, provider_context_error(config, :start_session, reason)}
      end
    end
  end

  defp normalize_executor_opts(executor_opts) when is_list(executor_opts), do: executor_opts
  defp normalize_executor_opts(_executor_opts), do: []

  defp put_dynamic_tool_context(%Config{} = config, opts) do
    with {:ok, planner} <- dynamic_tool_workflow_planner(opts),
         {:ok, tool_context} <- planner.(opts) do
      emit_dynamic_tool_context_planned(config, tool_context, opts)
      {:ok, Keyword.put(opts, :tool_context, tool_context)}
    else
      {:error, reason} ->
        {:error, provider_context_error(config, :start_session, {:dynamic_tool_workflow_plan_failed, reason})}

      other ->
        {:error, provider_context_error(config, :start_session, {:dynamic_tool_workflow_plan_failed, {:unexpected_result, other}})}
    end
  end

  defp dynamic_tool_workflow_planner(opts) do
    case Keyword.get(opts, :dynamic_tool_workflow_planner, &WorkflowPlan.from_opts/1) do
      planner when is_function(planner, 1) -> {:ok, planner}
      planner -> {:error, {:invalid_dynamic_tool_workflow_planner, planner}}
    end
  end

  defp emit_dynamic_tool_context_planned(%Config{} = config, tool_context, opts) when is_map(tool_context) do
    tool_names = dynamic_tool_names(tool_context)

    ObsLogger.emit(:info, :dynamic_tool_context_planned, %{
      component: "dynamic_tool",
      agent_provider_kind: config.kind,
      run_id: Keyword.get(opts, :run_id),
      issue_id: issue_field(opts, :id),
      issue_identifier: issue_field(opts, :identifier),
      dynamic_tool_exposure: dynamic_tool_exposure(tool_context),
      dynamic_tool_count: length(tool_names),
      dynamic_tool_names: tool_names,
      result_summary: "tools=#{length(tool_names)} exposure=#{dynamic_tool_exposure(tool_context) || "unknown"}"
    })
  end

  defp emit_dynamic_tool_context_planned(_config, _tool_context, _opts), do: :ok

  defp dynamic_tool_names(tool_context) when is_map(tool_context) do
    tool_context
    |> Map.get(:tool_specs, Map.get(tool_context, "tool_specs", []))
    |> Enum.flat_map(fn
      %{"name" => name} when is_binary(name) -> [name]
      %{name: name} when is_binary(name) -> [name]
      _tool_spec -> []
    end)
    |> Enum.sort()
  end

  defp dynamic_tool_exposure(%{tool_plan: %{exposure: exposure}}) when is_atom(exposure),
    do: Atom.to_string(exposure)

  defp dynamic_tool_exposure(%{tool_plan: %{exposure: exposure}}) when is_binary(exposure), do: exposure

  defp dynamic_tool_exposure(%{"tool_plan" => %{"exposure" => exposure}}) when is_binary(exposure), do: exposure
  defp dynamic_tool_exposure(_tool_context), do: nil

  defp issue_field(opts, field) when is_list(opts) do
    case Keyword.get(opts, :issue) do
      %{^field => value} -> value
      issue when is_map(issue) -> Map.get(issue, to_string(field))
      _issue -> nil
    end
  end

  defp validate_runtime_capability(%Config{} = config, capabilities, workspace, opts) do
    case runtime_target(workspace, opts) do
      %Runtime.Target{placement: :ssh, worker_host: nil} = target ->
        {:error, provider_context_error(config, :start_session, {:agent_runtime_target_invalid, :missing_worker_host, runtime_target_details(target)})}

      %Runtime.Target{} = target ->
        if Runtime.Target.remote?(target) and @remote_worker_capability not in capabilities do
          {:error, remote_worker_unsupported_error(config, target)}
        else
          {:ok, opts}
        end
    end
  end

  defp runtime_target(workspace, opts) when is_binary(workspace) and is_list(opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %Runtime.Target{} = target ->
        target

      _target ->
        case opts |> Keyword.get(:provider_runtime_context, %{}) |> map_value(:agent_runtime_target) do
          %Runtime.Target{} = target ->
            target

          _target ->
            Runtime.Target.new(
              workspace_path: workspace,
              placement: Keyword.get(opts, :agent_runtime_placement),
              worker_host: Keyword.get(opts, :worker_host)
            )
        end
    end
  end

  defp remote_worker_unsupported_error(%Config{} = config, %Runtime.Target{} = target) do
    Error.new(%{
      provider: config.kind,
      operation: :start_session,
      code: :agent_provider_remote_unsupported,
      message: "Selected agent provider does not support remote worker placement",
      retryable?: false,
      details: %{
        capability: @remote_worker_capability,
        worker_placement: Atom.to_string(target.placement),
        worker_pool: target.worker_pool,
        worker_host: target.worker_host
      }
    })
  end

  defp runtime_target_details(%Runtime.Target{} = target) do
    %{
      worker_placement: Atom.to_string(target.placement),
      worker_pool: target.worker_pool,
      worker_host: target.worker_host,
      workspace_path: target.workspace_path
    }
  end

  defp provider_context_error(%Config{} = config, operation, reason) do
    Error.new(%{
      provider: config.kind,
      operation: operation,
      code: :agent_provider_config_invalid,
      message: "Invalid agent-provider runtime context",
      retryable?: false,
      details: %{reason_summary: Redaction.summarize(reason, 256)}
    })
  end

  defp map_value(nil, _key), do: nil
  defp map_value(map, key) when is_map(map), do: Map.get(map, key)
  defp map_value(_value, _key), do: nil
end

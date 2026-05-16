defmodule SymphonyElixir.ChangeProposalReconciliation.Producer.TrackerToolResultHandler do
  @moduledoc false

  alias SymphonyElixir.ChangeProposalReconciliation.{Contract, RouteContext, TrackerCallOptions}
  alias SymphonyElixir.ChangeProposalReconciliation.KnownTarget.Fields, as: KnownTargetFields
  alias SymphonyElixir.ChangeProposalReconciliation.Producer.TrackerToolResultFields, as: ToolFields
  alias SymphonyElixir.Config
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.ChangeProposalReference
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.Config, as: ReconciliationConfig

  @spec record_tracker_tool_result(map(), String.t() | nil, term(), term(), keyword()) :: :ok
  def record_tracker_tool_result(tracker, tool, arguments, result, opts \\ [])

  def record_tracker_tool_result(tracker, tool, arguments, {:success, _payload}, opts)
      when is_map(tracker) and is_binary(tool) and is_list(opts) do
    attach_capability = Contract.tracker_attach_change_proposal_capability()
    move_capability = Contract.tracker_move_issue_capability()

    case tracker_tool_capability(tracker, tool, opts) do
      ^attach_capability ->
        register_attach_target(tracker, tool, arguments, opts)

      ^move_capability ->
        register_review_transition_target(tracker, tool, arguments, opts)

      nil ->
        emit_ignored(tracker, tool, arguments, :missing_workflow_capability, %{}, opts)
        :ok

      _other_capability ->
        :ok
    end
  end

  def record_tracker_tool_result(_tracker, _tool, _arguments, _result, _opts), do: :ok

  defp register_attach_target(tracker, tool, arguments, opts) when is_map(arguments) do
    with {:ok, issue_id} <- required_string(arguments, KnownTargetFields.issue_id()),
         {:ok, url} <- required_string(arguments, KnownTargetFields.url()) do
      settings = settings(opts)
      repo = repo_config(settings, opts)

      attrs = %{
        KnownTargetFields.issue_id() => issue_id,
        KnownTargetFields.tracker_kind() => TrackerConfig.kind(tracker),
        KnownTargetFields.repo_provider_kind() => string_value(arguments, KnownTargetFields.repo_provider_kind()) || RepoProvider.current_kind(repo),
        KnownTargetFields.repository() => string_value(arguments, KnownTargetFields.repository()) || RepoConfig.repository(repo),
        KnownTargetFields.number() => string_value(arguments, KnownTargetFields.change_proposal_id()),
        KnownTargetFields.url() => url,
        KnownTargetFields.branch() => string_value(arguments, KnownTargetFields.branch()),
        KnownTargetFields.head_sha() => string_value(arguments, KnownTargetFields.head_sha())
      }

      register_known_target(attrs, tracker, tool, arguments, opts)
    else
      {:error, reason} ->
        emit_ignored(tracker, tool, arguments, reason_atom(reason), %{error: inspect(reason)}, opts)
        :ok
    end
  end

  defp register_attach_target(tracker, tool, arguments, opts) do
    emit_ignored(tracker, tool, arguments, :invalid_arguments, %{}, opts)
    :ok
  end

  defp register_review_transition_target(tracker, tool, arguments, opts) when is_map(arguments) do
    with {:ok, issue_id} <- required_string(arguments, KnownTargetFields.issue_id()),
         {:ok, settings} <- fetch_settings(opts),
         {:ok, %ReconciliationConfig{enabled?: true} = config} <- ReconciliationConfig.from_settings(settings),
         {:ok, [issue | _rest]} <- fetch_issue_states_by_ids(tracker, issue_id, opts),
         true <- source_route_issue?(settings, config, issue),
         {:ok, %ChangeProposalReference{} = reference} <- fetch_change_proposal_reference(tracker, issue, opts) do
      attrs = %{
        KnownTargetFields.issue_id() => issue_id,
        KnownTargetFields.tracker_kind() => TrackerConfig.kind(tracker),
        KnownTargetFields.repo_provider_kind() => RepoProvider.current_kind(settings.repo),
        KnownTargetFields.repository() => RepoConfig.repository(settings.repo),
        KnownTargetFields.number() => reference.number,
        KnownTargetFields.url() => reference.url,
        KnownTargetFields.branch() => reference.branch
      }

      register_known_target(attrs, tracker, tool, arguments, opts)
    else
      other ->
        emit_ignored(tracker, tool, arguments, ignored_reason(other), ignored_details(other), opts)
        :ok
    end
  end

  defp register_review_transition_target(tracker, tool, arguments, opts) do
    emit_ignored(tracker, tool, arguments, :invalid_arguments, %{}, opts)
    :ok
  end

  defp register_known_target(attrs, tracker, tool, arguments, opts) do
    opts
    |> Keyword.get(:register_known_target_fn, &SymphonyElixir.ChangeProposalReconciliation.register_known_target/2)
    |> then(& &1.(attrs, opts))
    |> case do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        emit_ignored(tracker, tool, arguments, :known_target_registration_failed, %{error: inspect(reason)}, opts)
        :ok

      _other ->
        :ok
    end
  end

  defp fetch_issue_states_by_ids(tracker, issue_id, opts) do
    opts
    |> Keyword.get(:tracker_fetch_issue_states_by_ids_fn, &Tracker.fetch_issue_states_by_ids/3)
    |> then(& &1.(tracker, [issue_id], TrackerCallOptions.fetch(opts)))
  end

  defp fetch_change_proposal_reference(tracker, issue, opts) do
    opts
    |> Keyword.get(:tracker_fetch_change_proposal_reference_fn, &Tracker.fetch_change_proposal_reference/3)
    |> then(& &1.(tracker, issue, TrackerCallOptions.fetch(opts)))
  end

  defp source_route_issue?(settings, %ReconciliationConfig{} = config, issue) do
    context = RouteContext.for_issue(settings, issue)

    case RouteContext.route_facts(issue, context) do
      %{route_key: route_key} -> route_key in config.source_routes
      _route_facts -> false
    end
  end

  defp tracker_tool_capability(tracker, tool, opts) when is_map(tracker) and is_binary(tool) and is_list(opts) do
    tool_context_capability(tool, Keyword.get(opts, :tool_context)) ||
      tracker_tool_spec_capability(tracker, tool)
  end

  defp tool_context_capability(tool, tool_context) when is_map(tool_context) do
    tool_context
    |> map_value(ToolFields.tool_metadata())
    |> tool_metadata(tool)
    |> workflow_capability()
  end

  defp tool_context_capability(_tool, _tool_context), do: nil

  defp tool_metadata(metadata, tool) when is_map(metadata), do: Map.get(metadata, tool)
  defp tool_metadata(_metadata, _tool), do: nil

  defp tracker_tool_spec_capability(tracker, tool) do
    tracker
    |> Tracker.dynamic_tools()
    |> Enum.find(fn spec -> string_value(spec, ToolFields.name()) == tool end)
    |> workflow_capability()
  end

  defp workflow_capability(spec) when is_map(spec) do
    string_value(spec, ToolFields.workflow_capability()) || string_value(spec, ToolFields.workflow_capability_snake())
  end

  defp workflow_capability(_spec), do: nil

  defp emit_ignored(tracker, tool, arguments, reason, fields, opts)
       when is_map(tracker) and is_atom(reason) and is_map(fields) and is_list(opts) do
    if emit_ignored?(reason, opts) do
      emit_ignored_event(tracker, tool, arguments, reason, fields, opts)
    end

    :ok
  end

  defp emit_ignored_event(tracker, tool, arguments, reason, fields, opts) do
    event_fields =
      fields
      |> Map.merge(%{
        component: Contract.component(),
        producer: Contract.producer(:tracker_tool_result),
        tracker_kind: TrackerConfig.kind(tracker),
        dynamic_tool_name: tool,
        issue_id: string_value(arguments, KnownTargetFields.issue_id()),
        ignore_reason: Contract.reason_name(reason)
      })

    opts
    |> Keyword.get(:emit_event_fn, &ObservabilityLogger.emit/3)
    |> then(& &1.(ignored_event_level(reason), Contract.event(:tracker_tool_result_ignored), event_fields))

    :ok
  end

  defp emit_ignored?(:missing_workflow_capability, opts), do: diagnostics_enabled?(opts)
  defp emit_ignored?(_reason, _opts), do: true

  defp ignored_event_level(:known_target_registration_failed), do: :warning
  defp ignored_event_level(_reason), do: :debug

  defp diagnostics_enabled?(opts) when is_list(opts) do
    Keyword.get(opts, :tracker_tool_result_diagnostics?, false) == true or
      Keyword.get(opts, :dynamic_tool_exposure) in [:diagnostics, ToolFields.diagnostics_exposure()] or
      tool_context_exposure(Keyword.get(opts, :tool_context)) == ToolFields.diagnostics_exposure()
  end

  defp tool_context_exposure(tool_context) when is_map(tool_context) do
    case tool_context |> map_value(ToolFields.tool_plan()) |> map_value(ToolFields.exposure()) do
      exposure when is_binary(exposure) -> exposure
      _exposure -> nil
    end
  end

  defp tool_context_exposure(_tool_context), do: nil

  defp ignored_reason({:error, {:missing_required_argument, _field}}), do: :missing_required_argument
  defp ignored_reason({:error, _reason}), do: :tracker_tool_result_unavailable
  defp ignored_reason({:ok, []}), do: :issue_not_found
  defp ignored_reason({:ok, %ReconciliationConfig{enabled?: false}}), do: :reconciliation_disabled
  defp ignored_reason({:ok, nil}), do: :change_proposal_reference_unavailable
  defp ignored_reason(false), do: :source_route_mismatch
  defp ignored_reason(_other), do: :tracker_tool_result_unavailable

  defp ignored_details({:error, reason}), do: %{error: inspect(reason)}
  defp ignored_details(_other), do: %{}

  defp reason_atom({:missing_required_argument, _field}), do: :missing_required_argument

  defp settings(opts) do
    case fetch_settings(opts) do
      {:ok, settings} -> settings
      {:error, _reason} -> %{}
    end
  end

  defp fetch_settings(opts) do
    case Keyword.fetch(opts, :settings) do
      {:ok, settings} when is_map(settings) -> {:ok, settings}
      _other -> Config.settings()
    end
  end

  defp repo_config(%{repo: repo}, _opts) when is_map(repo), do: repo

  defp repo_config(_settings, opts) do
    case Keyword.get(opts, :repo) do
      repo when is_map(repo) -> repo
      _repo -> %{}
    end
  end

  defp required_string(map, key) when is_map(map) and is_binary(key) do
    case string_value(map, key) do
      value when is_binary(value) -> {:ok, value}
      nil -> {:error, {:missing_required_argument, key}}
    end
  end

  defp string_value(map, key) when is_map(map) and is_binary(key) do
    map
    |> map_value(key)
    |> normalize_string()
  end

  defp string_value(_map, _key), do: nil

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp map_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(_value), do: nil
end

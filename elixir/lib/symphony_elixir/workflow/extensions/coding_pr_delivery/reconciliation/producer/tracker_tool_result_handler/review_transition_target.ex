defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.ReviewTransitionTarget do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProducerDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields, as: KnownTargetFields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference, as: KnownTargetReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.ReferenceExtractor
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config, as: ReconciliationConfig
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Events
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Payload
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.TargetRegistration
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Values
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.RouteContext
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.TrackerCallOptions

  @spec record(map(), String.t(), term(), term(), keyword()) :: :ok
  def record(tracker, tool, arguments, payload, opts) when is_map(arguments) do
    with {:ok, issue_id} <- Values.required_string(arguments, KnownTargetFields.issue_id()),
         {:ok, settings} <- fetch_settings(opts),
         {:ok, %ReconciliationConfig{enabled?: true} = config} <- ReconciliationConfig.from_settings(settings),
         {:ok, issue} <- move_result_issue(tracker, payload, issue_id, opts),
         true <- source_route_issue?(settings, config, issue),
         %KnownTargetReference{} = reference <- internal_change_proposal_reference(issue, opts) do
      attrs = %{
        KnownTargetFields.issue_id() => issue.id || normalize_issue_id(tracker, issue_id),
        KnownTargetFields.tracker_kind() => Defaults.tracker_kind(tracker),
        KnownTargetFields.repo_provider_kind() => Defaults.repo_provider_kind(settings.repo),
        KnownTargetFields.repository() => Defaults.repo_repository(settings.repo),
        KnownTargetFields.number() => reference.number,
        KnownTargetFields.url() => reference.url,
        KnownTargetFields.branch() => reference.branch
      }

      TargetRegistration.register(attrs, tracker, tool, arguments, opts)
    else
      other ->
        Events.ignored(tracker, tool, arguments, Events.ignored_reason(other), Events.ignored_details(other), opts)
    end
  end

  def record(tracker, tool, arguments, _payload, opts) do
    Events.ignored(tracker, tool, arguments, :invalid_arguments, %{}, opts)
  end

  defp fetch_settings(opts) do
    case Keyword.fetch(opts, :settings) do
      {:ok, settings} when is_map(settings) -> {:ok, settings}
      _other -> Defaults.settings()
    end
  end

  defp move_result_issue(tracker, payload, fallback_issue_id, opts) do
    case Payload.issue(payload) do
      %Issue{} = issue ->
        {:ok, issue}

      nil ->
        with {:ok, [issue | _rest]} <- fetch_issue_states_by_ids(tracker, fallback_issue_id, opts) do
          {:ok, issue}
        end
    end
  end

  defp fetch_issue_states_by_ids(tracker, issue_id, opts) do
    issue_id = normalize_issue_id(tracker, issue_id)

    opts
    |> Keyword.get(:tracker_fetch_issue_states_by_ids_fn, &Defaults.fetch_issue_states_by_ids/3)
    |> then(& &1.(tracker, [issue_id], TrackerCallOptions.fetch(opts)))
  end

  defp normalize_issue_id(tracker, issue_id) when is_map(tracker) and is_binary(issue_id) do
    Defaults.normalize_issue_id(tracker, issue_id)
  end

  defp source_route_issue?(settings, %ReconciliationConfig{} = config, issue) do
    context = RouteContext.for_issue(settings, issue)

    case RouteContext.route_facts(issue, context) do
      %{route_key: route_key} -> ReconciliationConfig.source_route?(config, route_key)
      _route_facts -> false
    end
  end

  defp internal_change_proposal_reference(%Issue{} = issue, opts) do
    case ReferenceExtractor.from_issue(issue) do
      nil -> known_target_reference(issue.id, opts)
      %KnownTargetReference{} = reference -> reference
    end
  end

  defp known_target_reference(issue_id, opts) when is_binary(issue_id) do
    with {:ok, registry_opts} <- known_target_registry_opts(opts) do
      registry_opts
      |> Keyword.put_new(:server, Keyword.get(opts, :known_target_registry, KnownTarget.Registry))
      |> then(&KnownTarget.Registry.get(issue_id, &1))
      |> case do
        %KnownTarget{} = target ->
          KnownTarget.reference(target)

        _target ->
          nil
      end
    end
  end

  defp known_target_reference(_issue_id, _opts), do: nil

  defp known_target_registry_opts(opts) do
    registry_opts = Keyword.get(opts, :known_target_registry_opts, [])

    if Keyword.keyword?(registry_opts) do
      {:ok, registry_opts}
    else
      {:error, {:invalid_known_target_registry_opts, registry_opts}}
    end
  end
end

defmodule SymphonyElixir.ChangeProposalReconciliation.Producer.Watcher do
  @moduledoc """
  Bounded runtime producer for known change-proposal targets.

  The watcher only inspects targets that were previously registered by a safe
  runtime source. It never scans tracker source routes or repo-provider pull
  request lists to discover unrelated work.
  """

  use GenServer

  alias SymphonyElixir.ChangeProposalReconciliation.{CandidateInbox, Contract, KnownTarget}
  alias SymphonyElixir.ChangeProposalReconciliation.KnownTarget.Fields
  alias SymphonyElixir.ChangeProposalReconciliation.KnownTarget.Observation
  alias SymphonyElixir.Config
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.RepoProvider.ChangeProposalInspector
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.Config, as: ReconciliationConfig

  @default_interval_ms 60_000
  @default_target_limit 100
  @default_enqueue_unchanged_after_ms 300_000

  defmodule State do
    @moduledoc false

    defstruct enabled?: false,
              interval_ms: nil,
              target_limit: nil,
              enqueue_unchanged_after_ms: nil,
              registry_module: nil,
              registry: nil,
              inbox: CandidateInbox,
              timer_ref: nil
  end

  @type run_result :: %{
          inspected_count: non_neg_integer(),
          enqueued_count: non_neg_integer(),
          changed_count: non_neg_integer(),
          due_count: non_neg_integer(),
          error_count: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts = merge_application_opts(opts)

    case Keyword.fetch(opts, :name) do
      {:ok, nil} ->
        GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))

      {:ok, name} ->
        GenServer.start_link(__MODULE__, opts, name: name)

      :error ->
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @spec run_once(keyword()) :: run_result()
  def run_once(opts \\ []) when is_list(opts) do
    now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.monotonic_time(:millisecond) end)
    registry_module = registry_module(opts)
    registry = registry_server(opts, registry_module)
    inbox = Keyword.get(opts, :inbox, CandidateInbox)
    target_limit = positive_integer(Keyword.get(opts, :target_limit), @default_target_limit)
    enqueue_unchanged_after_ms = non_negative_integer(Keyword.get(opts, :enqueue_unchanged_after_ms), @default_enqueue_unchanged_after_ms)
    inspector_opts = Keyword.get(opts, :inspector_opts, [])
    facts_fn = Keyword.get(opts, :change_proposal_facts_fn, &ChangeProposalInspector.facts/3)
    emit_event_fn = Keyword.get(opts, :emit_event_fn, &ObservabilityLogger.emit/3)

    case runtime_targeted_settings(opts) do
      {:ok, settings} ->
        repo_config = Keyword.get(opts, :repo, settings.repo)

        registry_module
        |> list_targets(registry, target_limit)
        |> Enum.reduce(empty_result(), fn %KnownTarget{} = target, result ->
          inspect_target(target, result, %{
            registry_module: registry_module,
            registry: registry,
            inbox: inbox,
            repo: repo_config,
            facts_fn: facts_fn,
            emit_event_fn: emit_event_fn,
            inspector_opts: inspector_opts,
            now_ms: now_ms,
            enqueue_unchanged_after_ms: enqueue_unchanged_after_ms
          })
        end)

      :skip ->
        empty_result()
    end
  end

  defp list_targets(registry_module, registry, target_limit) do
    registry_module.list_targets(server: registry, limit: target_limit)
  end

  defp runtime_targeted_settings(opts) do
    with {:ok, settings} <- settings(opts),
         {:ok, %ReconciliationConfig{enabled?: true, candidate_discovery: :runtime_targeted}} <-
           ReconciliationConfig.from_settings(settings) do
      {:ok, settings}
    else
      _other -> :skip
    end
  end

  defp settings(opts) do
    case Keyword.fetch(opts, :settings) do
      {:ok, settings} when is_map(settings) -> {:ok, settings}
      _other -> Config.settings()
    end
  end

  @spec tick(GenServer.server()) :: run_result()
  def tick(server \\ __MODULE__) do
    GenServer.call(server, :tick)
  end

  @impl true
  def init(opts) do
    registry_module = registry_module(opts)

    state = %State{
      enabled?: Keyword.get(opts, :enabled?, Keyword.get(opts, :enabled, false)) == true,
      interval_ms: positive_integer(Keyword.get(opts, :interval_ms), @default_interval_ms),
      target_limit: positive_integer(Keyword.get(opts, :target_limit), @default_target_limit),
      enqueue_unchanged_after_ms:
        non_negative_integer(
          Keyword.get(opts, :enqueue_unchanged_after_ms),
          @default_enqueue_unchanged_after_ms
        ),
      registry_module: registry_module,
      registry: registry_server(opts, registry_module),
      inbox: Keyword.get(opts, :inbox, CandidateInbox)
    }

    {:ok, schedule_if_enabled(state)}
  end

  @impl true
  def handle_call(:tick, _from, %State{} = state) do
    {:reply, run_once(state_opts(state)), state}
  end

  @impl true
  def handle_info(:poll, %State{} = state) do
    _result = run_once(state_opts(state))
    {:noreply, schedule_if_enabled(%{state | timer_ref: nil})}
  end

  defp inspect_target(%KnownTarget{} = target, result, context) do
    facts = context.facts_fn.(context.repo, KnownTarget.reference(target), context.inspector_opts)
    signature = Observation.signature(facts)
    changed? = target.last_observed_signature != signature
    due? = enqueue_due?(target, context.now_ms, context.enqueue_unchanged_after_ms)
    should_enqueue? = changed? or due?

    {enqueued?, enqueue_error?} =
      if should_enqueue? do
        enqueue_known_target(target, context)
      else
        {false, false}
      end

    observation_attrs =
      facts
      |> Observation.attrs()
      |> maybe_put(Fields.last_enqueued_at_ms(), if(enqueued?, do: context.now_ms, else: nil))

    update_result = update_observation(target, observation_attrs, context)

    update_error? = emit_update_failure(update_result, target, context)

    result
    |> Map.update!(:inspected_count, &(&1 + 1))
    |> Map.update!(:enqueued_count, &(&1 + if(enqueued?, do: 1, else: 0)))
    |> Map.update!(:changed_count, &(&1 + if(changed?, do: 1, else: 0)))
    |> Map.update!(:due_count, &(&1 + if(due?, do: 1, else: 0)))
    |> Map.update!(:error_count, &(&1 + error_count(update_error?, enqueue_error?)))
  rescue
    error ->
      emit_watcher_failed(target, context, ObservabilityLogger.error_details(error, __STACKTRACE__))

      result
      |> Map.update!(:inspected_count, &(&1 + 1))
      |> Map.update!(:error_count, &(&1 + 1))
  end

  defp enqueue_known_target(%KnownTarget{} = target, context) when is_map(context) do
    case CandidateInbox.enqueue_issue_ids([target.issue_id], server: context.inbox) do
      {:ok, %{dropped_count: dropped_count} = enqueue_result} when is_integer(dropped_count) and dropped_count > 0 ->
        emit_candidate_enqueue_dropped(target, enqueue_result, context)
        {false, true}

      {:ok, enqueue_result} when is_map(enqueue_result) ->
        {Map.get(enqueue_result, :accepted_count, 0) + Map.get(enqueue_result, :duplicate_count, 0) > 0, false}

      {:error, reason} ->
        emit_watcher_failed(target, context, %{error: inspect(reason), failure_reason: :candidate_inbox_unavailable})
        {false, true}
    end
  end

  defp emit_update_failure({:ok, _updated_target}, _target, _context), do: false

  defp emit_update_failure({:error, reason}, %KnownTarget{} = target, context) do
    emit_watcher_failed(target, context, %{error: inspect(reason), failure_reason: :known_target_update_failed})
    true
  end

  defp emit_update_failure(_result, _target, _context), do: false

  defp emit_candidate_enqueue_dropped(%KnownTarget{} = target, enqueue_result, context) when is_map(enqueue_result) do
    emit(
      context,
      :warning,
      Contract.event(:candidate_enqueue_dropped),
      Map.merge(target_fields(target), Map.put(enqueue_result, :producer, Contract.producer(:known_target_watcher)))
    )
  end

  defp emit_watcher_failed(%KnownTarget{} = target, context, fields) when is_map(context) and is_map(fields) do
    emit(
      context,
      :warning,
      Contract.event(:known_target_watcher_failed),
      Map.merge(target_fields(target), fields)
    )
  end

  defp emit(context, level, event, fields) when is_map(context) and is_atom(level) and is_atom(event) and is_map(fields) do
    context.emit_event_fn.(
      level,
      event,
      Map.merge(
        %{
          component: Contract.component(),
          producer: Contract.producer(:known_target_watcher)
        },
        normalize_event_fields(fields)
      )
    )
  end

  defp normalize_event_fields(fields) when is_map(fields) do
    case Map.fetch(fields, :failure_reason) do
      {:ok, reason} -> Map.put(fields, :failure_reason, Contract.reason_name(reason))
      :error -> fields
    end
  end

  defp target_fields(%KnownTarget{} = target) do
    %{
      issue_id: target.issue_id,
      tracker_kind: target.tracker_kind,
      repo_provider_kind: target.repo_provider_kind,
      repository: target.repository,
      change_proposal_number: target.number,
      change_proposal_url: target.url,
      change_proposal_branch: target.branch
    }
  end

  defp error_count(true, true), do: 2
  defp error_count(true, false), do: 1
  defp error_count(false, true), do: 1
  defp error_count(false, false), do: 0

  defp enqueue_due?(%KnownTarget{last_enqueued_at_ms: nil}, _now_ms, _enqueue_unchanged_after_ms), do: true

  defp enqueue_due?(%KnownTarget{last_enqueued_at_ms: last_enqueued_at_ms}, now_ms, enqueue_unchanged_after_ms)
       when is_integer(last_enqueued_at_ms) and is_integer(now_ms) and is_integer(enqueue_unchanged_after_ms) do
    now_ms - last_enqueued_at_ms >= enqueue_unchanged_after_ms
  end

  defp state_opts(%State{} = state) do
    [
      registry: state.registry,
      registry_module: state.registry_module,
      inbox: state.inbox,
      target_limit: state.target_limit,
      enqueue_unchanged_after_ms: state.enqueue_unchanged_after_ms
    ]
  end

  defp schedule_if_enabled(%State{enabled?: false} = state), do: state

  defp schedule_if_enabled(%State{enabled?: true, interval_ms: interval_ms} = state) do
    timer_ref = Process.send_after(self(), :poll, interval_ms)
    %{state | timer_ref: timer_ref}
  end

  defp empty_result do
    %{
      inspected_count: 0,
      enqueued_count: 0,
      changed_count: 0,
      due_count: 0,
      error_count: 0
    }
  end

  defp merge_application_opts(opts) do
    app_opts =
      :symphony_elixir
      |> Application.get_env(:change_proposal_known_target_watcher, [])
      |> normalize_keyword()

    Keyword.merge(app_opts, opts)
  end

  defp normalize_keyword(opts) when is_list(opts), do: opts
  defp normalize_keyword(_opts), do: []

  defp registry_module(opts) when is_list(opts) do
    case Keyword.get(opts, :registry_module) do
      module when is_atom(module) and not is_nil(module) -> module
      _module -> default_registry_module()
    end
  end

  defp registry_server(opts, registry_module) when is_list(opts) do
    case Keyword.get(opts, :registry) do
      nil -> registry_module
      server -> server
    end
  end

  defp default_registry_module, do: Module.safe_concat(KnownTarget, "Registry")

  defp update_observation(%KnownTarget{} = target, observation_attrs, context) when is_map(context) do
    context.registry_module.update_observation(
      target.issue_id,
      observation_attrs,
      server: context.registry,
      now_ms: context.now_ms
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default
end

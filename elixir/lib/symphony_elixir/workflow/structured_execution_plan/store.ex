defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store do
  @moduledoc """
  Process-local facade for canonical structured execution plan records.

  This store is intentionally separate from the state-transition readiness
  store. It is suitable for deterministic tests and local smoke behavior only;
  durable production storage is a later implementation phase.
  """

  use GenServer

  alias SymphonyElixir.Workflow.RouteRef
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Evidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.StatusMachine
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.WorkpadRenderer

  @default_max_records 10_000
  @default_provider_session_event_limit 50

  defmodule State do
    @moduledoc false

    defstruct plans: %{},
              active_index: %{},
              max_records: nil
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @spec create(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def create(plan, opts \\ []) when is_map(plan) and is_list(opts) do
    call(Keyword.get(opts, :server, __MODULE__), service_unavailable_error(), {:create, plan})
  end

  @spec fetch(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def fetch(plan_id, opts \\ []) when is_binary(plan_id) and is_list(opts) do
    call(Keyword.get(opts, :server, __MODULE__), plan_not_found_error(plan_id), {:fetch, plan_id})
  end

  @spec active_plan(String.t(), map(), String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def active_plan(run_id, workflow_profile, route_key, opts \\ [])
      when is_binary(run_id) and is_map(workflow_profile) and is_binary(route_key) and is_list(opts) do
    case RouteRef.storage_key(run_id, workflow_profile, route_key) do
      {:ok, active_key} ->
        call(
          Keyword.get(opts, :server, __MODULE__),
          plan_not_found_error(nil),
          {:active_plan, active_key}
        )

      {:error, reason} ->
        {:error, invalid_route_ref_error(reason)}
    end
  end

  @spec update_plan_status(String.t(), String.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def update_plan_status(plan_id, status, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_binary(status) and is_list(opts) do
    call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:update_plan_status, plan_id, status, expected_revision, opts}
    )
  end

  @spec update_item_status(String.t(), String.t(), String.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def update_item_status(plan_id, item_id, status, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_binary(item_id) and is_binary(status) and is_list(opts) do
    call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:update_item_status, plan_id, item_id, status, expected_revision, opts}
    )
  end

  @spec append_evidence_ref(String.t(), String.t(), map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def append_evidence_ref(plan_id, item_id, evidence_ref, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_binary(item_id) and is_map(evidence_ref) and is_list(opts) do
    call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:append_evidence_ref, plan_id, item_id, evidence_ref, expected_revision, opts}
    )
  end

  @spec upsert_agent_items(String.t(), [map()], pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def upsert_agent_items(plan_id, items, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_list(items) and is_list(opts) do
    call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:upsert_agent_items, plan_id, items, expected_revision, opts}
    )
  end

  @spec record_evidence_refs(String.t(), [map()], keyword()) :: {:ok, map()} | {:error, map()}
  def record_evidence_refs(plan_id, evidence_refs, opts \\ []) when is_binary(plan_id) and is_list(evidence_refs) and is_list(opts) do
    call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:record_evidence_refs, plan_id, evidence_refs, opts}
    )
  end

  @spec record_render_marker(String.t(), map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def record_render_marker(plan_id, marker, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_map(marker) and is_integer(expected_revision) and is_list(opts) do
    call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:record_render_marker, plan_id, marker, expected_revision}
    )
  end

  @spec record_provider_session_event(String.t(), map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def record_provider_session_event(plan_id, event, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_map(event) and is_integer(expected_revision) and is_list(opts) do
    call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:record_provider_session_event, plan_id, event, expected_revision, opts}
    )
  end

  @spec reset(keyword()) :: :ok
  def reset(opts \\ []) when is_list(opts) do
    call(Keyword.get(opts, :server, __MODULE__), :ok, :reset)
  end

  @impl true
  def init(opts) do
    {:ok, %State{max_records: positive_integer(Keyword.get(opts, :max_records), @default_max_records)}}
  end

  @impl true
  def handle_call({:create, plan}, _from, %State{} = state) do
    result =
      with {:ok, valid_plan} <- Schema.validate(plan),
           :ok <- ensure_plan_id_available(state, valid_plan),
           :ok <- ensure_active_slot_available(state, valid_plan) do
        {:ok, put_plan(state, valid_plan)}
      end

    case result do
      {:ok, next_state} -> {:reply, {:ok, plan}, next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:fetch, plan_id}, _from, %State{} = state) do
    {:reply, fetch_from_state(state, plan_id), state}
  end

  def handle_call({:active_plan, key}, _from, %State{} = state) do
    result =
      case Map.fetch(state.active_index, key) do
        {:ok, plan_id} -> fetch_from_state(state, plan_id)
        :error -> {:error, plan_not_found_error(nil)}
      end

    {:reply, result, state}
  end

  def handle_call({:update_plan_status, plan_id, next_status, expected_revision, opts}, _from, %State{} = state) do
    result =
      with {:ok, plan} <- fetch_from_state(state, plan_id),
           :ok <- ensure_revision(plan, expected_revision),
           :ok <- StatusMachine.validate_plan_transition(Map.get(plan, "status"), next_status),
           updated_plan <- bump_plan(plan, opts) |> Map.put("status", next_status),
           :ok <- ensure_active_slot_available(state, updated_plan, plan_id) do
        {:ok, put_plan(remove_active_index(state, plan), updated_plan)}
      end

    case result do
      {:ok, next_state} -> {:reply, fetch_from_state(next_state, plan_id), next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:update_item_status, plan_id, item_id, next_status, expected_revision, opts}, _from, %State{} = state) do
    result =
      with {:ok, plan} <- fetch_from_state(state, plan_id),
           :ok <- ensure_plan_mutable(plan),
           :ok <- ensure_revision(plan, expected_revision),
           {:ok, item} <- fetch_item(plan, item_id),
           :ok <- StatusMachine.validate_item_transition(Map.get(item, "status"), next_status),
           updated_plan <- update_item(plan, item_id, Map.put(bump_item(item, opts), "status", next_status), opts) do
        {:ok, put_plan(state, updated_plan)}
      end

    case result do
      {:ok, next_state} -> {:reply, fetch_from_state(next_state, plan_id), next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:append_evidence_ref, plan_id, item_id, evidence_ref, expected_revision, opts}, _from, %State{} = state) do
    result =
      with {:ok, plan} <- fetch_from_state(state, plan_id),
           :ok <- ensure_plan_mutable(plan),
           :ok <- ensure_revision(plan, expected_revision),
           {:ok, item} <- fetch_item(plan, item_id),
           {:ok, updated_item} <- Evidence.append_ref(item, evidence_ref) do
        if updated_item == item do
          {:ok, state}
        else
          {:ok, put_plan(state, update_item(plan, item_id, bump_item(updated_item, opts), opts))}
        end
      end

    case result do
      {:ok, next_state} -> {:reply, fetch_from_state(next_state, plan_id), next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:upsert_agent_items, plan_id, items, expected_revision, opts}, _from, %State{} = state) do
    result =
      with {:ok, plan} <- fetch_from_state(state, plan_id),
           :ok <- ensure_plan_mutable(plan),
           :ok <- ensure_revision(plan, expected_revision),
           :ok <- ensure_agent_items(items),
           {:ok, updated_plan} <- upsert_items(plan, items, opts),
           {:ok, valid_plan} <- Schema.validate(updated_plan) do
        {:ok, put_plan(state, valid_plan)}
      end

    case result do
      {:ok, next_state} -> {:reply, fetch_from_state(next_state, plan_id), next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:record_evidence_refs, plan_id, evidence_refs, opts}, _from, %State{} = state) do
    result =
      with {:ok, plan} <- fetch_from_state(state, plan_id),
           :ok <- ensure_plan_mutable(plan),
           {:ok, valid_refs} <- validate_evidence_refs(evidence_refs),
           :ok <- ensure_evidence_scope(plan, valid_refs),
           {:ok, updated_plan} <- record_refs_and_reconcile(plan, valid_refs, opts) do
        {:ok, put_plan(state, updated_plan)}
      end

    case result do
      {:ok, next_state} -> {:reply, fetch_from_state(next_state, plan_id), next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:record_render_marker, plan_id, marker, expected_revision}, _from, %State{} = state) do
    result =
      with {:ok, plan} <- fetch_from_state(state, plan_id),
           :ok <- ensure_plan_mutable(plan),
           :ok <- ensure_revision(plan, expected_revision),
           {:ok, valid_marker} <- WorkpadRenderer.validate_marker(marker, plan) do
        {:ok, put_plan(state, Map.put(plan, "rendering", valid_marker))}
      end

    case result do
      {:ok, next_state} -> {:reply, fetch_from_state(next_state, plan_id), next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:record_provider_session_event, plan_id, event, expected_revision, opts}, _from, %State{} = state) do
    result =
      with {:ok, plan} <- fetch_from_state(state, plan_id),
           :ok <- ensure_plan_mutable(plan),
           :ok <- ensure_revision(plan, expected_revision),
           {:ok, valid_event} <- ProviderSessionEvent.validate(event),
           {:ok, updated_plan} <- record_provider_session_event_on_plan(plan, valid_event, opts),
           {:ok, valid_plan} <- Schema.validate(updated_plan) do
        {:ok, put_plan(state, valid_plan)}
      end

    case result do
      {:ok, next_state} -> {:reply, fetch_from_state(next_state, plan_id), next_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:reset, _from, %State{} = state) do
    {:reply, :ok, %{state | plans: %{}, active_index: %{}}}
  end

  defp ensure_plan_id_available(%State{plans: plans}, %{"plan_id" => plan_id}) do
    if Map.has_key?(plans, plan_id) do
      {:error,
       %{
         code: "plan_conflict",
         message: "A structured execution plan with this plan_id already exists.",
         plan_id: plan_id
       }}
    else
      :ok
    end
  end

  defp ensure_active_slot_available(state, plan, current_plan_id \\ nil)

  defp ensure_active_slot_available(_state, %{"status" => status}, _current_plan_id) when status != "active", do: :ok

  defp ensure_active_slot_available(%State{} = state, plan, current_plan_id) do
    key = active_key(plan)

    case Map.fetch(state.active_index, key) do
      {:ok, ^current_plan_id} ->
        :ok

      {:ok, active_plan_id} ->
        {:error,
         %{
           code: "plan_conflict",
           message: "An active structured execution plan already exists for this run/profile/route.",
           active_plan_id: active_plan_id,
           run_id: Map.get(plan, "run_id"),
           route_key: Map.get(plan, "route_key")
         }}

      :error ->
        :ok
    end
  end

  defp ensure_revision(%{"revision" => revision}, expected_revision) when revision == expected_revision, do: :ok

  defp ensure_revision(%{"revision" => revision}, expected_revision) do
    {:error,
     %{
       code: "revision_conflict",
       message: "Structured execution plan revision does not match the caller-observed revision.",
       current_revision: revision,
       expected_revision: expected_revision
     }}
  end

  defp ensure_plan_mutable(%{"status" => status, "plan_id" => plan_id}) when status in ["closed", "superseded"] do
    {:error,
     %{
       code: "item_update_not_allowed",
       message: "Closed or superseded structured execution plans do not accept item updates.",
       plan_id: plan_id,
       status: status
     }}
  end

  defp ensure_plan_mutable(_plan), do: :ok

  defp ensure_agent_items(items) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case ensure_agent_item(item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_agent_item(%{"item_id" => item_id} = item) do
    cond do
      Map.get(item, "owned_by") != "agent" ->
        {:error, agent_item_rejected(item_id, "Agent plan tools can only upsert agent-owned items.")}

      Map.get(item, "source") != "agent" ->
        {:error, agent_item_rejected(item_id, "Agent plan tools can only upsert agent-sourced items.")}

      Map.get(item, "required") != false ->
        {:error, agent_item_rejected(item_id, "Agent plan tools cannot create required items.")}

      Map.get(item, "criticality") != "informational" ->
        {:error, agent_item_rejected(item_id, "Agent plan tools cannot create critical items.")}

      Map.get(item, "evidence_requirements") not in [nil, []] ->
        {:error, agent_item_rejected(item_id, "Agent plan tools cannot create evidence-bound items.")}

      Map.get(item, "evidence_refs") not in [nil, []] ->
        {:error, agent_item_rejected(item_id, "Agent plan tools cannot attach evidence through item upsert.")}

      true ->
        :ok
    end
  end

  defp ensure_agent_item(_item) do
    {:error,
     %{
       code: "schema_invalid",
       message: "Agent item upsert requires item objects with item_id."
     }}
  end

  defp agent_item_rejected(item_id, message) do
    %{
      code: "item_update_not_allowed",
      message: message,
      item_id: item_id
    }
  end

  defp upsert_items(plan, items, opts) do
    original_items = Map.fetch!(plan, "items")

    with {:ok, updated_items} <-
           Enum.reduce_while(items, {:ok, original_items}, fn item, {:ok, current_items} ->
             case upsert_item(current_items, item, opts) do
               {:ok, next_items} -> {:cont, {:ok, next_items}}
               {:error, reason} -> {:halt, {:error, reason}}
             end
           end) do
      if updated_items == original_items do
        {:ok, plan}
      else
        {:ok, plan |> bump_plan(opts) |> Map.put("items", updated_items)}
      end
    end
  end

  defp upsert_item(items, item, opts) do
    item_id = Map.fetch!(item, "item_id")

    case Enum.find_index(items, &(Map.get(&1, "item_id") == item_id)) do
      nil ->
        {:ok, items ++ [item]}

      index ->
        existing_item = Enum.at(items, index)

        if agent_owned_item?(existing_item) do
          updated_item =
            item
            |> Map.put("created_at", Map.get(existing_item, "created_at", Map.get(item, "created_at")))
            |> Map.put("revision", Map.get(existing_item, "revision", 0) + 1)
            |> maybe_put_updated_at(opts)

          {:ok, List.replace_at(items, index, updated_item)}
        else
          {:error,
           %{
             code: "item_update_not_allowed",
             message: "Agent plan tools cannot replace profile-owned or backend-owned items.",
             item_id: item_id
           }}
        end
    end
  end

  defp agent_owned_item?(item) do
    Map.get(item, "owned_by") == "agent" and
      Map.get(item, "source") == "agent" and
      Map.get(item, "required") == false and
      Map.get(item, "criticality") == "informational"
  end

  defp validate_evidence_refs(evidence_refs) do
    Enum.reduce_while(evidence_refs, {:ok, []}, fn evidence_ref, {:ok, refs} ->
      case Evidence.validate_ref(evidence_ref) do
        {:ok, ref} -> {:cont, {:ok, refs ++ [ref]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_evidence_scope(plan, evidence_refs) do
    Enum.reduce_while(evidence_refs, :ok, fn ref, :ok ->
      cond do
        Map.get(ref, "run_id") != Map.get(plan, "run_id") ->
          {:halt,
           {:error,
            %{
              code: "cross_run_evidence_not_allowed",
              message: "Structured execution plan evidence must belong to the plan run.",
              plan_run_id: Map.get(plan, "run_id"),
              evidence_run_id: Map.get(ref, "run_id")
            }}}

        Map.get(ref, "issue_id") not in [Map.get(plan, "issue_id"), Map.get(plan, "issue_identifier")] ->
          {:halt,
           {:error,
            %{
              code: "cross_issue_evidence_not_allowed",
              message: "Structured execution plan evidence must belong to the plan issue.",
              plan_issue_id: Map.get(plan, "issue_id"),
              evidence_issue_id: Map.get(ref, "issue_id")
            }}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp record_refs_and_reconcile(plan, evidence_refs, opts) do
    original_items = Map.fetch!(plan, "items")

    with {:ok, items_with_refs} <- record_matching_refs(original_items, evidence_refs),
         {:ok, reconciled_plan} <- Reconciler.reconcile(Map.put(plan, "items", items_with_refs)) do
      reconciled_items = Map.fetch!(reconciled_plan, "items")

      if original_items == reconciled_items do
        {:ok, plan}
      else
        {:ok,
         plan
         |> bump_plan(opts)
         |> Map.put("items", bump_changed_items(original_items, reconciled_items, opts))}
      end
    end
  end

  defp record_matching_refs(items, evidence_refs) when is_list(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, updated_items} ->
      case record_item_matching_refs(item, evidence_refs) do
        {:ok, updated_item} -> {:cont, {:ok, [updated_item | updated_items]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, updated_items} -> {:ok, Enum.reverse(updated_items)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_item_matching_refs(%{"status" => "superseded"} = item, _evidence_refs), do: {:ok, item}

  defp record_item_matching_refs(item, evidence_refs) when is_map(item) do
    Enum.reduce_while(evidence_refs, {:ok, item}, fn evidence_ref, {:ok, current_item} ->
      if accepts_evidence_ref?(current_item, evidence_ref) do
        append_matching_ref(current_item, evidence_ref)
      else
        {:cont, {:ok, current_item}}
      end
    end)
  end

  defp accepts_evidence_ref?(item, evidence_ref) do
    item
    |> Map.get("evidence_requirements", [])
    |> Enum.any?(fn
      %{"evidence_kind" => evidence_kind, "trust_classes" => trust_classes} ->
        evidence_kind == Map.get(evidence_ref, "evidence_kind") and Map.get(evidence_ref, "source") in trust_classes

      _requirement ->
        false
    end)
  end

  defp append_matching_ref(item, evidence_ref) do
    case attached_evidence_ref(item, evidence_ref) do
      nil ->
        case Evidence.append_ref(item, evidence_ref) do
          {:ok, updated_item} -> {:cont, {:ok, updated_item}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      attached_ref ->
        if idempotent_evidence_replay?(attached_ref, evidence_ref) do
          {:cont, {:ok, item}}
        else
          {:halt,
           {:error,
            %{
              code: "evidence_ref_conflict",
              message: "Evidence references are immutable once attached.",
              evidence_id: Map.fetch!(evidence_ref, "evidence_id")
            }}}
        end
    end
  end

  defp attached_evidence_ref(item, evidence_ref) do
    evidence_id = Map.fetch!(evidence_ref, "evidence_id")

    item
    |> Map.get("evidence_refs", [])
    |> Enum.find(&(Map.get(&1, "evidence_id") == evidence_id))
  end

  defp idempotent_evidence_replay?(attached_ref, evidence_ref) do
    Map.drop(attached_ref, ["observed_at"]) == Map.drop(evidence_ref, ["observed_at"])
  end

  defp bump_changed_items(original_items, reconciled_items, opts) do
    Enum.zip(original_items, reconciled_items)
    |> Enum.map(fn
      {item, item} -> item
      {_original_item, reconciled_item} -> bump_item(reconciled_item, opts)
    end)
  end

  defp record_provider_session_event_on_plan(plan, event, opts) do
    extension_key = ProviderSessionEvent.extension_key()
    extensions = Map.get(plan, "extensions", %{})
    events = provider_session_events(extensions, extension_key)

    case Enum.find(events, &(Map.get(&1, "event_id") == Map.get(event, "event_id"))) do
      nil ->
        updated_extensions =
          Map.put(extensions, extension_key, Enum.take([event | events], provider_session_event_limit(opts)))

        {:ok,
         plan
         |> bump_plan(opts)
         |> Map.put("extensions", updated_extensions)}

      ^event ->
        {:ok, plan}

      _existing_event ->
        {:error,
         %{
           code: "provider_session_event_conflict",
           message: "Provider session events are immutable once recorded.",
           event_id: Map.get(event, "event_id")
         }}
    end
  end

  defp provider_session_events(extensions, extension_key) when is_map(extensions) do
    case Map.get(extensions, extension_key) do
      events when is_list(events) -> events
      _events -> []
    end
  end

  defp provider_session_event_limit(opts) do
    opts
    |> Keyword.get(:provider_session_event_limit, @default_provider_session_event_limit)
    |> positive_integer(@default_provider_session_event_limit)
  end

  defp fetch_from_state(%State{plans: plans}, plan_id) do
    case Map.fetch(plans, plan_id) do
      {:ok, plan} -> {:ok, plan}
      :error -> {:error, plan_not_found_error(plan_id)}
    end
  end

  defp fetch_item(%{"items" => items}, item_id) do
    case Enum.find(items, &(Map.get(&1, "item_id") == item_id)) do
      nil ->
        {:error,
         %{
           code: "item_not_found",
           message: "Structured execution plan item was not found.",
           item_id: item_id
         }}

      item ->
        {:ok, item}
    end
  end

  defp put_plan(%State{} = state, plan) do
    plans =
      state.plans
      |> Map.put(Map.fetch!(plan, "plan_id"), plan)
      |> enforce_limit(state.max_records)

    %{state | plans: plans}
    |> rebuild_active_index()
  end

  defp remove_active_index(%State{} = state, %{"status" => "active"} = plan) do
    %{state | active_index: Map.delete(state.active_index, active_key(plan))}
  end

  defp remove_active_index(%State{} = state, _plan), do: state

  defp rebuild_active_index(%State{} = state) do
    active_index =
      state.plans
      |> Map.values()
      |> Enum.filter(&(Map.get(&1, "status") == "active"))
      |> Map.new(fn plan -> {active_key(plan), Map.fetch!(plan, "plan_id")} end)

    %{state | active_index: active_index}
  end

  defp update_item(plan, item_id, updated_item, opts) do
    items =
      Enum.map(Map.fetch!(plan, "items"), fn item ->
        if Map.get(item, "item_id") == item_id, do: updated_item, else: item
      end)

    plan
    |> bump_plan(opts)
    |> Map.put("items", items)
  end

  defp bump_plan(plan, opts) do
    plan
    |> Map.update!("revision", &(&1 + 1))
    |> maybe_put_updated_at(opts)
  end

  defp bump_item(item, opts) do
    item
    |> Map.update!("revision", &(&1 + 1))
    |> maybe_put_updated_at(opts)
  end

  defp maybe_put_updated_at(record, opts) do
    case Keyword.get(opts, :updated_at) do
      timestamp when is_binary(timestamp) -> Map.put(record, "updated_at", timestamp)
      _timestamp -> record
    end
  end

  defp active_key(%{"run_id" => run_id, "workflow_profile" => workflow_profile, "route_key" => route_key}) do
    active_key(run_id, workflow_profile, route_key)
  end

  defp active_key(run_id, workflow_profile, route_key) do
    case RouteRef.storage_key(run_id, workflow_profile, route_key) do
      {:ok, active_key} -> active_key
      {:error, reason} -> raise ArgumentError, "invalid structured plan route ref: #{inspect(reason)}"
    end
  end

  defp enforce_limit(plans, max_records) when map_size(plans) <= max_records, do: plans

  defp enforce_limit(plans, max_records) do
    plans
    |> Enum.take(-max_records)
    |> Map.new()
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp call(server, default, message) when is_atom(server) do
    case Process.whereis(server) do
      pid when is_pid(pid) -> safe_call(default, fn -> GenServer.call(server, message) end)
      _pid -> default
    end
  end

  defp call(server, default, message) when is_pid(server), do: safe_call(default, fn -> GenServer.call(server, message) end)
  defp call(_server, default, _message), do: default

  defp safe_call(default, fun) do
    fun.()
  catch
    :exit, _reason -> default
  end

  defp plan_not_found_error(nil) do
    %{code: "plan_not_found", message: "Structured execution plan was not found."}
  end

  defp plan_not_found_error(plan_id) do
    %{code: "plan_not_found", message: "Structured execution plan was not found.", plan_id: plan_id}
  end

  defp invalid_route_ref_error(reason) do
    %{code: "invalid_route_ref", message: "Structured execution plan route reference is invalid.", reason: inspect(reason)}
  end

  defp service_unavailable_error do
    %{code: "store_unavailable", message: "Structured execution plan store is not running."}
  end
end

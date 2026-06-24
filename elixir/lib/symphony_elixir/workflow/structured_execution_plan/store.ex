defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store do
  @moduledoc """
  Public API facade for workflow structured execution plan adoption records.

  Process callbacks live in `Store.Server`, command transactions live in
  `Store.Commands`, and persistence reads/writes live in `Store.Persistence`.
  """

  alias SymphonyElixir.Workflow.RouteRef
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Client
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Errors
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Server

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [Keyword.delete(opts, :id)]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  defdelegate start_link(opts \\ []), to: Server

  @spec create(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def create(plan, opts \\ []) when is_map(plan) and is_list(opts) do
    Client.call(Keyword.get(opts, :server, __MODULE__), service_unavailable_error(), {:create, plan})
  end

  @spec fetch(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def fetch(plan_id, opts \\ []) when is_binary(plan_id) and is_list(opts) do
    Client.call(Keyword.get(opts, :server, __MODULE__), plan_not_found_error(plan_id), {:fetch, plan_id})
  end

  @spec active_plan(String.t(), map(), String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def active_plan(run_id, workflow_profile, route_key, opts \\ [])
      when is_binary(run_id) and is_map(workflow_profile) and is_binary(route_key) and is_list(opts) do
    case RouteRef.storage_key(run_id, workflow_profile, route_key) do
      {:ok, active_key} ->
        Client.call(
          Keyword.get(opts, :server, __MODULE__),
          plan_not_found_error(nil),
          {:active_plan, active_key}
        )

      {:error, reason} ->
        {:error, invalid_route_ref_error(reason)}
    end
  end

  @spec plan_not_found_error(String.t() | nil) :: map()
  def plan_not_found_error(plan_id), do: Errors.plan_not_found(plan_id)

  @spec update_plan_status(String.t(), String.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def update_plan_status(plan_id, status, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_binary(status) and is_list(opts) do
    Client.call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:update_plan_status, plan_id, status, expected_revision, opts}
    )
  end

  @spec update_item_status(String.t(), String.t(), String.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def update_item_status(plan_id, item_id, status, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_binary(item_id) and is_binary(status) and is_list(opts) do
    Client.call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:update_item_status, plan_id, item_id, status, expected_revision, opts}
    )
  end

  @spec append_evidence_ref(String.t(), String.t(), map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def append_evidence_ref(plan_id, item_id, evidence_ref, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_binary(item_id) and is_map(evidence_ref) and is_list(opts) do
    Client.call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:append_evidence_ref, plan_id, item_id, evidence_ref, expected_revision, opts}
    )
  end

  @spec upsert_agent_items(String.t(), [map()], pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def upsert_agent_items(plan_id, items, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_list(items) and is_list(opts) do
    Client.call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:upsert_agent_items, plan_id, items, expected_revision, opts}
    )
  end

  @spec record_evidence_refs(String.t(), [map()], keyword()) :: {:ok, map()} | {:error, map()}
  def record_evidence_refs(plan_id, evidence_refs, opts \\ []) when is_binary(plan_id) and is_list(evidence_refs) and is_list(opts) do
    Client.call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:record_evidence_refs, plan_id, evidence_refs, opts}
    )
  end

  @spec record_render_marker(String.t(), map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def record_render_marker(plan_id, marker, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_map(marker) and is_integer(expected_revision) and is_list(opts) do
    Client.call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:record_render_marker, plan_id, marker, expected_revision}
    )
  end

  @spec record_provider_session_event(String.t(), map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def record_provider_session_event(plan_id, event, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_map(event) and is_integer(expected_revision) and is_list(opts) do
    Client.call(
      Keyword.get(opts, :server, __MODULE__),
      service_unavailable_error(),
      {:record_provider_session_event, plan_id, event, expected_revision, opts}
    )
  end

  @spec reset(keyword()) :: :ok
  def reset(opts \\ []) when is_list(opts) do
    Client.call(Keyword.get(opts, :server, __MODULE__), :ok, :reset)
  end

  defp invalid_route_ref_error(reason), do: Errors.invalid_route_ref(reason)
  defp service_unavailable_error, do: Errors.service_unavailable()
end

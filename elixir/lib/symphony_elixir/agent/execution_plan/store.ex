defmodule SymphonyElixir.Agent.ExecutionPlan.Store do
  @moduledoc """
  Public facade for provider-neutral `agent.execution_plan.v1` storage.

  The facade owns the stable API only. `Store.Server` owns the GenServer process,
  `Store.Commands` owns domain mutations, and storage backends remain behind the
  `ExecutionPlan.Storage` behaviour.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Store.Client

  alias SymphonyElixir.Agent.ExecutionPlan.Store.Command.{
    AppendEvidenceRef,
    Create,
    Delete,
    Fetch,
    Replace,
    Reset,
    UpdateItemStatus,
    UpdatePlanStatus,
    UpsertAgentItems
  }

  alias SymphonyElixir.Agent.ExecutionPlan.Store.ErrorResults
  alias SymphonyElixir.Agent.ExecutionPlan.Store.Server

  @client_option_keys [:server]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: Server.start_link(opts, __MODULE__)

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @spec create(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def create(plan, opts \\ []) when is_map(plan) and is_list(opts) do
    call(opts, store_unavailable(), %Create{plan: plan, opts: command_opts(opts)})
  end

  @spec fetch(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def fetch(plan_id, opts \\ []) when is_binary(plan_id) and is_list(opts) do
    call(opts, store_unavailable(), %Fetch{plan_id: plan_id})
  end

  @spec delete(String.t(), keyword()) :: :ok | {:error, map()}
  def delete(plan_id, opts \\ []) when is_binary(plan_id) and is_list(opts) do
    call(opts, store_unavailable(), %Delete{plan_id: plan_id})
  end

  @spec replace(String.t(), map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def replace(plan_id, plan, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_map(plan) and is_integer(expected_revision) and is_list(opts) do
    call(opts, store_unavailable(), %Replace{
      plan_id: plan_id,
      replacement: plan,
      expected_revision: expected_revision,
      opts: command_opts(opts)
    })
  end

  @spec update_plan_status(String.t(), String.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def update_plan_status(plan_id, status, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_binary(status) and is_integer(expected_revision) and is_list(opts) do
    call(opts, store_unavailable(), %UpdatePlanStatus{
      plan_id: plan_id,
      next_status: status,
      expected_revision: expected_revision,
      opts: command_opts(opts)
    })
  end

  @spec update_item_status(String.t(), String.t(), String.t(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def update_item_status(plan_id, item_id, status, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_binary(item_id) and is_binary(status) and is_integer(expected_revision) and is_list(opts) do
    call(opts, store_unavailable(), %UpdateItemStatus{
      plan_id: plan_id,
      item_id: item_id,
      next_status: status,
      expected_revision: expected_revision,
      opts: command_opts(opts)
    })
  end

  @spec append_evidence_ref(String.t(), String.t(), map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def append_evidence_ref(plan_id, item_id, evidence_ref, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_binary(item_id) and is_map(evidence_ref) and is_integer(expected_revision) and is_list(opts) do
    call(opts, store_unavailable(), %AppendEvidenceRef{
      plan_id: plan_id,
      item_id: item_id,
      evidence_ref: evidence_ref,
      expected_revision: expected_revision,
      opts: command_opts(opts)
    })
  end

  @spec upsert_agent_items(String.t(), [map()], pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def upsert_agent_items(plan_id, items, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_list(items) and is_integer(expected_revision) and is_list(opts) do
    call(opts, store_unavailable(), %UpsertAgentItems{
      plan_id: plan_id,
      items: items,
      expected_revision: expected_revision,
      opts: command_opts(opts)
    })
  end

  @spec reset(keyword()) :: :ok | {:error, map()}
  def reset(opts \\ []) when is_list(opts) do
    call(opts, store_unavailable(), %Reset{})
  end

  defp call(opts, default, command), do: Client.call(client_opts(opts), __MODULE__, default, command)

  defp client_opts(opts), do: Keyword.take(opts, @client_option_keys)
  defp command_opts(opts), do: Keyword.drop(opts, @client_option_keys)
  defp store_unavailable, do: {:error, ErrorResults.store_unavailable()}
end

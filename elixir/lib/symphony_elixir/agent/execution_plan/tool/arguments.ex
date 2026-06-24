defmodule SymphonyElixir.Agent.ExecutionPlan.Tool.Arguments do
  @moduledoc """
  Raw argument boundary for generic Agent execution-plan tools.

  Public functions parse external Dynamic Tool argument maps into stable command
  structs. Runtime modules should consume these command structs instead of
  re-reading raw string-keyed input.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields

  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Command.{
    AppendEvidenceRef,
    Create,
    MergeItems,
    Snapshot,
    UpdateItem
  }

  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Contract
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Payload

  @type upsert_args :: Create.t() | MergeItems.t()

  @spec snapshot(term()) :: {:ok, Snapshot.t()} | {:error, term()}
  def snapshot(arguments) when is_map(arguments) do
    with :ok <- reject_unknown_fields(arguments, [Fields.plan_id()]),
         {:ok, plan_id} <- required_string(arguments, Fields.plan_id()) do
      {:ok, %Snapshot{plan_id: plan_id}}
    end
  end

  def snapshot(_arguments), do: {:error, {:invalid_arguments, "Expected an object for Agent execution plan snapshot."}}

  @spec upsert(term()) :: {:ok, upsert_args()} | {:error, term()}
  def upsert(arguments) when is_map(arguments) do
    with :ok <- reject_unknown_fields(arguments, [Contract.plan_arg(), Fields.plan_id(), Contract.plan_revision_arg(), Fields.items()]) do
      cond do
        is_map(Map.get(arguments, Contract.plan_arg())) ->
          with {:ok, plan} <- Payload.plan(Map.fetch!(arguments, Contract.plan_arg())) do
            {:ok, %Create{plan: plan}}
          end

        true ->
          with {:ok, plan_id} <- required_string(arguments, Fields.plan_id()),
               {:ok, plan_revision} <- required_positive_integer(arguments, Contract.plan_revision_arg()),
               {:ok, items} <- Payload.item_set(Map.get(arguments, Fields.items())) do
            {:ok, %MergeItems{plan_id: plan_id, plan_revision: plan_revision, items: items}}
          end
      end
    end
  end

  def upsert(_arguments), do: {:error, {:invalid_arguments, "Expected an object for Agent execution plan upsert."}}

  @spec update_item(term()) :: {:ok, UpdateItem.t()} | {:error, term()}
  def update_item(arguments) when is_map(arguments) do
    with :ok <- reject_unknown_fields(arguments, [Fields.plan_id(), Fields.item_id(), Fields.status(), Contract.plan_revision_arg()]),
         {:ok, plan_id} <- required_string(arguments, Fields.plan_id()),
         {:ok, item_id} <- required_string(arguments, Fields.item_id()),
         {:ok, status} <- required_string(arguments, Fields.status()),
         {:ok, plan_revision} <- required_positive_integer(arguments, Contract.plan_revision_arg()) do
      {:ok, %UpdateItem{plan_id: plan_id, item_id: item_id, status: status, plan_revision: plan_revision}}
    end
  end

  def update_item(_arguments), do: {:error, {:invalid_arguments, "Expected an object for Agent execution plan item update."}}

  @spec append_evidence(term()) :: {:ok, AppendEvidenceRef.t()} | {:error, term()}
  def append_evidence(arguments) when is_map(arguments) do
    with :ok <- reject_unknown_fields(arguments, [Fields.plan_id(), Fields.item_id(), Contract.evidence_ref_arg(), Contract.plan_revision_arg()]),
         {:ok, plan_id} <- required_string(arguments, Fields.plan_id()),
         {:ok, item_id} <- required_string(arguments, Fields.item_id()),
         {:ok, evidence_ref_map} <- required_map(arguments, Contract.evidence_ref_arg()),
         {:ok, evidence_ref} <- Payload.evidence_ref(evidence_ref_map),
         {:ok, plan_revision} <- required_positive_integer(arguments, Contract.plan_revision_arg()) do
      {:ok, %AppendEvidenceRef{plan_id: plan_id, item_id: item_id, evidence_ref: evidence_ref, plan_revision: plan_revision}}
    end
  end

  def append_evidence(_arguments), do: {:error, {:invalid_arguments, "Expected an object for Agent execution plan evidence append."}}

  defp required_string(map, key) do
    case optional_string(map, key) do
      value when is_binary(value) -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "Missing required string field #{key}."}}
    end
  end

  defp optional_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      value when is_integer(value) ->
        Integer.to_string(value)

      _value ->
        nil
    end
  end

  defp required_positive_integer(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "#{key} must be a positive integer."}}
    end
  end

  defp required_map(map, key) do
    case Map.get(map, key) do
      value when is_map(value) -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "#{key} must be an object."}}
    end
  end

  defp reject_unknown_fields(map, allowed_fields) do
    unknown_fields = map |> Map.keys() |> Enum.reject(&(&1 in allowed_fields))

    if unknown_fields == [] do
      :ok
    else
      {:error, {:invalid_arguments, "Unsupported argument field(s): #{Enum.join(unknown_fields, ", ")}."}}
    end
  end
end

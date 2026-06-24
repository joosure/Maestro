defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding do
  @moduledoc """
  Orchestrates successful typed workflow tool results into structured plan evidence refs.

  Tool/evidence mapping, payload normalization, check-status normalization, raw
  boundary input handling, and binding error codes live in focused submodules.
  This module does not expose provider tools and does not decide readiness policy.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentContract
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Payloads
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Providers
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.RawInput
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ToolMap
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields, as: WorkflowFields

  @evidence_id_prefix "evidence_"

  @type bind_result :: {:ok, [map()]} | {:error, map()}

  @spec bind_typed_tool_result(String.t() | atom() | nil, term(), String.t() | nil, term(), term(), keyword()) ::
          bind_result()
  def bind_typed_tool_result(source_kind, source_context, tool, arguments, result, opts \\ [])

  def bind_typed_tool_result(source_kind, source_context, tool, arguments, {:success, payload}, opts)
      when is_binary(tool) and is_list(opts) do
    if Keyword.keyword?(opts) do
      bind_successful_tool_result(source_kind, source_context, tool, arguments, payload, opts)
    else
      {:ok, []}
    end
  end

  def bind_typed_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: {:ok, []}

  @spec evidence_kind(String.t() | nil) :: String.t() | nil
  @spec evidence_kind(String.t() | nil, keyword()) :: String.t() | nil
  def evidence_kind(tool, opts \\ [])

  def evidence_kind(tool, opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: ToolMap.evidence_kind(tool, opts) || Providers.evidence_kind(tool, opts), else: nil
  end

  def evidence_kind(_tool, _opts), do: nil

  @spec idempotency_key(map()) :: String.t()
  def idempotency_key(ref) when is_map(ref) do
    idempotency_key(
      Map.fetch!(ref, AgentFields.evidence_kind()),
      Map.fetch!(ref, AgentFields.producer()),
      %{
        run_id: Map.fetch!(ref, WorkflowFields.run_id()),
        issue_id: Map.fetch!(ref, WorkflowFields.issue_id())
      },
      Map.fetch!(ref, AgentFields.payload()),
      []
    )
  end

  defp evidence_ref(evidence_kind, producer, scope, payload, opts) do
    %{
      AgentFields.evidence_id() => evidence_id(evidence_kind, producer, scope, payload, opts),
      AgentFields.evidence_kind() => evidence_kind,
      AgentFields.source() => AgentContract.tool_generated_trust_class(),
      AgentFields.producer() => producer,
      WorkflowFields.run_id() => Map.fetch!(scope, :run_id),
      WorkflowFields.issue_id() => Map.fetch!(scope, :issue_id),
      AgentFields.observed_at() => observed_at(opts),
      AgentFields.payload() => payload
    }
  end

  defp bind_successful_tool_result(source_kind, source_context, tool, arguments, payload, opts) do
    case evidence_kind(tool, opts) do
      nil ->
        {:ok, []}

      evidence_kind ->
        with {:ok, scope} <- evidence_scope(arguments, opts),
             {:ok, evidence_payload} <- Payloads.normalize(evidence_kind, source_kind, source_context, arguments, payload) do
          {:ok, [evidence_ref(evidence_kind, tool, scope, evidence_payload, opts)]}
        else
          :unknown -> {:ok, []}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp evidence_scope(arguments, opts) do
    runtime_metadata = opts |> Keyword.get(:tool_context) |> RawInput.runtime_metadata()

    scope = %{
      run_id:
        RawInput.first_present([
          Keyword.get(opts, :run_id),
          RawInput.value(arguments, WorkflowFields.run_id()),
          RawInput.map_value(runtime_metadata, :run_id)
        ]),
      issue_id:
        RawInput.first_present([
          RawInput.value(arguments, WorkflowFields.issue_id()),
          Keyword.get(opts, :issue_id),
          RawInput.map_value(runtime_metadata, :issue_id),
          RawInput.value(arguments, WorkflowFields.issue_identifier()),
          Keyword.get(opts, :issue_identifier),
          RawInput.map_value(runtime_metadata, :issue_identifier)
        ])
    }

    cond do
      is_nil(scope.run_id) ->
        {:error, %{code: ErrorCodes.missing_run_id(), message: "Structured plan evidence requires a run_id."}}

      is_nil(scope.issue_id) ->
        {:error, %{code: ErrorCodes.missing_issue_id(), message: "Structured plan evidence requires an issue_id."}}

      true ->
        {:ok, scope}
    end
  end

  defp evidence_id(evidence_kind, producer, scope, payload, opts) do
    @evidence_id_prefix <> String.slice(idempotency_key(evidence_kind, producer, scope, payload, opts), 0, 22)
  end

  defp idempotency_key(evidence_kind, producer, scope, payload, opts) do
    identity =
      payload
      |> Map.take(identity_fields(evidence_kind, opts))
      |> Map.put(AgentFields.evidence_kind(), evidence_kind)
      |> Map.put(AgentFields.producer(), producer)
      |> Map.put(WorkflowFields.run_id(), Map.fetch!(scope, :run_id))
      |> Map.put(WorkflowFields.issue_id(), Map.fetch!(scope, :issue_id))

    identity
    |> :erlang.term_to_binary()
    |> short_hash()
  end

  defp identity_fields(evidence_kind, opts) do
    case ToolMap.identity_fields(evidence_kind) do
      [] -> Providers.identity_fields(evidence_kind, opts)
      fields -> fields
    end
  end

  defp observed_at(opts) do
    case Keyword.get(opts, :observed_at) do
      value when is_binary(value) -> value
      _value -> DateTime.utc_now() |> DateTime.to_iso8601()
    end
  end

  defp short_hash(value) do
    :crypto.hash(:sha256, value)
    |> Base.url_encode64(padding: false)
  end
end

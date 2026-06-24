defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEventBoundaryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Identifiers
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.RawInput
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Validator
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Values

  test "facade exposes provider-session event contract" do
    assert ProviderSessionEvent.schema_id() == Contract.schema_id()
    assert ProviderSessionEvent.extension_key() == Contract.extension_key()
  end

  test "identifiers own derived provider-session id prefixes" do
    assert String.starts_with?(Identifiers.fallback_event_id(%{}), Identifiers.fallback_event_id_prefix())
    assert Identifiers.generated_task_id(0) == Identifiers.generated_task_id_prefix() <> "1"
  end

  test "normalizer owns raw provider aliases and emits canonical event fields" do
    provider_task_id_key = Contract.provider_task_id_key()
    title_key = Contract.title_key()
    requested_status_key = Contract.requested_status_key()

    assert {:ok, event} =
             ProviderSessionEvent.normalize(
               %{
                 provider: :codex,
                 id: "provider-event-1",
                 observed_at: "2026-05-20T00:00:01Z",
                 todos: [
                   %{
                     uuid: "task-1",
                     content: "Push code",
                     state: "completed",
                     item_id: "repo.push"
                   }
                 ]
               },
               run_id: "run-1"
             )

    assert event[Contract.schema_key()] == Contract.schema_id()
    assert event[Contract.authority_key()] == Values.authority()
    assert event[Contract.trust_class_key()] == Values.default_trust_class()
    assert event[Contract.provider_kind_key()] == "codex"
    assert event[Contract.surface_key()] == Values.provider_session_tasks_surface()
    assert event[Contract.run_id_key()] == "run-1"

    assert [
             %{
               ^provider_task_id_key => "task-1",
               ^title_key => "Push code",
               ^requested_status_key => complete_status
             }
           ] = event[Contract.tasks_key()]

    assert complete_status == Values.complete_status()
    refute get_in(event, [Contract.tasks_key(), Access.at(0), "item_id"])
    assert Values.complete_does_not_satisfy_evidence_warning() in event[Contract.warnings_key()]
  end

  test "validator only accepts canonical event contract" do
    assert {:error, %{code: code, errors: errors}} =
             Validator.validate(%{
               Contract.schema_key() => Contract.schema_id(),
               Contract.authority_key() => Values.authority(),
               Contract.trust_class_key() => Values.default_trust_class(),
               Contract.provider_kind_key() => "codex",
               Contract.surface_key() => "tasks",
               Contract.event_id_key() => "provider-event-1",
               Contract.observed_at_key() => "2026-05-20T00:00:01Z"
             })

    assert code == ErrorCodes.invalid_event()
    assert Enum.any?(errors, &(&1.code == ErrorCodes.invalid_enum() and &1.path == [Contract.surface_key()]))
  end

  test "raw input owns atom and string boundary reads" do
    assert RawInput.task_values(%{todos: ["one"]}) == ["one"]
    assert RawInput.task_values(%{"todos" => ["one"]}) == ["one"]
  end
end

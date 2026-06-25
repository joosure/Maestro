defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery do
  @moduledoc """
  Built-in workflow runtime extension for coding PR delivery.

  The module adapts the extension-owned reconciliation service to the
  runtime-extension boundary. This keeps the orchestrator dependent on the
  stable workflow extension contract instead of coding PR delivery rules.
  """

  @behaviour SymphonyElixir.Workflow.Extension
  @behaviour SymphonyElixir.Workflow.Extension.ContributionCallbacks

  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ConfigValidator
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Manifest

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.{
    ChangeProposalReconcile,
    ProductionProfileEvidenceRequest,
    ProductionProfilePlan,
    ProductionProfilePreflightCollect,
    ProductionProfileStatus,
    ProductionProfileTemplate,
    ProductionProfileValidate
  }

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding, as: StructuredPlanEvidenceBinding
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Supervision
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.TemplateCatalog
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ToolResultRecorder

  @impl true
  def id, do: Manifest.id()

  @spec version() :: String.t()
  def version, do: Manifest.version()

  @impl true
  def validate_settings(settings, profile_context) when is_map(settings) do
    ConfigValidator.validate_settings(settings, profile_context)
  end

  @impl true
  def operator_commands,
    do: [
      ChangeProposalReconcile,
      ProductionProfilePlan,
      ProductionProfileEvidenceRequest,
      ProductionProfileValidate,
      ProductionProfileTemplate,
      ProductionProfilePreflightCollect,
      ProductionProfileStatus
    ]

  @impl true
  def tool_result_recorders, do: [ToolResultRecorder]

  @impl true
  def profiles, do: [Profile]

  @impl true
  def template_entries, do: TemplateCatalog.entries()

  @impl true
  def completion_validators, do: [CompletionValidator]

  @impl true
  def readiness_evidence_providers, do: Readiness.evidence_providers()

  @impl true
  def structured_execution_plan_evidence_binding_providers, do: [StructuredPlanEvidenceBinding]

  @impl true
  def readiness_policies, do: Readiness.policies()

  @impl true
  def readiness_evidence_recorders, do: Readiness.evidence_recorders()

  @impl true
  def typed_tool_failure_retry_policies, do: Readiness.retry_policies()

  @impl true
  def typed_tool_failure_resource_identity(runtime_metadata, arguments),
    do: Readiness.resource_identity(runtime_metadata, arguments)

  @impl true
  def children(opts), do: Supervision.children(opts)

  @impl true
  def run_poll_cycle(%RuntimeContext{} = context, opts), do: Runtime.run_poll_cycle(context, opts)
end

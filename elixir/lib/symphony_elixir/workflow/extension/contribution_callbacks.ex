defmodule SymphonyElixir.Workflow.Extension.ContributionCallbacks do
  @moduledoc """
  Optional contribution callbacks for workflow extensions.

  `SymphonyElixir.Workflow.Extension` is the minimal runtime contract. This
  behaviour keeps static contribution lists separate from the runtime callback
  so the extension boundary can grow through manifest/contribution projection
  instead of turning the runtime behaviour into a single large plugin interface.
  """

  @callback operator_commands() :: [module()]
  @callback tool_result_recorders() :: [module()]
  @callback readiness_policies() :: [module()]
  @callback readiness_evidence_recorders() :: [module()]
  @callback readiness_evidence_providers() :: [module()]
  @callback structured_execution_plan_evidence_binding_providers() :: [module()]
  @callback completion_validators() :: [module()]
  @callback profiles() :: [module()]
  @callback template_entries() :: [term()]
  @callback children(keyword()) :: [Supervisor.child_spec()]
  @callback typed_tool_failure_retry_policies() :: map()
  @callback typed_tool_failure_resource_identity(map(), term()) :: {String.t(), term()} | nil

  @optional_callbacks operator_commands: 0,
                      tool_result_recorders: 0,
                      readiness_policies: 0,
                      readiness_evidence_recorders: 0,
                      readiness_evidence_providers: 0,
                      structured_execution_plan_evidence_binding_providers: 0,
                      completion_validators: 0,
                      profiles: 0,
                      template_entries: 0,
                      children: 1,
                      typed_tool_failure_retry_policies: 0,
                      typed_tool_failure_resource_identity: 2
end

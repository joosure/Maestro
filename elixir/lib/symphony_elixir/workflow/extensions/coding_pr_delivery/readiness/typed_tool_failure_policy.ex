defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.TypedToolFailurePolicy do
  @moduledoc """
  Coding PR Delivery retry-policy contribution for typed Dynamic Tool failures.
  """

  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.RetryPolicy
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ExternalReferenceContract, as: ExternalReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ResourceIdentityContract, as: ResourceIdentity
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Contract
  alias SymphonyElixir.Workflow.StateTransitionReadiness

  @review_handoff_blocked_code "review_handoff_blocked_after_retries"
  @review_handoff_blocked_message "Review handoff remains blocked after repeated structured readiness failures."

  @spec retry_policies() :: map()
  def retry_policies do
    %{
      StateTransitionReadiness.typed_tool_not_ready_error_code() =>
        RetryPolicy.new!(
          @review_handoff_blocked_code,
          @review_handoff_blocked_message
        ),
      Contract.not_ready_error() =>
        RetryPolicy.new!(
          @review_handoff_blocked_code,
          @review_handoff_blocked_message
        )
    }
  end

  @spec resource_identity(map(), term()) :: {String.t(), term()} | nil
  def resource_identity(_runtime_metadata, arguments) do
    cond do
      change_proposal_reference?(arguments) ->
        change_proposal_external_identity(arguments)

      value = argument_value(arguments, ResourceIdentity.pr_url_key()) || argument_value(arguments, ResourceIdentity.pr_url_atom_key()) ->
        {ResourceIdentity.change_proposal_resource_kind(), value}

      value =
          argument_value(arguments, ResourceIdentity.pull_request_url_key()) ||
            argument_value(arguments, ResourceIdentity.pull_request_url_atom_key()) ->
        {ResourceIdentity.change_proposal_resource_kind(), value}

      true ->
        nil
    end
  end

  defp change_proposal_reference?(arguments) do
    argument_value(arguments, ExternalReference.reference_kind_key()) == ExternalReference.change_proposal_kind() or
      argument_value(arguments, ResourceIdentity.reference_kind_atom_key()) == ExternalReference.change_proposal_kind()
  end

  defp change_proposal_external_identity(arguments) do
    case argument_value(arguments, ExternalReference.external_id_key()) ||
           argument_value(arguments, ResourceIdentity.external_id_atom_key()) ||
           argument_value(arguments, ResourceIdentity.url_key()) ||
           argument_value(arguments, ResourceIdentity.url_atom_key()) do
      nil -> nil
      value -> {ResourceIdentity.change_proposal_resource_kind(), value}
    end
  end

  defp argument_value(arguments, key) when is_map(arguments), do: Map.get(arguments, key)
  defp argument_value(_arguments, _key), do: nil
end

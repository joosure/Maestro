defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.RepoProvider do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.CheckStatus
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Normalization
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  @change_proposal_key Evidence.change_proposal_key()
  @checks_key Evidence.checks_key()
  @feedback_key Evidence.feedback_key()
  @status_key Evidence.status_key()
  @source_key Evidence.source_key()
  @id_key Evidence.id_key()
  @url_key Evidence.url_key()
  @head_ref_key Evidence.head_ref_key()
  @head_sha_key Evidence.head_sha_key()
  @observed_at_key Evidence.observed_at_key()
  @provider_kind_key Evidence.provider_kind_key()
  @repository_key Evidence.repository_key()
  @number_key Evidence.number_key()
  @summary_key Evidence.summary_key()
  @actionable_count_key Evidence.actionable_count_key()
  @missing_status Values.missing_status()
  @clear_status Values.clear_status()
  @action_required_status Values.action_required_status()
  @not_required_status Values.not_required_status()
  @unavailable_status Values.unavailable_status()
  @created_status Values.created_status()
  @updated_status Values.updated_status()
  @repo_provider_observed_source Values.repo_provider_observed_source()

  @payload_data_key "data"
  @payload_change_proposal_key "changeProposal"
  @payload_action_key "action"
  @payload_exists_key "exists"
  @payload_created_action "created"
  @payload_updated_action "updated"
  @payload_provider_key "provider"
  @payload_repository_key "repository"
  @payload_id_key "id"
  @payload_number_key "number"
  @payload_url_key "url"
  @payload_head_ref_camel_key "headRefName"
  @payload_head_ref_key "head_ref"
  @payload_branch_key "branch"
  @payload_head_sha_camel_key "headRefOid"
  @payload_head_sha_key "headSha"
  @payload_head_sha_snake_key "head_sha"
  @payload_summary_key "summary"
  @payload_actionable_feedback_count_key "actionableFeedbackCount"
  @payload_actionable_items_key "actionableItems"
  @payload_checks_key "checks"
  @payload_discussion_key "discussion"

  @spec change_proposal_observation(term()) :: map()
  def change_proposal_observation(payload) do
    data = Map.get(payload, @payload_data_key, %{})
    proposal = Map.get(data, @payload_change_proposal_key, %{}) || %{}
    action = Normalization.string_value(data, @payload_action_key)

    cond do
      Map.get(data, @payload_exists_key) == false ->
        %{
          @change_proposal_key =>
            Normalization.compact(%{
              @status_key => @missing_status,
              @source_key => @repo_provider_observed_source,
              @observed_at_key => Normalization.generated_at()
            })
        }

      not is_map(proposal) or map_size(proposal) == 0 ->
        %{}

      true ->
        status =
          case action do
            @payload_created_action -> @created_status
            @payload_updated_action -> @updated_status
            _action -> @updated_status
          end

        %{
          @change_proposal_key =>
            Normalization.compact(%{
              @status_key => status,
              @source_key => @repo_provider_observed_source,
              @provider_kind_key => Normalization.string_value(proposal, @payload_provider_key),
              @repository_key => Normalization.string_value(proposal, @payload_repository_key),
              @id_key => Normalization.string_value(proposal, @payload_id_key),
              @number_key => Normalization.string_value(proposal, @payload_number_key),
              @url_key => Normalization.string_value(proposal, @payload_url_key),
              @head_ref_key =>
                Normalization.string_value(proposal, @payload_head_ref_camel_key) ||
                  Normalization.string_value(proposal, @payload_head_ref_key) ||
                  Normalization.string_value(proposal, @payload_branch_key),
              @head_sha_key =>
                Normalization.string_value(proposal, @payload_head_sha_camel_key) ||
                  Normalization.string_value(proposal, @payload_head_sha_key) ||
                  Normalization.string_value(proposal, @payload_head_sha_snake_key),
              @observed_at_key => Normalization.generated_at()
            })
        }
    end
  end

  @spec checks_observation(term(), keyword()) :: map()
  def checks_observation(checks, opts) when is_map(checks) do
    status = CheckStatus.status(checks, opts)

    head_sha =
      if status in [@not_required_status, @unavailable_status] do
        nil
      else
        Normalization.string_value(checks, @payload_head_sha_key) ||
          Normalization.string_value(checks, @payload_head_sha_snake_key)
      end

    %{
      @checks_key =>
        Normalization.compact(%{
          @status_key => status,
          @source_key => @repo_provider_observed_source,
          @summary_key => Map.get(checks, @payload_summary_key),
          @head_sha_key => head_sha,
          @observed_at_key => Normalization.generated_at()
        })
    }
  end

  def checks_observation(_checks, _opts), do: %{}

  @spec feedback_observation(term()) :: map()
  def feedback_observation(discussion) when is_map(discussion) do
    summary = Map.get(discussion, @payload_summary_key, %{}) || %{}

    actionable_count =
      Normalization.integer_value(summary, @payload_actionable_feedback_count_key) ||
        length(List.wrap(Map.get(discussion, @payload_actionable_items_key)))

    %{
      @feedback_key =>
        Normalization.compact(%{
          @status_key => if(actionable_count > 0, do: @action_required_status, else: @clear_status),
          @source_key => @repo_provider_observed_source,
          @actionable_count_key => actionable_count,
          @observed_at_key => Normalization.generated_at()
        })
    }
  end

  def feedback_observation(_discussion), do: %{}

  @spec snapshot_observation(term(), keyword()) :: map()
  def snapshot_observation(payload, opts) do
    data = Normalization.payload_data(payload)

    %{}
    |> Normalization.deep_merge(change_proposal_observation(%{@payload_data_key => data}))
    |> Normalization.deep_merge(checks_observation(Map.get(data, @payload_checks_key), opts))
    |> Normalization.deep_merge(feedback_observation(Map.get(data, @payload_discussion_key)))
  end
end

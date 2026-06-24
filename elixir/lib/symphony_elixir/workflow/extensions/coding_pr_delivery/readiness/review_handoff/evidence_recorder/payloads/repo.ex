defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Repo do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Normalization
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  @repo_key Evidence.repo_key()
  @validation_key Evidence.validation_key()
  @status_key Evidence.status_key()
  @source_key Evidence.source_key()
  @id_key Evidence.id_key()
  @head_ref_key Evidence.head_ref_key()
  @head_sha_key Evidence.head_sha_key()
  @published_head_sha_key Evidence.published_head_sha_key()
  @commits_key Evidence.commits_key()
  @change_kind_key Evidence.change_kind_key()
  @observed_at_key Evidence.observed_at_key()
  @commands_key Evidence.commands_key()
  @working_tree_clean_key Evidence.working_tree_clean_key()
  @pushed_key Evidence.pushed_key()
  @command_key Evidence.command_key()
  @cwd_key Evidence.cwd_key()
  @exit_code_key Evidence.exit_code_key()
  @passed_status Values.passed_status()
  @unknown_status Values.unknown_status()
  @code_change_kind Evidence.code_change_kind()
  @typed_tool_observed_source Values.typed_tool_observed_source()
  @repo_observed_source Values.repo_observed_source()
  @repo_diff_check_id "repo_diff_check"
  @repo_diff_check_command ["git", "diff", "--check"]
  @command_separator " "
  @payload_data_key "data"
  @payload_status_key "status"
  @payload_head_sha_key "headSha"
  @payload_published_head_sha_key "publishedHeadSha"
  @payload_action_key "action"
  @payload_committed_action "committed"
  @payload_branch_key "branch"
  @payload_commit_sha_key "sha"
  @payload_clean_key "clean"
  @payload_diff_check_key "diffCheck"
  @payload_args_key "args"
  @payload_root_key "root"
  @payload_path_key "path"

  @spec commit_observation(term()) :: map()
  def commit_observation(payload) do
    data = Map.get(payload, @payload_data_key, %{})
    status = Map.get(data, @payload_status_key, %{})
    head_sha = Normalization.string_value(data, @payload_head_sha_key) || Normalization.string_value(status, @payload_head_sha_key)
    action = Normalization.string_value(data, @payload_action_key)

    repo =
      %{
        @source_key => @repo_observed_source,
        @change_kind_key => if(action == @payload_committed_action and Normalization.present?(head_sha), do: @code_change_kind, else: @unknown_status),
        @head_ref_key => Normalization.string_value(status, @payload_branch_key),
        @head_sha_key => head_sha,
        @commits_key => if(Normalization.present?(head_sha), do: [%{@payload_commit_sha_key => head_sha}], else: []),
        @working_tree_clean_key => Map.get(status, @payload_clean_key),
        @observed_at_key => Normalization.generated_at()
      }
      |> Normalization.compact()

    %{@repo_key => repo}
  end

  @spec push_observation(term()) :: map()
  def push_observation(payload) do
    data = Map.get(payload, @payload_data_key, %{})
    head_sha = Normalization.string_value(data, @payload_head_sha_key) || Normalization.string_value(data, @payload_published_head_sha_key)

    %{
      @repo_key =>
        Normalization.compact(%{
          @source_key => @repo_observed_source,
          @change_kind_key => if(Normalization.present?(head_sha), do: @code_change_kind, else: @unknown_status),
          @head_ref_key => Normalization.string_value(data, @payload_branch_key),
          @head_sha_key => head_sha,
          @published_head_sha_key => Normalization.string_value(data, @payload_published_head_sha_key),
          @pushed_key => Normalization.present?(Normalization.string_value(data, @payload_published_head_sha_key)),
          @observed_at_key => Normalization.generated_at()
        })
    }
  end

  @spec diff_validation_observation(term(), term()) :: map()
  def diff_validation_observation(arguments, payload) do
    data = Map.get(payload, @payload_data_key, %{})

    if Map.has_key?(data, @payload_diff_check_key) and not is_nil(Map.get(data, @payload_diff_check_key)) do
      status = Map.get(data, @payload_status_key, %{})
      args = arguments |> Normalization.value(@payload_args_key) |> Normalization.string_list()

      %{
        @validation_key =>
          Normalization.compact(%{
            @status_key => @passed_status,
            @source_key => @typed_tool_observed_source,
            @commands_key => [
              Normalization.compact(%{
                @id_key => @repo_diff_check_id,
                @command_key => Enum.join(@repo_diff_check_command ++ args, @command_separator),
                @cwd_key => Normalization.string_value(status, @payload_root_key) || Normalization.string_value(status, @payload_path_key),
                @exit_code_key => 0,
                @head_sha_key => Normalization.string_value(status, @payload_head_sha_key),
                @source_key => @typed_tool_observed_source
              })
            ],
            @head_sha_key => Normalization.string_value(status, @payload_head_sha_key),
            @observed_at_key => Normalization.generated_at()
          })
      }
    else
      %{}
    end
  end
end

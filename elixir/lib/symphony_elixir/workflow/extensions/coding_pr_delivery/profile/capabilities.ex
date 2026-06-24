defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Capabilities do
  @moduledoc false

  alias SymphonyElixir.Agent.Capabilities, as: AgentCapabilities
  alias SymphonyElixir.Repo.Capabilities, as: RepoCapabilities
  alias SymphonyElixir.RepoProvider.Capabilities, as: RepoProviderCapabilities
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Options

  @required_capabilities [
    TrackerCapabilities.issue_read(),
    TrackerCapabilities.comment_read(),
    TrackerCapabilities.comment_write(),
    TrackerCapabilities.state_update(),
    RepoCapabilities.checkout(),
    RepoCapabilities.diff(),
    RepoCapabilities.commit(),
    RepoCapabilities.push(),
    AgentCapabilities.turn_run()
  ]

  @change_proposal_capabilities [
    RepoProviderCapabilities.change_proposal_create(),
    RepoProviderCapabilities.change_proposal_read(),
    RepoProviderCapabilities.review_read(),
    RepoProviderCapabilities.check_read()
  ]

  @typed_tracker_capabilities [
    TrackerCapabilities.issue_snapshot(),
    TrackerCapabilities.move_issue(),
    TrackerCapabilities.upsert_workpad()
  ]

  @typed_change_proposal_capabilities [
    TrackerCapabilities.attach_external_reference()
  ]

  @typed_repo_capabilities [
    RepoProviderCapabilities.change_proposal_snapshot(),
    RepoProviderCapabilities.create_or_update_change_proposal(),
    RepoProviderCapabilities.read_change_proposal_discussion(),
    RepoProviderCapabilities.add_change_proposal_comment(),
    RepoProviderCapabilities.reply_change_proposal_review_comment(),
    RepoProviderCapabilities.read_change_proposal_checks()
  ]

  @typed_repo_land_capabilities [
    RepoProviderCapabilities.merge_change_proposal()
  ]

  @profile_owned_execution_profile_capabilities [
    RepoProviderCapabilities.merge()
  ]

  @optional_capabilities (@change_proposal_capabilities ++
                            @typed_repo_capabilities ++
                            @typed_repo_land_capabilities ++
                            [
                              @profile_owned_execution_profile_capabilities,
                              RepoProviderCapabilities.review_write(),
                              TrackerCapabilities.relation_read(),
                              TrackerCapabilities.relation_write(),
                              TrackerCapabilities.upsert_comment(),
                              TrackerCapabilities.create_follow_up_issue(),
                              TrackerCapabilities.read_issue_relations(),
                              TrackerCapabilities.add_issue_relation(),
                              TrackerCapabilities.read_issue_dependencies(),
                              TrackerCapabilities.save_issue_dependency(),
                              RepoProviderCapabilities.submit_change_proposal_review()
                            ])
                         |> List.flatten()

  @spec required_capabilities(term()) :: [String.t()]
  def required_capabilities(options) do
    require_change_proposal? = Options.change_proposal_required?(options)
    require_typed_tracker_tools? = Options.typed_tracker_tools_required?(options)
    require_typed_repo_tools? = Options.typed_repo_tools_required?(options)

    @required_capabilities
    |> maybe_add_capabilities(@change_proposal_capabilities, require_change_proposal?)
    |> maybe_add_capabilities(@typed_tracker_capabilities, require_typed_tracker_tools?)
    |> maybe_add_capabilities(
      @typed_repo_capabilities,
      require_typed_repo_tools? and require_change_proposal?
    )
    |> maybe_add_capabilities(
      @typed_change_proposal_capabilities,
      require_typed_tracker_tools? and require_change_proposal?
    )
  end

  @spec optional_capabilities(term()) :: [String.t()]
  def optional_capabilities(_options), do: @optional_capabilities

  @spec execution_profile_required_capabilities(term(), term()) :: [String.t()]
  def execution_profile_required_capabilities(execution_profile, options) when is_binary(execution_profile) do
    if execution_profile == Contract.land_execution_profile() and
         execution_profile in Options.allowed_execution_profile_names(options) do
      @profile_owned_execution_profile_capabilities
      |> maybe_add_capabilities(
        @typed_repo_land_capabilities,
        Options.typed_repo_tools_required?(options)
      )
    else
      []
    end
  end

  def execution_profile_required_capabilities(_execution_profile, _options), do: []

  defp maybe_add_capabilities(capabilities, additional_capabilities, true),
    do: capabilities ++ additional_capabilities

  defp maybe_add_capabilities(capabilities, _additional_capabilities, false), do: capabilities
end

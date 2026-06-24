defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.CheckStatus do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CheckRun
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile, as: CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Normalization
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  @passed_status Values.passed_status()
  @failed_status Values.failed_status()
  @unknown_status Values.unknown_status()
  @unavailable_status Values.unavailable_status()
  @not_required_status Values.not_required_status()
  @pending_status Values.pending_status()

  @runs_key "runs"
  @summary_key "summary"
  @bucket_key "bucket"
  @state_key "state"
  @adoption_settings_key "adoption_settings"
  @workflow_key "workflow"
  @profile_key "profile"
  @kind_key "kind"
  @options_key "options"

  @passed_provider_bucket_aliases ~w(successful green)
  @failed_provider_bucket_aliases ~w(failure error cancelled canceled timed_out timedout red)
  @pending_provider_bucket_aliases ~w(queued running in_progress waiting yellow)
  @passed_check_buckets [@passed_status] ++ CheckRun.successful_conclusions() ++ @passed_provider_bucket_aliases
  @failed_check_buckets [@failed_status] ++ @failed_provider_bucket_aliases
  @pending_check_buckets [@pending_status] ++ @pending_provider_bucket_aliases

  @spec status(map(), keyword()) :: String.t()
  def status(%{@runs_key => runs}, opts) when is_list(runs) do
    run_buckets = Enum.map(runs, &check_bucket/1)

    cond do
      runs == [] -> empty_checks_status(opts)
      Enum.any?(run_buckets, &(&1 in @failed_check_buckets)) -> @failed_status
      Enum.any?(run_buckets, &(&1 in @pending_check_buckets)) -> @pending_status
      Enum.all?(run_buckets, &(&1 in @passed_check_buckets)) -> @passed_status
      true -> @unknown_status
    end
  end

  def status(%{@summary_key => summary}, opts) when is_map(summary), do: summary_status(summary, opts)
  def status(_checks, _opts), do: @unknown_status

  defp summary_status(summary, opts) when is_map(summary) do
    cond do
      summary == %{} -> empty_checks_status(opts)
      Enum.any?(@failed_check_buckets, fn bucket -> (Normalization.integer_value(summary, bucket) || 0) > 0 end) -> @failed_status
      Enum.any?(@pending_check_buckets, fn bucket -> (Normalization.integer_value(summary, bucket) || 0) > 0 end) -> @pending_status
      Enum.any?(@passed_check_buckets, fn bucket -> (Normalization.integer_value(summary, bucket) || 0) > 0 end) -> @passed_status
      true -> @unknown_status
    end
  end

  defp empty_checks_status(opts) do
    if change_proposal_checks_not_required?(opts), do: @not_required_status, else: @unavailable_status
  end

  defp check_bucket(check) when is_map(check) do
    explicit_bucket = Normalization.string_value(check, @bucket_key) || Normalization.string_value(check, @state_key)
    status = CheckRun.normalized_status(check)
    conclusion = CheckRun.normalized_conclusion(check)

    cond do
      Normalization.present?(explicit_bucket) ->
        String.downcase(explicit_bucket)

      CheckRun.successful_completed?(check) ->
        @passed_status

      CheckRun.completed?(check) and conclusion in @failed_check_buckets ->
        conclusion

      Normalization.present?(status) and status in @pending_check_buckets ->
        status

      Normalization.present?(conclusion) ->
        conclusion

      true ->
        @unknown_status
    end
  end

  defp check_bucket(_check), do: @unknown_status

  defp change_proposal_checks_not_required?(opts) when is_list(opts) do
    opts
    |> workflow_settings()
    |> coding_pr_delivery_profile_options()
    |> CodingPrDelivery.review_handoff_change_proposal_checks_not_required?()
  end

  defp workflow_settings(opts) when is_list(opts) do
    cond do
      is_map(Keyword.get(opts, :workflow_settings)) ->
        Keyword.fetch!(opts, :workflow_settings)

      is_map(tool_context_adoption_settings(Keyword.get(opts, :tool_context))) ->
        tool_context_adoption_settings(Keyword.get(opts, :tool_context))

      true ->
        %{}
    end
  end

  defp tool_context_adoption_settings(%{adoption_settings: settings}) when is_map(settings), do: settings
  defp tool_context_adoption_settings(%{@adoption_settings_key => settings}) when is_map(settings), do: settings
  defp tool_context_adoption_settings(_context), do: nil

  defp coding_pr_delivery_profile_options(settings) when is_map(settings) do
    profile =
      settings
      |> Normalization.value(@workflow_key)
      |> Normalization.value(@profile_key)

    if Normalization.string_value(profile || %{}, @kind_key) == CodingPrDelivery.kind() do
      case Normalization.value(profile, @options_key) do
        options when is_map(options) -> options
        _options -> %{}
      end
    else
      %{}
    end
  end

  defp coding_pr_delivery_profile_options(_settings), do: %{}
end

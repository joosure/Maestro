defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Builder do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProviderFactsDefaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Facts
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Payload
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Summary

  @spec missing(map(), map()) :: Facts.t()
  def missing(repo_config, target) when is_map(repo_config) and is_map(target) do
    repo_config
    |> base_attrs(target)
    |> Facts.new!()
  end

  @spec error(map(), atom(), map(), term()) :: Facts.t()
  def error(repo_config, operation, target, reason)
      when is_map(repo_config) and is_atom(operation) and is_map(target) do
    error = ProviderFactsDefaults.normalize_error(repo_config, operation, reason)

    repo_config
    |> base_attrs(target)
    |> Map.merge(%{
      error: error,
      retryable?: ProviderFactsDefaults.retryable_error?(error),
      provider_state: :unknown
    })
    |> Facts.new!()
  end

  @spec from_provider_payload(map(), map(), map(), [map()], [map()], [map()], [map()], map() | list()) :: Facts.t()
  def from_provider_payload(repo_config, target, pr_payload, issue_comments, review_comments, reviews, check_runs, env)
      when is_map(repo_config) and is_map(target) and is_map(pr_payload) and is_list(issue_comments) and
             is_list(review_comments) and is_list(reviews) and is_list(check_runs) do
    repo_config
    |> base_attrs(target)
    |> Map.merge(%{
      number: Payload.field_value(pr_payload, Contract.payload_key(:number)),
      url: Payload.field_value(pr_payload, Contract.payload_key(:url)),
      branch: Payload.field_value(pr_payload, Contract.payload_key(:head_ref_name)) || Payload.target_value(target, :branch),
      head_sha: Payload.field_value(pr_payload, Contract.payload_key(:head_ref_oid)),
      provider_state: Summary.provider_state(pr_payload),
      review_summary: Summary.review_summary(reviews),
      check_summary: Summary.check_summary(check_runs),
      mergeability_summary: Summary.mergeability_summary(pr_payload),
      unresolved_actionable_feedback?: Summary.unresolved_actionable_feedback?(issue_comments, review_comments, env)
    })
    |> Facts.new!()
  end

  defp base_attrs(repo_config, target) do
    %{
      provider_kind: ProviderFactsDefaults.provider_kind(repo_config),
      repository: ProviderFactsDefaults.repository(repo_config),
      number: Payload.target_value(target, :number),
      url: Payload.target_value(target, :url),
      branch: Payload.target_value(target, :branch),
      observed_at: DateTime.utc_now()
    }
  end
end

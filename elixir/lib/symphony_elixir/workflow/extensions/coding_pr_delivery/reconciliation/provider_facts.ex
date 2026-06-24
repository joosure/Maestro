defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts do
  @moduledoc """
  Builds Coding PR Delivery provider facts through injected provider callbacks.

  This module belongs to the Coding PR Delivery extension because it maps
  provider-neutral repo facts into the extension-owned reconciliation fact
  model. Bundled deployments adapt RepoProvider through
  `HostAdapters.Reconciliation.ProviderFactsDefaults`; RepoProvider remains a
  provider facade and must not depend on this workflow-extension domain model.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProviderFactsDefaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference, as: KnownTargetReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Facts
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Builder
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Client
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Options
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Payload

  @spec facts(map(), KnownTargetReference.t() | map() | nil, keyword()) :: Facts.t()
  def facts(repo_config, target, opts \\ [])

  def facts(repo_config, target, opts) when is_map(repo_config) do
    case Options.normalize(opts) do
      {:ok, options} -> facts_for_target(repo_config, target, options)
      {:error, reason} -> Builder.error(repo_config, :provider_facts, target_for_error(target), reason)
    end
  end

  defp facts_for_target(repo_config, nil, %Options{}) when is_map(repo_config) do
    Builder.missing(repo_config, %{})
  end

  defp facts_for_target(repo_config, target, %Options{} = options) when is_map(repo_config) and is_map(target) do
    provider_opts = Payload.provider_target_opts(target)

    case Client.map(:pr_view, repo_config, provider_opts, options) do
      {:ok, pr_payload} ->
        inspect_context(repo_config, target, pr_payload, options)

      {:error, reason} ->
        if ProviderFactsDefaults.change_proposal_not_found?(reason) do
          Builder.missing(repo_config, target)
        else
          Builder.error(repo_config, :pr_view, target, reason)
        end
    end
  end

  defp facts_for_target(repo_config, target, %Options{}) when is_map(repo_config) do
    Builder.error(
      repo_config,
      :provider_facts,
      %{},
      {:invalid_provider_facts_target, %{target_type: Diagnostics.detailed_type_atom(target)}}
    )
  end

  defp inspect_context(repo_config, target, pr_payload, %Options{} = options) do
    provider_opts = Payload.provider_target_opts(pr_payload, target)

    with {:ok, issue_comments} <- Client.list(:pr_issue_comments, repo_config, provider_opts, options),
         {:ok, review_comments} <- Client.list(:pr_review_comments, repo_config, provider_opts, options),
         {:ok, reviews} <- Client.list(:pr_reviews, repo_config, provider_opts, options),
         {:ok, checks} <- Client.list(:pr_checks, repo_config, provider_opts, options) do
      provider_payload_facts(
        repo_config,
        target,
        pr_payload,
        issue_comments,
        review_comments,
        reviews,
        checks,
        options
      )
    else
      {:error, reason} ->
        Builder.error(repo_config, :provider_facts, target, reason)
    end
  end

  defp provider_payload_facts(
         repo_config,
         target,
         pr_payload,
         issue_comments,
         review_comments,
         reviews,
         check_runs,
         %Options{} = options
       )
       when is_map(repo_config) and is_map(target) and is_map(pr_payload) and is_list(issue_comments) and
              is_list(review_comments) and is_list(reviews) and is_list(check_runs) do
    Builder.from_provider_payload(repo_config, target, pr_payload, issue_comments, review_comments, reviews, check_runs, options.env)
  end

  defp target_for_error(target) when is_map(target), do: target
  defp target_for_error(_target), do: %{}
end

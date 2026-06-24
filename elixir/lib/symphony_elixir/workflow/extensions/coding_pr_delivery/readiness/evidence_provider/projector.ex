defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.Projector do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.LandReady
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Facts

  @spec evidence(Facts.t(), Issue.t()) :: map()
  def evidence(%Facts{} = facts, %Issue{} = issue) do
    %{
      Contract.change_proposal_key() => change_proposal(facts),
      Contract.repo_key() => repo(facts),
      Contract.checks_key() => checks(facts),
      Contract.review_key() => review(facts),
      Contract.tracker_key() => tracker(facts, issue)
    }
  end

  defp change_proposal(%Facts{} = facts) do
    %{
      Contract.url_key() => facts.url,
      Contract.number_key() => facts.number,
      Contract.target_key() => facts.number || facts.url || facts.branch,
      Contract.branch_key() => facts.branch,
      Contract.provider_state_key() => atom_name(facts.provider_state),
      Contract.linked_issue_key() => true,
      Contract.tracker_linked_key() => true
    }
  end

  defp repo(%Facts{} = facts) do
    %{
      Contract.repository_key() => facts.repository,
      Contract.branch_key() => facts.branch,
      Contract.head_sha_key() => facts.head_sha,
      Contract.diff_present_key() => present?(facts.head_sha)
    }
  end

  defp checks(%Facts{} = facts) do
    %{
      Contract.read_key() => facts.check_summary != Contract.summary_unknown(),
      Contract.status_key() => atom_name(facts.check_summary),
      Contract.check_summary_key() => atom_name(facts.check_summary),
      Contract.passing_key() => facts.check_summary == Contract.check_summary_passing()
    }
  end

  defp review(%Facts{} = facts) do
    %{
      Contract.approved_key() => facts.review_summary == Contract.review_summary_approved(),
      Contract.status_key() => atom_name(facts.review_summary),
      Contract.review_summary_key() => atom_name(facts.review_summary)
    }
  end

  defp tracker(%Facts{} = facts, %Issue{} = issue) do
    %{
      Contract.state_key() => issue.state,
      Contract.change_proposal_attached_key() => true,
      Contract.merge_approved_key() => LandReady.ready?(facts)
    }
  end

  defp atom_name(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_name(value) when is_binary(value), do: value
  defp atom_name(_value), do: nil

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end

defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Plan.Evidence do
  @moduledoc """
  Stable selectors and comparison helpers for structured-plan evidence refs.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceKinds
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Projection, as: StructuredPlanProjection

  @repo_key Evidence.repo_key()
  @change_proposal_key Evidence.change_proposal_key()
  @head_sha_key Evidence.head_sha_key()
  @published_head_sha_key Evidence.published_head_sha_key()
  @repo_change_kinds EvidenceKinds.repo_change_kinds()

  @spec latest_repo_head(map()) :: String.t() | nil
  def latest_repo_head(plan) do
    plan
    |> all_evidence_refs()
    |> Enum.filter(&(StructuredPlanProjection.evidence_kind(&1) in @repo_change_kinds))
    |> latest_ref()
    |> payload_head()
  end

  @spec latest_repo_change_at(map()) :: DateTime.t() | nil
  def latest_repo_change_at(plan) do
    plan
    |> all_evidence_refs()
    |> Enum.filter(&(StructuredPlanProjection.evidence_kind(&1) in @repo_change_kinds))
    |> latest_observed_at()
  end

  @spec current_head(map()) :: String.t() | nil
  def current_head(observations) when is_map(observations) do
    repo = Map.get(observations, @repo_key, %{})
    change_proposal = Map.get(observations, @change_proposal_key, %{})

    Map.get(repo, @published_head_sha_key) ||
      Map.get(repo, @head_sha_key) ||
      Map.get(change_proposal, @head_sha_key)
  end

  def current_head(_observations), do: nil

  @spec payload_head(map() | nil) :: String.t() | nil
  def payload_head(ref) do
    payload = StructuredPlanProjection.evidence_payload(ref) || %{}

    Map.get(payload, @published_head_sha_key) || Map.get(payload, @head_sha_key)
  end

  @spec category_refs(map(), [String.t()]) :: [map()]
  def category_refs(item, evidence_kinds) do
    item
    |> StructuredPlanProjection.item_evidence_refs()
    |> Enum.filter(&(StructuredPlanProjection.evidence_kind(&1) in evidence_kinds))
  end

  @spec latest_observed_at([map()]) :: DateTime.t() | nil
  def latest_observed_at(refs) do
    refs
    |> Enum.flat_map(fn ref ->
      case parse_datetime(StructuredPlanProjection.evidence_observed_at(ref)) do
        %DateTime{} = datetime -> [datetime]
        nil -> []
      end
    end)
    |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)
  end

  @spec head_mismatch?(term(), term()) :: boolean()
  def head_mismatch?(left, right), do: present?(left) and present?(right) and left != right

  @spec newer_than?(DateTime.t() | nil, DateTime.t() | nil) :: boolean()
  def newer_than?(nil, _right), do: false
  def newer_than?(_left, nil), do: false
  def newer_than?(left, right), do: DateTime.compare(left, right) == :gt

  defp all_evidence_refs(plan) do
    plan
    |> StructuredPlanProjection.items()
    |> Enum.flat_map(&StructuredPlanProjection.item_evidence_refs/1)
  end

  defp latest_ref(refs) do
    Enum.max_by(refs, &observed_at_unix/1, fn -> nil end)
  end

  defp observed_at_unix(ref) do
    case parse_datetime(StructuredPlanProjection.evidence_observed_at(ref || %{})) do
      %DateTime{} = datetime -> DateTime.to_unix(datetime, :microsecond)
      nil -> -1
    end
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end

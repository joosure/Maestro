defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceSource do
  @moduledoc """
  Evidence lookup and issue-derived observation projection for review handoff.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceStore
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ChangeProposalUrl
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.{Envelope, Values}

  @observations_key Envelope.observations_key()
  @change_proposal_key Evidence.change_proposal_key()
  @status_key Evidence.status_key()
  @source_key Evidence.source_key()
  @id_key Evidence.id_key()
  @url_key Evidence.url_key()
  @linked_to_tracker_key Evidence.linked_to_tracker_key()
  @linked_status Values.linked_status()
  @tracker_observed_source Values.tracker_observed_source()

  @issue_id_key "id"
  @issue_identifier_key "identifier"
  @issue_attachments_key "attachments"
  @attachment_id_key "id"
  @attachment_url_key "url"
  @nodes_key "nodes"

  @spec evidence_for_issue(map(), keyword()) :: map()
  def evidence_for_issue(issue, opts) do
    explicit_evidence = opts |> Keyword.get(:evidence, %{}) |> normalize_evidence()
    run_id = Keyword.get(opts, :run_id)
    issue_keys = issue_keys(issue, Keyword.get(opts, :issue_key))

    scoped_issue_keys =
      run_id
      |> EvidenceStore.scope_issue_keys(issue_keys, opts)

    issue_keys
    |> EvidenceStore.snapshot(opts)
    |> deep_merge(EvidenceStore.snapshot(scoped_issue_keys, opts))
    |> normalize_evidence()
    |> deep_merge(explicit_evidence)
  end

  @spec normalized_observations(map(), map()) :: map()
  def normalized_observations(evidence, issue) do
    evidence
    |> normalize_evidence()
    |> Map.get(@observations_key, %{})
    |> deep_merge(tracker_issue_observations(issue))
  end

  @spec observation(map(), String.t()) :: map()
  def observation(observations, key) when is_map(observations), do: Map.get(observations, key, %{})
  def observation(_observations, _key), do: %{}

  defp normalize_evidence(%{@observations_key => observations} = evidence) when is_map(observations), do: evidence
  defp normalize_evidence(observations) when is_map(observations), do: %{@observations_key => observations}
  defp normalize_evidence(_evidence), do: %{@observations_key => %{}}

  defp tracker_issue_observations(issue) do
    case issue_change_proposal_attachment(issue) do
      nil ->
        %{}

      attachment ->
        %{
          @change_proposal_key =>
            compact(%{
              @status_key => @linked_status,
              @source_key => @tracker_observed_source,
              @id_key => Map.get(attachment, @attachment_id_key),
              @url_key => Map.get(attachment, @attachment_url_key),
              @linked_to_tracker_key => true
            })
        }
    end
  end

  defp issue_change_proposal_attachment(issue) do
    issue
    |> issue_attachments()
    |> Enum.find(&change_proposal_attachment?/1)
  end

  defp change_proposal_attachment?(attachment) when is_map(attachment) do
    attachment
    |> string_value(@attachment_url_key)
    |> ChangeProposalUrl.change_proposal_url?()
  end

  defp change_proposal_attachment?(_attachment), do: false

  defp issue_keys(issue, explicit_key) do
    [
      explicit_key,
      string_value(issue, @issue_id_key),
      string_value(issue, @issue_identifier_key)
    ]
    |> Enum.flat_map(&present_values/1)
    |> Enum.uniq()
  end

  defp issue_attachments(%{attachments: attachments}), do: nodes(attachments)
  defp issue_attachments(%{@issue_attachments_key => attachments}), do: nodes(attachments)
  defp issue_attachments(_issue), do: []

  defp nodes(value) do
    case value do
      %{@nodes_key => nodes} when is_list(nodes) -> nodes
      nodes when is_list(nodes) -> nodes
      _value -> []
    end
  end

  defp string_value(%{id: value}, @issue_id_key), do: normalize_string(value)
  defp string_value(%{identifier: value}, @issue_identifier_key), do: normalize_string(value)

  defp string_value(map, key) when is_map(map) and is_binary(key) do
    map
    |> Map.get(key)
    |> normalize_string()
  end

  defp string_value(_map, _key), do: nil

  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp normalize_string(_value), do: nil

  defp present_values(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      trimmed -> [trimmed]
    end
  end

  defp present_values(value) when is_integer(value), do: [Integer.to_string(value)]
  defp present_values(value) when is_atom(value), do: present_values(Atom.to_string(value))
  defp present_values(_value), do: []

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, left_value, right_value when is_map(left_value) and is_map(right_value) -> deep_merge(left_value, right_value)
      _key, _left_value, right_value -> right_value
    end)
  end

  defp compact(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end

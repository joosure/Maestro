defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.ReferenceExtractor do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference

  @workflow_key "workflow"
  @change_proposal_reference_key "change_proposal"
  @issue_branch_key "branch_name"

  @spec from_issue(map()) :: Reference.t() | nil
  def from_issue(issue) when is_map(issue) do
    issue
    |> issue_map_candidates()
    |> Enum.find_value(&Reference.from_map/1)
    |> with_issue_branch(issue_branch(issue))
  end

  def from_issue(_issue), do: nil

  defp issue_map_candidates(issue) when is_map(issue) do
    workflow = normalize_map(issue_workflow(issue))

    [
      map_value(workflow, @change_proposal_reference_key),
      map_value(issue, @change_proposal_reference_key)
    ]
  end

  defp with_issue_branch(%Reference{branch: nil} = reference, branch) do
    reference
    |> Map.put(:branch, present_string(branch))
    |> blank_reference_to_nil()
  end

  defp with_issue_branch(nil, branch) do
    %Reference{branch: present_string(branch)}
    |> blank_reference_to_nil()
  end

  defp with_issue_branch(reference, _branch), do: reference

  defp blank_reference_to_nil(%Reference{} = reference) do
    if Enum.any?([reference.number, reference.url, reference.branch], &present_string?/1) do
      reference
    end
  end

  defp issue_workflow(%{workflow: workflow}) when is_map(workflow), do: workflow
  defp issue_workflow(%{@workflow_key => workflow}) when is_map(workflow), do: workflow
  defp issue_workflow(_issue), do: %{}

  defp issue_branch(%{branch_name: branch}), do: branch
  defp issue_branch(%{@issue_branch_key => branch}), do: branch
  defp issue_branch(_issue), do: nil

  defp map_value(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)

  defp map_value(_map, _key), do: nil

  defp normalize_map(value) when is_map(value), do: value

  defp present_string(value) when is_integer(value), do: Integer.to_string(value)

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_value), do: nil

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
end

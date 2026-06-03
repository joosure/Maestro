defmodule SymphonyElixir.Tracker.ChangeProposalReference do
  @moduledoc false

  alias SymphonyElixir.Issue

  defstruct [:number, :url, :branch]

  @type t :: %__MODULE__{
          number: String.t() | integer() | nil,
          url: String.t() | nil,
          branch: String.t() | nil
        }

  @spec from_issue(Issue.t() | map()) :: t() | nil
  def from_issue(%Issue{} = issue) do
    issue
    |> issue_struct_candidates()
    |> Enum.find_value(&from_map/1)
    |> with_issue_branch(issue.branch_name)
  end

  def from_issue(issue) when is_map(issue) do
    issue
    |> issue_map_candidates()
    |> Enum.find_value(&from_map/1)
    |> with_issue_branch(map_value(issue, "branch_name") || map_value(issue, "branchName"))
  end

  def from_issue(_issue), do: nil

  @spec from_map(map()) :: t() | nil
  def from_map(value) when is_map(value) do
    %__MODULE__{
      number: present_string(map_value(value, "number") || map_value(value, "change_proposal_id") || map_value(value, "changeProposalId")),
      url: present_string(map_value(value, "url")),
      branch: present_string(map_value(value, "branch") || map_value(value, "head_ref") || map_value(value, "headRefName"))
    }
    |> blank_to_nil()
  end

  def from_map(_value), do: nil

  defp issue_struct_candidates(%Issue{} = issue) do
    workflow = normalize_map(issue.workflow)

    [
      map_value(workflow, "change_proposal"),
      map_value(workflow, "changeProposal")
    ]
  end

  defp issue_map_candidates(issue) when is_map(issue) do
    workflow = normalize_map(map_value(issue, "workflow"))

    [
      map_value(workflow, "change_proposal"),
      map_value(workflow, "changeProposal"),
      map_value(issue, "change_proposal"),
      map_value(issue, "changeProposal")
    ]
  end

  defp with_issue_branch(%__MODULE__{branch: nil} = reference, branch) do
    %{reference | branch: present_string(branch)}
    |> blank_to_nil()
  end

  defp with_issue_branch(nil, branch) do
    %__MODULE__{branch: present_string(branch)}
    |> blank_to_nil()
  end

  defp with_issue_branch(reference, _branch), do: reference

  defp blank_to_nil(%__MODULE__{} = reference) do
    if Enum.any?([reference.number, reference.url, reference.branch], &present_string?/1) do
      reference
    end
  end

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp map_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

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

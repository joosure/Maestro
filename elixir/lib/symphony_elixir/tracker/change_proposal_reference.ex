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
    change_proposal =
      issue.workflow
      |> map_value("change_proposal")
      |> normalize_map()

    %__MODULE__{
      number: present_string(map_value(change_proposal, "number")),
      url: present_string(map_value(change_proposal, "url")),
      branch: present_string(map_value(change_proposal, "branch") || issue.branch_name)
    }
    |> blank_to_nil()
  end

  def from_issue(_issue), do: nil

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

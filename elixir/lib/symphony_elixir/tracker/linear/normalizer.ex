defmodule SymphonyElixir.Tracker.Linear.Normalizer do
  @moduledoc """
  Normalizes Linear issue payloads into `SymphonyElixir.Issue`.
  """

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle

  @type assignee_filter :: %{optional(:configured_assignee) => String.t(), required(:match_values) => MapSet.t(String.t())} | nil

  @spec normalize_issue(map(), assignee_filter(), keyword()) :: Issue.t() | nil
  def normalize_issue(issue, assignee_filter \\ nil, opts \\ [])

  def normalize_issue(issue, assignee_filter, opts) when is_map(issue) and is_list(opts) do
    assignee = issue["assignee"]
    state_phase_map = Keyword.get(opts, :state_phase_map, %{})
    workflow = Keyword.get(opts, :workflow, %{})
    raw_state = get_in(issue, ["state", "name"])

    %Issue{
      id: issue["id"],
      identifier: issue["identifier"],
      title: issue["title"],
      description: issue["description"],
      priority: parse_priority(issue["priority"]),
      state: raw_state,
      lifecycle_phase: WorkflowLifecycle.phase_for_state(raw_state, state_phase_map),
      branch_name: issue["branchName"],
      url: issue["url"],
      assignee_id: assignee_field(assignee, "id"),
      blocked_by: extract_blockers(issue, state_phase_map),
      labels: extract_labels(issue),
      workflow: workflow,
      assigned_to_worker: assigned_to_worker?(assignee, assignee_filter),
      created_at: parse_datetime(issue["createdAt"]),
      updated_at: parse_datetime(issue["updatedAt"])
    }
  end

  def normalize_issue(_issue, _assignee_filter, _opts), do: nil

  @doc false
  @spec assignee_id(map()) :: String.t() | nil
  def assignee_id(%{} = assignee), do: normalize_assignee_match_value(assignee["id"])
  def assignee_id(_assignee), do: nil

  @doc false
  @spec normalize_assignee_match_value(term()) :: String.t() | nil
  def normalize_assignee_match_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_assignee_match_value(_value), do: nil

  defp assignee_field(%{} = assignee, field) when is_binary(field), do: assignee[field]
  defp assignee_field(_assignee, _field), do: nil

  defp assigned_to_worker?(_assignee, nil), do: true

  defp assigned_to_worker?(%{} = assignee, %{match_values: match_values})
       when is_struct(match_values, MapSet) do
    assignee
    |> assignee_id()
    |> then(fn
      nil -> false
      assignee_id -> MapSet.member?(match_values, assignee_id)
    end)
  end

  defp assigned_to_worker?(_assignee, _assignee_filter), do: false

  defp extract_labels(%{"labels" => %{"nodes" => labels}}) when is_list(labels) do
    labels
    |> Enum.map(& &1["name"])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
  end

  defp extract_labels(_issue), do: []

  defp extract_blockers(%{"inverseRelations" => %{"nodes" => inverse_relations}}, state_phase_map)
       when is_list(inverse_relations) do
    inverse_relations
    |> Enum.flat_map(fn
      %{"type" => relation_type, "issue" => blocker_issue}
      when is_binary(relation_type) and is_map(blocker_issue) ->
        if String.downcase(String.trim(relation_type)) == "blocks" do
          blocker_state = get_in(blocker_issue, ["state", "name"])

          [
            %{
              id: blocker_issue["id"],
              identifier: blocker_issue["identifier"],
              state: blocker_state,
              lifecycle_phase: WorkflowLifecycle.phase_for_state(blocker_state, state_phase_map)
            }
          ]
        else
          []
        end

      _ ->
        []
    end)
  end

  defp extract_blockers(_issue, _state_phase_map), do: []

  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_priority(priority) when is_integer(priority), do: priority
  defp parse_priority(_priority), do: nil
end

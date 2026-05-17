defmodule SymphonyElixir.Tracker.Memory do
  @moduledoc """
  In-memory tracker adapter used for tests and local development.
  """

  @behaviour SymphonyElixir.Tracker.Adapter

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.Config
  alias SymphonyElixir.Tracker.Kinds
  alias SymphonyElixir.Tracker.ProjectRef
  alias SymphonyElixir.Tracker.StatePrecondition
  alias SymphonyElixir.Workflow.CapabilityNames

  @provider_kind Kinds.memory()

  @spec kind() :: String.t()
  def kind, do: @provider_kind

  @spec capabilities() :: [String.t()]
  def capabilities do
    [
      CapabilityNames.tracker_issue_read(),
      CapabilityNames.tracker_issue_update(),
      CapabilityNames.tracker_issue_create(),
      CapabilityNames.tracker_comment_read(),
      CapabilityNames.tracker_comment_write(),
      CapabilityNames.tracker_comment_update(),
      CapabilityNames.tracker_state_update(),
      CapabilityNames.tracker_relation_read(),
      CapabilityNames.tracker_relation_write()
    ]
  end

  @spec defaults() :: map()
  def defaults do
    %{
      lifecycle: %{
        "active_states" => [],
        "terminal_states" => []
      }
    }
  end

  @spec validate_config(Config.t()) :: :ok | {:error, term()}
  def validate_config(_tracker), do: :ok

  @spec dynamic_tools(Config.t()) :: [map()]
  def dynamic_tools(_tracker), do: []

  @spec prepare_workspace(Config.t(), Path.t(), keyword()) :: :ok
  def prepare_workspace(_tracker, _workspace, _opts \\ []), do: :ok

  @spec project_ref(Config.t()) :: ProjectRef.t()
  def project_ref(_tracker), do: %ProjectRef{kind: kind()}

  @spec healthcheck(Config.t(), keyword()) :: :ok
  def healthcheck(_tracker, _opts \\ []), do: :ok

  @spec fetch_candidate_issues(Config.t(), keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues(tracker, _opts \\ []) do
    {:ok, issue_entries(tracker)}
  end

  @spec fetch_issues_by_states(Config.t(), [String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(tracker, state_names, _opts \\ []) do
    normalized_states =
      state_names
      |> Enum.map(&normalize_state/1)
      |> MapSet.new()

    {:ok,
     Enum.filter(issue_entries(tracker), fn %Issue{state: state} ->
       MapSet.member?(normalized_states, normalize_state(state))
     end)}
  end

  @spec fetch_issue_states_by_ids(Config.t(), [String.t()], keyword()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(tracker, issue_ids, _opts \\ []) do
    wanted_ids = MapSet.new(issue_ids)

    {:ok,
     Enum.filter(issue_entries(tracker), fn %Issue{id: id} ->
       MapSet.member?(wanted_ids, id)
     end)}
  end

  @spec create_comment(Config.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(_tracker, issue_id, body, _opts \\ []) do
    send_event({:memory_tracker_comment, issue_id, body})
    :ok
  end

  @spec update_issue_state(Config.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_issue_state(tracker, issue_id, state_name, opts \\ []) do
    with :ok <- confirm_expected_current_state(tracker, issue_id, opts) do
      if persist_state_updates?(tracker) do
        persist_state_update(issue_id, state_name)
      end

      send_event({:memory_tracker_state_update, issue_id, state_name})
      :ok
    end
  end

  defp configured_issues do
    Application.get_env(:symphony_elixir, :memory_tracker_issues, [])
  end

  defp issue_entries(tracker) do
    state_overrides = state_overrides(tracker)

    tracker
    |> template_issues()
    |> Kernel.++(configured_issues())
    |> Enum.flat_map(&normalize_issue/1)
    |> Enum.map(&apply_state_override(&1, state_overrides))
  end

  defp template_issues(tracker) do
    provider = Config.provider(tracker)

    cond do
      is_list(nested_value(provider, "issues")) ->
        nested_value(provider, "issues")

      is_map(nested_value(provider, "issue")) ->
        [nested_value(provider, "issue")]

      true ->
        []
    end
  end

  defp normalize_issue(%Issue{} = issue), do: [issue]

  defp normalize_issue(issue) when is_map(issue) do
    issue
    |> normalize_issue_attrs()
    |> required_issue?()
    |> case do
      true -> [struct(Issue, normalize_issue_attrs(issue))]
      false -> []
    end
  end

  defp normalize_issue(_issue), do: []

  defp required_issue?(attrs) do
    is_binary(attrs.id) and attrs.id != "" and
      is_binary(attrs.identifier) and attrs.identifier != "" and
      is_binary(attrs.title) and attrs.title != "" and
      is_binary(attrs.state) and attrs.state != ""
  end

  defp normalize_issue_attrs(issue) when is_map(issue) do
    %{
      id: issue |> nested_value("id") |> normalize_optional_string(),
      identifier: issue |> nested_value("identifier") |> normalize_optional_string(),
      title: issue |> nested_value("title") |> normalize_optional_string(),
      description: issue |> nested_value("description") |> normalize_optional_string(),
      priority: issue |> nested_value("priority") |> normalize_integer(),
      state: issue |> nested_value("state") |> normalize_optional_string(),
      lifecycle_phase: issue |> nested_value("lifecycle_phase") |> normalize_optional_string(),
      workitem_type_id: issue |> nested_value("workitem_type_id") |> normalize_optional_string(),
      branch_name: issue |> nested_value("branch_name") |> normalize_optional_string(),
      url: issue |> nested_value("url") |> normalize_optional_string(),
      assignee_id: issue |> nested_value("assignee_id") |> normalize_optional_string(),
      blocked_by: issue |> nested_value("blocked_by") |> normalize_list(),
      labels: issue |> nested_value("labels") |> normalize_string_list(),
      workflow: issue |> nested_value("workflow") |> normalize_map(),
      assigned_to_worker: issue |> nested_value("assigned_to_worker") |> normalize_boolean(true),
      created_at: nested_value(issue, "created_at"),
      updated_at: nested_value(issue, "updated_at")
    }
  end

  defp persist_state_updates?(tracker) do
    tracker
    |> Config.provider()
    |> nested_value("persist_state_updates")
    |> Kernel.==(true)
  end

  defp state_overrides(tracker) do
    if persist_state_updates?(tracker) do
      Application.get_env(:symphony_elixir, :memory_tracker_issue_state_overrides, %{})
    else
      %{}
    end
  end

  defp persist_state_update(issue_id, state_name) when is_binary(issue_id) and is_binary(state_name) do
    overrides = Application.get_env(:symphony_elixir, :memory_tracker_issue_state_overrides, %{})
    Application.put_env(:symphony_elixir, :memory_tracker_issue_state_overrides, Map.put(overrides, issue_id, state_name))
  end

  defp persist_state_update(_issue_id, _state_name), do: :ok

  defp confirm_expected_current_state(tracker, issue_id, opts)
       when is_binary(issue_id) and is_list(opts) do
    case StatePrecondition.expected_current_state(opts) do
      nil ->
        :ok

      expected ->
        case Enum.find(issue_entries(tracker), &(&1.id == issue_id)) do
          %Issue{} = issue ->
            StatePrecondition.check(kind(), :update_issue_state, issue, expected)

          nil ->
            {:error, StatePrecondition.issue_missing_error(kind(), :update_issue_state, issue_id, expected)}
        end
    end
  end

  defp apply_state_override(%Issue{id: id} = issue, overrides) when is_binary(id) and is_map(overrides) do
    case Map.get(overrides, id) do
      state when is_binary(state) and state != "" -> %{issue | state: state}
      _state -> issue
    end
  end

  defp apply_state_override(issue, _overrides), do: issue

  defp send_event(message) do
    case Application.get_env(:symphony_elixir, :memory_tracker_recipient) do
      pid when is_pid(pid) -> send(pid, message)
      _ -> :ok
    end
  end

  defp normalize_state(state) when is_binary(state) do
    state
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_state(_state), do: ""

  defp nested_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp nested_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil

  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp normalize_integer(_value), do: nil

  defp normalize_list(values) when is_list(values), do: values
  defp normalize_list(_values), do: []

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.flat_map(fn
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> []
          trimmed -> [trimmed]
        end

      _value ->
        []
    end)
  end

  defp normalize_string_list(_values), do: []

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp normalize_boolean(value, _default) when is_boolean(value), do: value
  defp normalize_boolean(_value, default), do: default
end

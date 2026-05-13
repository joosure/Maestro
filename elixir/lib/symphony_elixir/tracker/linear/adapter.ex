defmodule SymphonyElixir.Tracker.Linear.Adapter do
  @moduledoc """
  Linear-backed tracker adapter.

  Implements `SymphonyElixir.Tracker.Adapter` for the Linear project
  management platform. This is a thin delegation layer:

    * Read/write operations → `Linear.Client`
    * Dynamic tool execution → `Linear.ToolExecutor`
    * Configuration validation → inline (lightweight)
  """

  @behaviour SymphonyElixir.Tracker.Adapter

  import SymphonyElixir.Tracker.ConfigAccess, only: [blank?: 1, map_get_existing_atom: 2]

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Error
  alias SymphonyElixir.Tracker.Linear.{Client, ToolExecutor}
  alias SymphonyElixir.Tracker.ProjectRef

  # ── Required callbacks ───────────────────────────────────────────

  @spec kind() :: String.t()
  def kind, do: "linear"

  @spec capabilities() :: [String.t()]
  def capabilities do
    [
      "tracker.issue.read",
      "tracker.issue.update",
      "tracker.comment.read",
      "tracker.comment.write",
      "tracker.comment.update",
      "tracker.state.update",
      "tracker.relation.read",
      "tracker.relation.write",
      "tracker.issue_snapshot",
      "tracker.move_issue",
      "tracker.upsert_workpad",
      "tracker.attach_change_proposal"
    ]
  end

  @spec defaults() :: map()
  def defaults do
    %{
      endpoint: "https://api.linear.app/graphql",
      env_vars: %{
        auth: %{
          api_key: "LINEAR_API_KEY"
        },
        provider: %{
          assignee: "LINEAR_ASSIGNEE"
        }
      },
      lifecycle: %{
        "active_states" => ["Todo", "In Progress"],
        "terminal_states" => ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"],
        "state_phase_map" => %{
          "Backlog" => "backlog",
          "Todo" => "todo",
          "In Progress" => "in_progress",
          "In Review" => "human_review",
          "Merging" => "merging",
          "Rework" => "rework",
          "Done" => "done",
          "Closed" => "canceled",
          "Cancelled" => "canceled",
          "Canceled" => "canceled",
          "Duplicate" => "canceled"
        }
      }
    }
  end

  @spec validate_config(TrackerConfig.t()) :: :ok | {:error, term()}
  def validate_config(tracker) when is_map(tracker) do
    cond do
      blank?(TrackerConfig.api_key(tracker)) ->
        {:error, config_error(:missing_linear_api_token, :missing_credentials, "Linear API key is required.")}

      blank?(project_slug(tracker)) ->
        {:error, config_error(:missing_linear_project_slug, :missing_project_reference, "Linear project slug is required.")}

      true ->
        :ok
    end
  end

  # ── Dynamic tools ────────────────────────────────────────────────

  @spec dynamic_tools(TrackerConfig.t()) :: [map()]
  def dynamic_tools(tracker), do: ToolExecutor.tool_specs(tracker)

  @spec tool_environment(TrackerConfig.t()) :: map()
  def tool_environment(tracker) when is_map(tracker) do
    %{}
    |> maybe_put_env("SYMPHONY_LINEAR_API_KEY", TrackerConfig.api_key(tracker))
    |> maybe_put_env("SYMPHONY_LINEAR_ENDPOINT", TrackerConfig.endpoint(tracker))
  end

  @spec execute_dynamic_tool(TrackerConfig.t(), String.t() | nil, term(), keyword()) ::
          SymphonyElixir.Tracker.Adapter.tool_result()
  def execute_dynamic_tool(tracker, tool, arguments, opts) do
    ToolExecutor.execute(tracker, tool, arguments, opts)
  end

  # ── Metadata ─────────────────────────────────────────────────────

  @spec project_ref(TrackerConfig.t()) :: ProjectRef.t()
  def project_ref(tracker) when is_map(tracker) do
    case project_slug(tracker) do
      project_slug when is_binary(project_slug) and project_slug != "" ->
        %ProjectRef{
          kind: kind(),
          id: project_slug,
          url: "https://linear.app/project/#{project_slug}/issues"
        }

      _ ->
        %ProjectRef{kind: kind()}
    end
  end

  # ── Reader ───────────────────────────────────────────────────────

  @spec fetch_candidate_issues(TrackerConfig.t(), keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues(tracker, _opts \\ []) when is_map(tracker) do
    client_module().fetch_candidate_issues(tracker)
  end

  @spec fetch_issues_by_states(TrackerConfig.t(), [String.t()], keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(tracker, states, _opts \\ []) when is_map(tracker) and is_list(states) do
    client_module().fetch_issues_by_states(states, tracker)
  end

  @spec fetch_issue_states_by_ids(TrackerConfig.t(), [String.t()], keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(tracker, issue_ids, _opts \\ [])
      when is_map(tracker) and is_list(issue_ids) do
    client_module().fetch_issue_states_by_ids(issue_ids, tracker)
  end

  # ── Writer ───────────────────────────────────────────────────────

  @spec create_comment(TrackerConfig.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(tracker, issue_id, body, _opts \\ [])
      when is_map(tracker) and is_binary(issue_id) and is_binary(body) do
    client_module().create_comment(issue_id, body, tracker: tracker)
  end

  @spec update_issue_state(TrackerConfig.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_issue_state(tracker, issue_id, state_name, _opts \\ [])
      when is_map(tracker) and is_binary(issue_id) and is_binary(state_name) do
    client_module().update_issue_state(issue_id, state_name, tracker: tracker)
  end

  # ── Workspace ────────────────────────────────────────────────────

  @spec prepare_workspace(TrackerConfig.t(), Path.t(), keyword()) :: :ok
  def prepare_workspace(_tracker, _workspace, _opts \\ []), do: :ok

  # ── Healthcheck ──────────────────────────────────────────────────

  @spec healthcheck(TrackerConfig.t(), keyword()) :: :ok | {:error, Error.t() | term()}
  def healthcheck(tracker, _opts \\ []) when is_map(tracker) do
    client_module().healthcheck(tracker: tracker)
  end

  # ── Private ──────────────────────────────────────────────────────

  defp project_slug(tracker) when is_map(tracker) do
    tracker
    |> TrackerConfig.provider()
    |> provider_value("project_slug")
  end

  defp provider_value(provider, key) when is_map(provider) and is_binary(key) do
    Map.get(provider, key) || map_get_existing_atom(provider, key)
  end

  defp provider_value(_provider, _key), do: nil

  defp maybe_put_env(env, _key, value) when value in [nil, ""], do: env

  defp maybe_put_env(env, key, value) when is_binary(key) do
    Map.put(env, key, to_string(value))
  end

  defp client_module do
    Application.get_env(:symphony_elixir, :linear_client_module, Client)
  end

  defp config_error(source_reason, code, message) do
    Error.new(%{
      provider: kind(),
      operation: :validate_config,
      code: code,
      message: message,
      details: %{source_reason: source_reason}
    })
  end
end

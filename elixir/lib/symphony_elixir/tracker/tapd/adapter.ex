defmodule SymphonyElixir.Tracker.Tapd.Adapter do
  @moduledoc """
  TAPD-backed tracker adapter.

  Implements `SymphonyElixir.Tracker.Adapter` for the TAPD project
  management platform. Delegates dynamic tool execution to
  `ToolExecutor` and deep configuration validation to `ConfigValidator`.
  """

  @behaviour SymphonyElixir.Tracker.Adapter

  import SymphonyElixir.Tracker.ConfigAccess, only: [blank?: 1, provider_field: 2]

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Error
  alias SymphonyElixir.Tracker.ProjectRef
  alias SymphonyElixir.Tracker.Tapd.{Client, ConfigValidator, ToolExecutor, WorkspacePreparation}

  # ── Required callbacks ───────────────────────────────────────────

  @spec kind() :: String.t()
  def kind, do: "tapd"

  @spec capabilities() :: [String.t()]
  def capabilities do
    [
      "tracker.issue.read",
      "tracker.issue.update",
      "tracker.issue.create",
      "tracker.comment.read",
      "tracker.comment.write",
      "tracker.comment.update",
      "tracker.state.update",
      "tracker.relation.read",
      "tracker.relation.write",
      "tracker.issue_snapshot",
      "tracker.move_issue",
      "tracker.upsert_workpad",
      "tracker.attach_change_proposal",
      "tracker.upsert_comment",
      "tracker.create_follow_up_issue",
      "tracker.read_issue_relations",
      "tracker.add_issue_relation",
      "tracker.read_issue_dependencies",
      "tracker.save_issue_dependency",
      "tracker.provider_diagnostics"
    ]
  end

  @spec defaults() :: map()
  def defaults do
    %{
      endpoint: "https://api.tapd.cn",
      env_vars: %{
        auth: %{
          api_key: "TAPD_API_USER",
          api_secret: "TAPD_API_PASSWORD"
        },
        provider: %{
          platform: %{
            comment_author: "TAPD_COMMENT_AUTHOR"
          }
        }
      },
      provider: %{
        "platform" => %{}
      }
    }
  end

  @spec validate_config(TrackerConfig.t()) :: :ok | {:error, term()}
  def validate_config(tracker) when is_map(tracker) do
    platform = provider_field(tracker, "platform")
    workspace_id = Map.get(platform, "workspace_id")

    cond do
      blank?(TrackerConfig.api_key(tracker)) ->
        {:error, credential_error(:missing_tapd_api_user, "TAPD API user is required.")}

      blank?(TrackerConfig.api_secret(tracker)) ->
        {:error, credential_error(:missing_tapd_api_secret, "TAPD API secret is required.")}

      blank?(workspace_id) ->
        {:error, credential_error(:missing_tapd_workspace_id, "TAPD workspace id is required.", :missing_project_reference)}

      true ->
        ConfigValidator.validate(tracker, platform)
    end
  end

  # ── Dynamic tools ────────────────────────────────────────────────

  @spec dynamic_tools(TrackerConfig.t()) :: [map()]
  def dynamic_tools(_tracker), do: ToolExecutor.tool_specs()

  @spec execute_dynamic_tool(TrackerConfig.t(), String.t() | nil, term(), keyword()) ::
          SymphonyElixir.Tracker.Adapter.tool_result()
  def execute_dynamic_tool(tracker, tool, arguments, opts) do
    ToolExecutor.execute(tracker, tool, arguments, opts)
  end

  # ── Metadata ─────────────────────────────────────────────────────

  @spec project_ref(TrackerConfig.t()) :: ProjectRef.t()
  def project_ref(tracker) when is_map(tracker) do
    case Map.get(provider_field(tracker, "platform"), "workspace_id") do
      workspace_id when is_binary(workspace_id) and workspace_id != "" ->
        %ProjectRef{
          kind: kind(),
          id: workspace_id,
          url: "https://www.tapd.cn/#{workspace_id}/prong/stories/view"
        }

      _ ->
        %ProjectRef{kind: kind()}
    end
  end

  # ── Reader ───────────────────────────────────────────────────────

  @spec fetch_candidate_issues(TrackerConfig.t(), keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues(tracker, _opts \\ []) when is_map(tracker), do: Client.fetch_candidate_issues(tracker)

  @spec fetch_issues_by_states(TrackerConfig.t(), [String.t()], keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(tracker, states, _opts \\ []) when is_map(tracker) and is_list(states) do
    Client.fetch_issues_by_states(states, tracker)
  end

  @spec fetch_issue_states_by_ids(TrackerConfig.t(), [String.t()], keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(tracker, issue_ids, _opts \\ [])
      when is_map(tracker) and is_list(issue_ids) do
    Client.fetch_issue_states_by_ids(issue_ids, tracker)
  end

  # ── Writer ───────────────────────────────────────────────────────

  @spec create_comment(TrackerConfig.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(tracker, issue_id, body, _opts \\ [])
      when is_map(tracker) and is_binary(issue_id) and is_binary(body) do
    Client.create_story_comment(issue_id, body, tracker: tracker)
  end

  @spec update_issue_state(TrackerConfig.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_issue_state(tracker, issue_id, state_name, _opts \\ [])
      when is_map(tracker) and is_binary(issue_id) and is_binary(state_name) do
    Client.update_story_status(issue_id, state_name, tracker: tracker)
  end

  # ── Workspace ────────────────────────────────────────────────────

  @spec prepare_workspace(TrackerConfig.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def prepare_workspace(_tracker, workspace, opts \\ []) when is_binary(workspace) do
    worker_host = Keyword.get(opts, :worker_host)
    WorkspacePreparation.ensure_workpad_ignore(workspace, worker_host, opts)
  end

  # ── Healthcheck ──────────────────────────────────────────────────

  @spec healthcheck(TrackerConfig.t(), keyword()) :: :ok | {:error, Error.t() | term()}
  def healthcheck(tracker, _opts \\ []) when is_map(tracker) do
    workspace_id = Map.get(provider_field(tracker, "platform"), "workspace_id")

    case Client.request("GET", "/quickstart/testauth", %{"workspace_id" => workspace_id}, tracker: tracker) do
      {:ok, _body} ->
        :ok

      {:error, reason} ->
        {:error, Error.normalize(kind(), :healthcheck, reason)}
    end
  end

  defp credential_error(source_reason, message, code \\ :missing_credentials) do
    Error.new(%{
      provider: kind(),
      operation: :validate_config,
      code: code,
      message: message,
      details: %{source_reason: source_reason}
    })
  end
end

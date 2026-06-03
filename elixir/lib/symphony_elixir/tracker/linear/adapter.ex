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
  alias SymphonyElixir.Tracker.Kinds
  alias SymphonyElixir.Tracker.Linear.{Client, ConfigValidator, ToolExecutor}
  alias SymphonyElixir.Tracker.ProjectRef
  alias SymphonyElixir.Tracker.StatePrecondition
  alias SymphonyElixir.Workflow.CapabilityNames

  @provider_kind Kinds.linear()
  @tool_api_key_env "SYMPHONY_LINEAR_API_KEY"
  @tool_endpoint_env "SYMPHONY_LINEAR_ENDPOINT"

  # ── Required callbacks ───────────────────────────────────────────

  @spec kind() :: String.t()
  def kind, do: @provider_kind

  @spec tool_api_key_env() :: String.t()
  def tool_api_key_env, do: @tool_api_key_env

  @spec tool_endpoint_env() :: String.t()
  def tool_endpoint_env, do: @tool_endpoint_env

  @spec capabilities() :: [String.t()]
  def capabilities do
    [
      CapabilityNames.tracker_issue_read(),
      CapabilityNames.tracker_issue_update(),
      CapabilityNames.tracker_comment_read(),
      CapabilityNames.tracker_comment_write(),
      CapabilityNames.tracker_comment_update(),
      CapabilityNames.tracker_state_update(),
      CapabilityNames.tracker_relation_read(),
      CapabilityNames.tracker_relation_write(),
      CapabilityNames.tracker_issue_snapshot(),
      CapabilityNames.tracker_move_issue(),
      CapabilityNames.tracker_upsert_workpad(),
      CapabilityNames.tracker_attach_change_proposal()
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
        ConfigValidator.validate(tracker)
    end
  end

  # ── Dynamic tools ────────────────────────────────────────────────

  @spec dynamic_tools(TrackerConfig.t()) :: [map()]
  def dynamic_tools(tracker), do: ToolExecutor.tool_specs(tracker)

  @spec tool_environment(TrackerConfig.t()) :: map()
  def tool_environment(tracker) when is_map(tracker) do
    %{}
    |> maybe_put_env(@tool_api_key_env, TrackerConfig.api_key(tracker))
    |> maybe_put_env(@tool_endpoint_env, TrackerConfig.endpoint(tracker))
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
  def update_issue_state(tracker, issue_id, state_name, opts \\ [])
      when is_map(tracker) and is_binary(issue_id) and is_binary(state_name) do
    with :ok <- confirm_expected_current_state(tracker, issue_id, opts) do
      client_module().update_issue_state(issue_id, state_name, Keyword.put(opts, :tracker, tracker))
    end
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

  defp confirm_expected_current_state(tracker, issue_id, opts)
       when is_map(tracker) and is_binary(issue_id) and is_list(opts) do
    case StatePrecondition.expected_current_state(opts) do
      nil ->
        :ok

      expected ->
        with {:ok, issues} <- client_fetch_issue_states_by_ids([issue_id], tracker, opts),
             {:ok, issue} <- single_issue(issues, issue_id, expected) do
          StatePrecondition.check(kind(), :update_issue_state, issue, expected)
        end
    end
  end

  defp client_fetch_issue_states_by_ids(issue_ids, tracker, opts) do
    client = client_module()

    if function_exported?(client, :fetch_issue_states_by_ids, 3) do
      client.fetch_issue_states_by_ids(issue_ids, tracker, opts)
    else
      client.fetch_issue_states_by_ids(issue_ids, tracker)
    end
  end

  defp single_issue([%SymphonyElixir.Issue{} = issue | _rest], _issue_id, _expected), do: {:ok, issue}

  defp single_issue([], issue_id, expected) do
    {:error, StatePrecondition.issue_missing_error(kind(), :update_issue_state, issue_id, expected)}
  end

  defp single_issue(issues, issue_id, expected) do
    {:error,
     Error.new(%{
       provider: kind(),
       operation: :update_issue_state,
       code: :invalid_response,
       message: "Linear issue precondition lookup returned an unexpected payload.",
       details: %{
         issue_id: issue_id,
         expected_current_state: expected,
         issue_count: if(is_list(issues), do: length(issues), else: nil),
         source_reason: :invalid_expected_current_state_lookup
       }
     })}
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

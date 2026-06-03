defmodule SymphonyElixir.Tracker.Adapter do
  @moduledoc """
  Unified tracker adapter contract.

  Defines the behaviour that all tracker integrations must implement.
  The facade (`SymphonyElixir.Tracker`) dispatches to whichever adapter
  the current `%Config{kind: kind}` resolves to via the `Registry`.

  ## Required Callbacks

    * `kind/0` — unique string identifier (e.g. `"linear"`, `"tapd"`)
    * `defaults/0` — default configuration map, including an `env_vars`
      mapping used by `TrackerSettingsFinalizer` for environment resolution
    * `validate_config/1` — fail-fast configuration validation; returns
      `:ok` or `{:error, %Error{} | term()}`

  ## Optional Callbacks

  All remaining callbacks are optional. The facade checks support at
  runtime via `function_exported?/3` and uses safe defaults
  (empty list, `:ok`, etc.) when a callback is not implemented.
  `tool_environment/1` is a tracker-owned dynamic-tool contract; it returns
  environment required by generated tracker helper tools, while higher layers
  decide whether that environment is passed to an AgentProvider process.
  `update_issue_state/4` implementations should honor
  `:expected_current_state` in opts when they can confirm the issue's current
  state before writing.

  ## Implementing a New Adapter

      defmodule MyApp.Tracker.Jira.Adapter do
        @behaviour SymphonyElixir.Tracker.Adapter

        def kind, do: "jira"
        def defaults, do: %{endpoint: "https://xxx.atlassian.net"}
        def validate_config(_tracker), do: :ok
        # implement optional callbacks as needed …
      end

  Register at runtime:

      config :symphony_elixir, :tracker_adapters, %{
        "jira" => MyApp.Tracker.Jira.Adapter
      }
  """

  alias SymphonyElixir.Tracker.{Config, Error, ProjectRef}

  @type result(t) :: {:ok, t} | {:error, Error.t() | term()}
  @type tool_result :: {:success, term()} | {:failure, term()} | {:error, Error.t() | term()}

  @callback kind() :: String.t()
  @callback defaults() :: map()
  @callback validate_config(Config.t()) :: :ok | {:error, Error.t() | term()}

  @callback fetch_candidate_issues(Config.t(), keyword()) :: result([term()])
  @callback fetch_issues_by_states(Config.t(), [String.t()], keyword()) :: result([term()])
  @callback fetch_issue_states_by_ids(Config.t(), [String.t()], keyword()) :: result([term()])

  @callback normalize_issue_id(Config.t(), String.t()) :: String.t() | nil

  @callback create_comment(Config.t(), String.t(), String.t(), keyword()) ::
              :ok | {:error, Error.t() | term()}
  @callback update_issue_state(Config.t(), String.t(), String.t(), keyword()) ::
              :ok | {:error, Error.t() | term()}

  @callback dynamic_tools(Config.t()) :: [map()]
  @callback tool_environment(Config.t()) :: map()
  @callback execute_dynamic_tool(Config.t(), String.t() | nil, term(), keyword()) :: tool_result()

  @callback prepare_workspace(Config.t(), Path.t(), keyword()) ::
              :ok | {:error, Error.t() | term()}

  @callback project_ref(Config.t()) :: ProjectRef.t() | nil
  @callback healthcheck(Config.t(), keyword()) :: :ok | {:error, Error.t() | term()}
  @callback capabilities() :: [String.t()]

  @optional_callbacks [
    capabilities: 0,
    fetch_candidate_issues: 2,
    fetch_issues_by_states: 3,
    fetch_issue_states_by_ids: 3,
    normalize_issue_id: 2,
    create_comment: 4,
    update_issue_state: 4,
    dynamic_tools: 1,
    tool_environment: 1,
    execute_dynamic_tool: 4,
    prepare_workspace: 3,
    project_ref: 1,
    healthcheck: 2
  ]
end

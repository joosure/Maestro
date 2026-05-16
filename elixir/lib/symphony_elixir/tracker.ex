defmodule SymphonyElixir.Tracker do
  @moduledoc """
  Facade for the pluggable issue-tracker subsystem.

  This module is the **only public entry point** that application code
  (Orchestrator, DynamicTool, Workspace …) should use. Internally it:

    1. Reads the current `%Config{}` via `Config.current!/0`
    2. Resolves the adapter module via `Registry.fetch!/1`
    3. Delegates to the adapter, passing the config as first argument

  ## Calling Conventions

  Every API has two forms:

    * **Implicit** – reads the current config from application state
      (`Tracker.fetch_candidate_issues()`)
    * **Explicit** – receives a `%Config{}` as first argument
      (`Tracker.fetch_candidate_issues(config, opts)`)

  ## Adding a New Tracker

  1. Implement `SymphonyElixir.Tracker.Adapter` behaviour
  2. Register via `config :symphony_elixir, :tracker_adapters, %{"kind" => Module}`
  3. Set `tracker.kind` in the user configuration
  """

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.{Adapter, ChangeProposalReference, Config, Error, ProjectRef, Registry}
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle

  @type tracker_config :: Config.t()
  @type result(t) :: {:ok, t} | {:error, Error.t() | term()}
  @type tool_result :: Adapter.tool_result()

  # ── Registry ──────────────────────────────────────────────────────

  @spec supported_kinds() :: [String.t()]
  def supported_kinds, do: Registry.supported_kinds()

  @spec current_kind() :: String.t() | nil
  def current_kind do
    case Config.current!() |> Config.kind() do
      kind when is_binary(kind) -> kind
      _ -> nil
    end
  end

  @spec adapter() :: module()
  def adapter, do: current!() |> elem(0)

  @spec adapter(tracker_config() | map()) :: module()
  def adapter(%Config{} = tracker), do: Registry.fetch!(Config.kind(tracker))
  def adapter(%{kind: kind} = _tracker) when is_binary(kind), do: Registry.fetch!(kind)
  def adapter(%{"kind" => kind} = _tracker) when is_binary(kind), do: Registry.fetch!(kind)

  @spec adapter_for(term()) :: module() | nil
  def adapter_for(kind) when is_binary(kind), do: Registry.fetch(kind)
  def adapter_for(_kind), do: nil

  @spec defaults(term()) :: map()
  def defaults(kind) do
    case adapter_for(kind) do
      nil -> %{}
      module -> module.defaults()
    end
  end

  @spec validate_config(tracker_config() | map()) :: :ok | {:error, term()}
  def validate_config(%Config{} = tracker) do
    do_validate_config(Config.kind(tracker), tracker)
  end

  def validate_config(%{kind: kind} = tracker) when is_binary(kind) do
    do_validate_config(kind, tracker)
  end

  def validate_config(%{"kind" => kind} = tracker) when is_binary(kind) do
    do_validate_config(kind, tracker)
  end

  def validate_config(_tracker), do: {:error, :missing_tracker_kind}

  defp do_validate_config(kind, tracker) do
    case adapter_for(kind) do
      nil -> {:error, {:unsupported_tracker_kind, kind}}
      module -> module.validate_config(tracker)
    end
  end

  # ── Reader ────────────────────────────────────────────────────────

  @spec fetch_candidate_issues(keyword()) :: result([term()])
  def fetch_candidate_issues(opts \\ [])
  def fetch_candidate_issues(opts) when is_list(opts), do: call(:fetch_candidate_issues, [opts])

  @spec fetch_candidate_issues(tracker_config() | map()) :: result([term()])
  def fetch_candidate_issues(%{kind: _} = tracker), do: fetch_candidate_issues(tracker, [])
  @spec fetch_candidate_issues(tracker_config() | map(), keyword()) :: result([term()])
  def fetch_candidate_issues(%{kind: _} = tracker, opts) when is_list(opts), do: call(tracker, :fetch_candidate_issues, [opts])

  @spec fetch_issues_by_states([String.t()], keyword()) :: result([term()])
  def fetch_issues_by_states(states, opts \\ [])
  def fetch_issues_by_states(states, opts) when is_list(states) and is_list(opts), do: call(:fetch_issues_by_states, [states, opts])

  @spec fetch_issues_by_states(tracker_config() | map(), [String.t()]) :: result([term()])
  def fetch_issues_by_states(%{kind: _} = tracker, states) when is_list(states), do: fetch_issues_by_states(tracker, states, [])
  @spec fetch_issues_by_states(tracker_config() | map(), [String.t()], keyword()) :: result([term()])
  def fetch_issues_by_states(%{kind: _} = tracker, states, opts) when is_list(states) and is_list(opts), do: call(tracker, :fetch_issues_by_states, [states, opts])

  @spec fetch_issue_states_by_ids([String.t()], keyword()) :: result([term()])
  def fetch_issue_states_by_ids(issue_ids, opts \\ [])
  def fetch_issue_states_by_ids(issue_ids, opts) when is_list(issue_ids) and is_list(opts), do: call(:fetch_issue_states_by_ids, [issue_ids, opts])

  @spec fetch_issue_states_by_ids(tracker_config() | map(), [String.t()]) :: result([term()])
  def fetch_issue_states_by_ids(%{kind: _} = tracker, issue_ids) when is_list(issue_ids), do: fetch_issue_states_by_ids(tracker, issue_ids, [])
  @spec fetch_issue_states_by_ids(tracker_config() | map(), [String.t()], keyword()) :: result([term()])
  def fetch_issue_states_by_ids(%{kind: _} = tracker, issue_ids, opts) when is_list(issue_ids) and is_list(opts), do: call(tracker, :fetch_issue_states_by_ids, [issue_ids, opts])

  @spec fetch_terminal_issues(keyword()) :: result([term()])
  def fetch_terminal_issues(opts \\ []) do
    {adapter, tracker} = current!()
    terminal = Config.terminal_states(tracker) || []

    case candidate_issue_ids(tracker) do
      [] ->
        dispatch(adapter, :fetch_issues_by_states, [tracker, terminal, opts])

      issue_ids ->
        with {:ok, issues} <- dispatch(adapter, :fetch_issue_states_by_ids, [tracker, issue_ids, opts]) do
          {:ok, Enum.filter(issues, &terminal_issue?(&1, terminal))}
        end
    end
  end

  # ── Writer ────────────────────────────────────────────────────────

  @spec create_comment(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(issue_id, body, opts \\ [])
  def create_comment(issue_id, body, opts) when is_binary(issue_id) and is_binary(body) and is_list(opts), do: call(:create_comment, [issue_id, body, opts])

  @spec create_comment(tracker_config() | map(), String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(%{kind: _} = tracker, issue_id, body) when is_binary(issue_id) and is_binary(body), do: create_comment(tracker, issue_id, body, [])
  @spec create_comment(tracker_config() | map(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(%{kind: _} = tracker, issue_id, body, opts) when is_binary(issue_id) and is_binary(body) and is_list(opts), do: call(tracker, :create_comment, [issue_id, body, opts])

  @spec update_issue_state(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name, opts \\ [])
  def update_issue_state(issue_id, state_name, opts) when is_binary(issue_id) and is_binary(state_name) and is_list(opts), do: call(:update_issue_state, [issue_id, state_name, opts])

  @spec update_issue_state(tracker_config() | map(), String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(%{kind: _} = tracker, issue_id, state_name) when is_binary(issue_id) and is_binary(state_name), do: update_issue_state(tracker, issue_id, state_name, [])
  @spec update_issue_state(tracker_config() | map(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_issue_state(%{kind: _} = tracker, issue_id, state_name, opts) when is_binary(issue_id) and is_binary(state_name) and is_list(opts),
    do: call(tracker, :update_issue_state, [issue_id, state_name, opts])

  # ── Tooling ───────────────────────────────────────────────────────

  @spec dynamic_tools() :: [map()]
  def dynamic_tools, do: call_optional(:dynamic_tools, [], [])

  @spec dynamic_tools(tracker_config() | map()) :: [map()]
  def dynamic_tools(%{kind: _} = tracker), do: call_optional(tracker, :dynamic_tools, [], [])

  @spec tool_environment() :: map()
  def tool_environment, do: call_optional(:tool_environment, [], %{})

  @spec tool_environment(tracker_config() | map()) :: map()
  def tool_environment(tracker) when is_map(tracker), do: optional(adapter(tracker), :tool_environment, [tracker], %{})
  def tool_environment(_tracker), do: %{}

  @spec execute_dynamic_tool(String.t() | nil, term(), keyword()) :: tool_result()
  def execute_dynamic_tool(tool, arguments, opts \\ []) do
    {adapter, tracker} = current!()
    do_execute_dynamic_tool(adapter, tracker, tool, arguments, opts)
  end

  @spec execute_dynamic_tool(tracker_config() | map(), String.t() | nil, term(), keyword()) ::
          tool_result()
  def execute_dynamic_tool(%{kind: _} = tracker, tool, arguments, opts) when is_list(opts), do: do_execute_dynamic_tool(adapter(tracker), tracker, tool, arguments, opts)

  # ── Metadata ──────────────────────────────────────────────────────

  @spec project_ref() :: ProjectRef.t()
  def project_ref do
    {adapter, tracker} = current!()
    do_project_ref(adapter, tracker)
  end

  @spec project_ref(tracker_config() | map()) :: ProjectRef.t()
  def project_ref(%{kind: _} = tracker), do: do_project_ref(adapter(tracker), tracker)
  def project_ref(_tracker), do: %ProjectRef{}

  @spec project_id() :: String.t() | nil
  def project_id, do: project_ref() |> Map.get(:id)

  @spec project_id(tracker_config()) :: String.t() | nil
  def project_id(tracker), do: project_ref(tracker) |> Map.get(:id)

  @spec project_url() :: String.t() | nil
  def project_url, do: project_ref() |> Map.get(:url)

  @spec project_url(tracker_config()) :: String.t() | nil
  def project_url(tracker), do: project_ref(tracker) |> Map.get(:url)

  @spec change_proposal_reference(Issue.t() | map()) :: ChangeProposalReference.t() | nil
  def change_proposal_reference(issue), do: ChangeProposalReference.from_issue(issue)

  @spec fetch_change_proposal_reference(Issue.t() | map(), keyword()) ::
          result(ChangeProposalReference.t() | nil)
  def fetch_change_proposal_reference(issue, opts \\ [])

  def fetch_change_proposal_reference(%Issue{} = issue, opts) when is_list(opts) do
    {adapter, tracker} = current!()
    do_fetch_change_proposal_reference(adapter, tracker, issue, opts)
  end

  def fetch_change_proposal_reference(issue, opts) when is_map(issue) and is_list(opts) do
    {adapter, tracker} = current!()
    do_fetch_change_proposal_reference(adapter, tracker, issue, opts)
  end

  @spec fetch_change_proposal_reference(tracker_config() | map(), Issue.t() | map()) ::
          result(ChangeProposalReference.t() | nil)
  def fetch_change_proposal_reference(%{kind: _} = tracker, issue) when is_map(issue) do
    fetch_change_proposal_reference(tracker, issue, [])
  end

  @spec fetch_change_proposal_reference(tracker_config() | map(), Issue.t() | map(), keyword()) ::
          result(ChangeProposalReference.t() | nil)
  def fetch_change_proposal_reference(%{kind: _} = tracker, issue, opts)
      when is_map(issue) and is_list(opts) do
    do_fetch_change_proposal_reference(adapter(tracker), tracker, issue, opts)
  end

  # ── Workspace ─────────────────────────────────────────────────────

  @spec prepare_workspace(Path.t(), String.t() | nil, keyword()) :: :ok | {:error, term()}
  def prepare_workspace(workspace, worker_host, opts \\ []) when is_binary(workspace), do: call_optional(:prepare_workspace, [workspace, Keyword.put_new(opts, :worker_host, worker_host)], :ok)

  @spec prepare_workspace(tracker_config() | map(), Path.t(), String.t() | nil, keyword()) :: :ok | {:error, term()}
  def prepare_workspace(%{kind: _} = tracker, workspace, worker_host, opts) when is_binary(workspace) and is_list(opts),
    do: call_optional(tracker, :prepare_workspace, [workspace, Keyword.put_new(opts, :worker_host, worker_host)], :ok)

  # ── Healthcheck ──────────────────────────────────────────────────

  @spec healthcheck(keyword()) :: :ok | {:error, Error.t() | term()}
  def healthcheck(opts \\ [])
  def healthcheck(opts) when is_list(opts), do: call_optional(:healthcheck, [opts], :ok)

  @spec healthcheck(tracker_config() | map()) :: :ok | {:error, Error.t() | term()}
  def healthcheck(%{kind: _} = tracker), do: healthcheck(tracker, [])
  @spec healthcheck(tracker_config() | map(), keyword()) :: :ok | {:error, Error.t() | term()}
  def healthcheck(%{kind: _} = tracker, opts) when is_list(opts), do: call_optional(tracker, :healthcheck, [opts], :ok)

  # ── Private: Unified Dispatch ────────────────────────────────────

  # Implicit dispatch — reads current config from application state.
  @spec call(atom(), [term()]) :: term()
  defp call(callback, extra_args) when is_atom(callback) and is_list(extra_args) do
    {adapter, tracker} = current!()
    dispatch(adapter, callback, [tracker | extra_args])
  end

  # Explicit dispatch — caller provides the tracker config.
  @spec call(tracker_config() | map(), atom(), [term()]) :: term()
  defp call(%{kind: _} = tracker, callback, extra_args) when is_atom(callback) and is_list(extra_args) do
    dispatch(adapter(tracker), callback, [tracker | extra_args])
  end

  # Implicit optional dispatch uses `default` when callback is not exported.
  @spec call_optional(atom(), [term()], term()) :: term()
  defp call_optional(callback, extra_args, default) when is_atom(callback) and is_list(extra_args) do
    {adapter, tracker} = current!()
    optional(adapter, callback, [tracker | extra_args], default)
  end

  # Explicit optional dispatch.
  @spec call_optional(tracker_config() | map(), atom(), [term()], term()) :: term()
  defp call_optional(%{kind: _} = tracker, callback, extra_args, default) when is_atom(callback) and is_list(extra_args) do
    optional(adapter(tracker), callback, [tracker | extra_args], default)
  end

  # ── Private: Specialised Handlers ────────────────────────────────

  defp do_execute_dynamic_tool(adapter, tracker, tool, arguments, opts) do
    optional(adapter, :execute_dynamic_tool, [tracker, tool, arguments, opts], unsupported_dynamic_tool_error(tracker))
  end

  defp do_project_ref(adapter, tracker) when is_map(tracker) do
    case optional(adapter, :project_ref, [tracker], nil) do
      %ProjectRef{} = ref -> ref
      nil -> %ProjectRef{kind: Config.kind(tracker)}
    end
  end

  defp do_fetch_change_proposal_reference(adapter, tracker, issue, opts)
       when is_map(tracker) and is_map(issue) and is_list(opts) do
    case ChangeProposalReference.from_issue(issue) do
      %ChangeProposalReference{} = reference ->
        {:ok, reference}

      nil ->
        optional(adapter, :fetch_change_proposal_reference, [tracker, issue, opts], {:ok, nil})
    end
  end

  defp candidate_issue_ids(tracker) do
    tracker
    |> Config.provider()
    |> nested_value("candidate_issue_ids")
    |> normalize_string_list()
  end

  defp terminal_issue?(issue, terminal_states) when is_map(issue) and is_list(terminal_states) do
    terminal_states =
      terminal_states
      |> Enum.map(&normalize_state_name/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    issue
    |> issue_state()
    |> normalize_state_name()
    |> then(&MapSet.member?(terminal_states, &1))
  end

  defp terminal_issue?(_issue, _terminal_states), do: false

  defp issue_state(%Issue{state: state}), do: state

  defp issue_state(issue) when is_map(issue) do
    Map.get(issue, :state) || Map.get(issue, "state")
  end

  defp normalize_state_name(value) when is_binary(value) do
    value
    |> WorkflowLifecycle.normalize_tracker_state()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_state_name(value), do: value |> to_string() |> normalize_state_name()

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_string_list(_values), do: []

  defp normalize_optional_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value), do: value |> to_string() |> normalize_optional_string()

  defp nested_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp nested_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp unsupported_dynamic_tool_error(tracker) do
    {:error,
     Error.new(%{
       provider: Config.kind(tracker) || "unknown",
       operation: :execute_dynamic_tool,
       code: :unsupported_dynamic_tool,
       message: "Configured tracker does not expose dynamic tools.",
       details: %{
         supported_tools: dynamic_tools(tracker) |> Enum.flat_map(&tool_name/1)
       }
     })}
  end

  # ── Private: Core Dispatch Primitives ────────────────────────────

  defp optional(module, callback, args, default) when is_atom(module) do
    Code.ensure_loaded(module)
    if function_exported?(module, callback, length(args)), do: dispatch(module, callback, args), else: default
  end

  defp dispatch(module, callback, args) when is_atom(module) do
    metadata = %{adapter: module, callback: callback}

    :telemetry.span(
      [:symphony, :tracker, :dispatch],
      metadata,
      fn ->
        result = apply(module, callback, args)
        {result, Map.put(metadata, :result, result_tag(result))}
      end
    )
  end

  defp result_tag(:ok), do: :ok
  defp result_tag({:ok, _}), do: :ok
  defp result_tag({:success, _}), do: :ok
  defp result_tag({:failure, _}), do: :failure
  defp result_tag({:error, _}), do: :error
  defp result_tag(_), do: :ok

  defp tool_name(%{"name" => name}) when is_binary(name), do: [name]
  defp tool_name(%{name: name}) when is_binary(name), do: [name]
  defp tool_name(_tool), do: []

  defp current! do
    tracker = Config.current!()
    {adapter(tracker), tracker}
  end
end

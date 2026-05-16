defmodule SymphonyElixir.Tracker.Smoke do
  @moduledoc """
  Tracker smoke validation for deployment readiness checks.

  The smoke runner is read-only by default. State writes require an explicit
  opt-in and always pass an `:expected_current_state` precondition to the
  tracker facade.
  """

  alias SymphonyElixir.Config
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.ProjectRef
  alias SymphonyElixir.Workflow
  alias SymphonyElixir.Workflow.Templates

  @type probe_result :: %{
          id: String.t(),
          ok: boolean(),
          duration_ms: non_neg_integer(),
          summary: String.t(),
          error: String.t() | nil
        }

  @type report :: %{
          workflow: String.t() | nil,
          tracker_kind: String.t() | nil,
          project_id: String.t() | nil,
          project_url: String.t() | nil,
          smoke_mode: String.t(),
          ok: boolean(),
          duration_ms: non_neg_integer(),
          probe_count: non_neg_integer(),
          passed_count: non_neg_integer(),
          failed_count: non_neg_integer(),
          probes: [probe_result()]
        }

  @type deps :: %{
          required(:monotonic_time_ms) => (-> integer()),
          required(:workflow_file_path) => (-> Path.t()),
          required(:set_workflow_file_path) => (Path.t() -> :ok),
          required(:workflow_file_env) => (-> {:ok, Path.t()} | :error),
          required(:restore_workflow_file_env) => ({:ok, Path.t()} | :error -> :ok),
          required(:resolve_template) => (String.t() -> {:ok, Path.t()} | {:error, String.t()}),
          required(:file_regular?) => (Path.t() -> boolean()),
          required(:validate_config) => (-> :ok | {:error, term()}),
          required(:settings) => (-> struct()),
          required(:healthcheck) => (map() -> :ok | {:error, term()}),
          required(:fetch_issue_states_by_ids) => (map(), [String.t()] -> {:ok, [term()]} | {:error, term()}),
          required(:update_issue_state) => (map(), String.t(), String.t(), keyword() -> :ok | {:error, term()}),
          required(:project_ref) => (map() -> ProjectRef.t() | nil)
        }

  @spec run(keyword(), deps()) :: report()
  def run(opts, deps \\ runtime_deps()) when is_list(opts) and is_map(deps) do
    started_at_ms = deps.monotonic_time_ms.()
    previous_workflow_env = deps.workflow_file_env.()
    smoke_mode = smoke_mode(opts)

    try do
      case resolve_workflow(opts, deps) do
        {:ok, workflow_path, workflow_label} ->
          :ok = deps.set_workflow_file_path.(workflow_path)

          {probes, settings} = run_config_probe(deps)
          {probes, tracker, project_ref} = append_tracker_context(probes, settings, deps)
          probes = append_healthcheck_probe(probes, tracker, deps)
          {probes, fetched_issue} = append_issue_probe(probes, tracker, opts, deps)
          probes = append_state_write_probe(probes, tracker, fetched_issue, opts, deps)

          build_report(
            workflow_label,
            tracker,
            project_ref,
            smoke_mode,
            probes,
            deps.monotonic_time_ms.() - started_at_ms
          )

        {:error, reason} ->
          probes = [failed_probe("workflow", reason)]

          build_report(
            nil,
            nil,
            nil,
            smoke_mode,
            probes,
            deps.monotonic_time_ms.() - started_at_ms
          )
      end
    after
      deps.restore_workflow_file_env.(previous_workflow_env)
    end
  end

  @spec format_text(report()) :: String.t()
  def format_text(report) when is_map(report) do
    status = if report.ok, do: "passed", else: "failed"

    header =
      "tracker smoke #{status} tracker=#{report.tracker_kind || "unknown"} mode=#{report.smoke_mode} " <>
        "probes=#{report.probe_count} passed=#{report.passed_count} failed=#{report.failed_count}"

    probe_lines =
      Enum.map(report.probes, fn probe ->
        status = if probe.ok, do: "ok", else: "fail"
        detail = if probe.error, do: "#{probe.summary}: #{probe.error}", else: probe.summary
        "- [#{status}] #{probe.id} #{detail} (#{probe.duration_ms}ms)"
      end)

    Enum.join([header | probe_lines], "\n") <> "\n"
  end

  @spec to_map(report()) :: map()
  def to_map(report) when is_map(report), do: report

  @spec runtime_deps() :: deps()
  def runtime_deps do
    %{
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      workflow_file_path: &Workflow.workflow_file_path/0,
      set_workflow_file_path: &Workflow.set_workflow_file_path/1,
      workflow_file_env: fn -> Application.fetch_env(:symphony_elixir, :workflow_file_path) end,
      restore_workflow_file_env: &restore_workflow_file_env/1,
      resolve_template: &Templates.resolve/1,
      file_regular?: &File.regular?/1,
      validate_config: &Config.validate!/0,
      settings: &Config.settings!/0,
      healthcheck: fn tracker -> Tracker.healthcheck(tracker) end,
      fetch_issue_states_by_ids: fn tracker, issue_ids -> Tracker.fetch_issue_states_by_ids(tracker, issue_ids) end,
      update_issue_state: fn tracker, issue_id, state_name, opts ->
        Tracker.update_issue_state(tracker, issue_id, state_name, opts)
      end,
      project_ref: fn tracker -> Tracker.project_ref(tracker) end
    }
  end

  defp resolve_workflow(opts, deps) do
    template = opts |> Keyword.get(:template) |> normalize_optional_string()
    workflow_path = opts |> Keyword.get(:workflow_path) |> normalize_optional_string()

    cond do
      is_binary(template) ->
        with {:ok, path} <- deps.resolve_template.(template) do
          {:ok, path, "template:#{template}"}
        end

      is_binary(workflow_path) ->
        expanded = Path.expand(workflow_path)

        if deps.file_regular?.(expanded) do
          {:ok, expanded, expanded}
        else
          {:error, "Workflow file not found: #{expanded}"}
        end

      true ->
        path = deps.workflow_file_path.()

        if deps.file_regular?.(path) do
          {:ok, path, path}
        else
          {:error, "Workflow file not found: #{path}"}
        end
    end
  end

  defp run_config_probe(deps) do
    {probe, result} =
      run_probe("config-validation", deps, fn ->
        with :ok <- deps.validate_config.() do
          settings = deps.settings.()
          {:ok, "workflow config valid", settings}
        end
      end)

    {[probe], ok_value(result)}
  end

  defp append_tracker_context(probes, nil, _deps), do: {probes, nil, nil}

  defp append_tracker_context(probes, settings, deps) do
    tracker = Map.get(settings, :tracker)
    project_ref = if is_map(tracker), do: deps.project_ref.(tracker), else: nil
    {probes, tracker, project_ref}
  end

  defp append_healthcheck_probe(probes, nil, _deps), do: probes

  defp append_healthcheck_probe(probes, tracker, deps) do
    {probe, _result} =
      run_probe("healthcheck", deps, fn ->
        case deps.healthcheck.(tracker) do
          :ok -> {:ok, "tracker healthcheck passed", :ok}
          {:error, reason} -> {:error, reason}
        end
      end)

    probes ++ [probe]
  end

  defp append_issue_probe(probes, nil, _opts, _deps), do: {probes, nil}

  defp append_issue_probe(probes, tracker, opts, deps) do
    case opts |> Keyword.get(:issue_id) |> normalize_optional_string() do
      nil ->
        {probes, nil}

      issue_id ->
        {probe, result} =
          run_probe("fetch-issue", deps, fn ->
            with {:ok, issues} <- deps.fetch_issue_states_by_ids.(tracker, [issue_id]),
                 {:ok, issue} <- single_issue(issues, issue_id) do
              {:ok, "issue #{issue_id} current_state=#{issue_state(issue) || "unknown"}", issue}
            end
          end)

        {probes ++ [probe], ok_value(result)}
    end
  end

  defp append_state_write_probe(probes, nil, _fetched_issue, opts, _deps) do
    if Keyword.get(opts, :confirm_state_write, false),
      do: probes ++ [failed_probe("state-write", "tracker config unavailable")],
      else: probes
  end

  defp append_state_write_probe(probes, tracker, fetched_issue, opts, deps) do
    if Keyword.get(opts, :confirm_state_write, false) do
      issue_id = opts |> Keyword.get(:issue_id) |> normalize_optional_string()

      {probe, _result} =
        run_probe("state-write", deps, fn ->
          with {:ok, issue_id} <- present_value(issue_id, "issue id is required"),
               {:ok, current_state} <- current_state_for_write(fetched_issue),
               expected = expected_current_state(opts, current_state),
               {:ok, expected} <- present_value(expected, "expected current state is required"),
               target = target_state(opts, expected),
               {:ok, target} <- present_value(target, "target state is required"),
               :ok <- deps.update_issue_state.(tracker, issue_id, target, expected_current_state: expected) do
            {:ok, "state write accepted target=#{target} expected_current_state=#{expected}", :ok}
          end
        end)

      probes ++ [probe]
    else
      probes
    end
  end

  defp current_state_for_write(%Issue{} = issue), do: present_value(issue_state(issue), "fetched issue state is required")
  defp current_state_for_write(issue) when is_map(issue), do: present_value(issue_state(issue), "fetched issue state is required")
  defp current_state_for_write(_issue), do: {:error, "issue fetch must pass before state write"}

  defp expected_current_state(opts, current_state) do
    case opts |> Keyword.get(:expected_current_state) |> normalize_optional_string() do
      nil -> current_state
      expected -> expected
    end
  end

  defp target_state(opts, expected_current_state) do
    case opts |> Keyword.get(:write_state) |> normalize_optional_string() do
      nil -> expected_current_state
      target -> target
    end
  end

  defp single_issue([%Issue{} = issue], _issue_id), do: {:ok, issue}
  defp single_issue([issue], _issue_id) when is_map(issue), do: {:ok, issue}
  defp single_issue([], issue_id), do: {:error, "issue not found: #{issue_id}"}
  defp single_issue(issues, issue_id) when is_list(issues), do: {:error, "expected one issue for #{issue_id}, got #{length(issues)}"}
  defp single_issue(_issues, issue_id), do: {:error, "unexpected issue lookup payload for #{issue_id}"}

  defp issue_state(%Issue{state: state}), do: normalize_optional_string(state)
  defp issue_state(issue) when is_map(issue), do: issue |> map_value(:state) |> normalize_optional_string()

  defp present_value(value, _message) when is_binary(value), do: {:ok, value}
  defp present_value(_value, message), do: {:error, message}

  defp smoke_mode(opts) do
    if Keyword.get(opts, :confirm_state_write, false), do: "state_write", else: "read_only"
  end

  defp run_probe(id, deps, fun) when is_binary(id) and is_function(fun, 0) do
    started_at_ms = deps.monotonic_time_ms.()

    try do
      case fun.() do
        {:ok, summary, value} ->
          {%{id: id, ok: true, duration_ms: deps.monotonic_time_ms.() - started_at_ms, summary: summary, error: nil}, {:ok, value}}

        {:error, reason} ->
          {%{
             id: id,
             ok: false,
             duration_ms: deps.monotonic_time_ms.() - started_at_ms,
             summary: "failed",
             error: format_reason(reason)
           }, {:error, reason}}
      end
    rescue
      exception ->
        {%{
           id: id,
           ok: false,
           duration_ms: deps.monotonic_time_ms.() - started_at_ms,
           summary: "failed",
           error: Exception.message(exception)
         }, {:error, exception}}
    end
  end

  defp failed_probe(id, reason) do
    %{id: id, ok: false, duration_ms: 0, summary: "failed", error: format_reason(reason)}
  end

  defp ok_value({:ok, value}), do: value
  defp ok_value(_result), do: nil

  defp build_report(workflow_label, tracker, project_ref, smoke_mode, probes, duration_ms) do
    passed_count = Enum.count(probes, & &1.ok)
    failed_count = length(probes) - passed_count

    %{
      workflow: workflow_label,
      tracker_kind: tracker_kind(tracker, project_ref),
      project_id: project_ref_value(project_ref, :id),
      project_url: project_ref_value(project_ref, :url),
      smoke_mode: smoke_mode,
      ok: failed_count == 0,
      duration_ms: max(duration_ms, 0),
      probe_count: length(probes),
      passed_count: passed_count,
      failed_count: failed_count,
      probes: probes
    }
  end

  defp tracker_kind(_tracker, %ProjectRef{kind: kind}) when is_binary(kind), do: kind
  defp tracker_kind(tracker, _project_ref) when is_map(tracker), do: map_value(tracker, :kind) |> normalize_optional_string()
  defp tracker_kind(_tracker, _project_ref), do: nil

  defp project_ref_value(%ProjectRef{} = ref, key) when key in [:id, :url] do
    ref
    |> Map.get(key)
    |> normalize_optional_string()
  end

  defp project_ref_value(_ref, _key), do: nil

  defp restore_workflow_file_env({:ok, path}) when is_binary(path), do: Workflow.set_workflow_file_path(path)
  defp restore_workflow_file_env(:error), do: Workflow.clear_workflow_file_path()

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_map, _key), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(value) when is_integer(value), do: value |> Integer.to_string() |> normalize_optional_string()
  defp normalize_optional_string(_value), do: nil

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end

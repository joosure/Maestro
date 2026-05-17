defmodule SymphonyElixir.AgentProvider.Smoke do
  @moduledoc """
  Agent-provider smoke validation for deployment readiness checks.

  The smoke runner validates the selected workflow config, creates a temporary
  empty workspace, starts the configured agent provider, optionally runs one
  minimal turn, stops the provider session, and removes the temporary workspace.
  It does not run the workflow prompt and does not read or write tracker or repo
  providers.
  """

  alias SymphonyElixir.Agent.DynamicTool.Context, as: DynamicToolContext
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.AgentProvider.{Config, Error, Session, TurnResult}
  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Smoke.ResultStatus
  alias SymphonyElixir.Workflow
  alias SymphonyElixir.Workflow.CapabilityNames
  alias SymphonyElixir.Workflow.Templates

  @turn_capability CapabilityNames.agent_turn_run()
  @default_prompt """
  This is a Symphony agent-provider smoke check in a temporary empty workspace.
  Reply with one short sentence confirming the provider turn completed.
  Do not inspect files, run commands, modify files, call external services, or reveal secrets.
  """

  @type probe_result :: %{
          id: String.t(),
          ok: boolean(),
          duration_ms: non_neg_integer(),
          summary: String.t(),
          error: String.t() | nil
        }

  @type report :: %{
          workflow: String.t() | nil,
          agent_provider_kind: String.t() | nil,
          smoke_mode: String.t(),
          prompt_transport: String.t() | nil,
          command: String.t() | [String.t()] | nil,
          workspace: String.t(),
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
          required(:settings) => (-> {:ok, struct()} | {:error, term()}),
          required(:provider_capabilities) => (Config.t() -> [String.t()]),
          required(:mk_temp_dir) => (String.t() -> {:ok, Path.t()} | {:error, term()}),
          required(:prepare_workspace) => (Path.t(), keyword() -> :ok | {:error, term()}),
          required(:start_session) => (Path.t(), keyword() -> {:ok, Session.t()} | {:error, term()}),
          required(:run_turn) => (Session.t(), String.t(), map(), keyword() -> {:ok, TurnResult.t()} | {:error, term()}),
          required(:stop_session) => (Session.t(), keyword() -> :ok | {:error, term()}),
          required(:rm_rf) => (Path.t() -> :ok | {:ok, [Path.t()]} | {:error, term()} | {:error, term(), Path.t()})
        }

  @spec run(keyword(), deps()) :: report()
  def run(opts, deps \\ runtime_deps()) when is_list(opts) and is_map(deps) do
    opts = Keyword.put_new(opts, :run_id, generated_run_id())
    started_at_ms = deps.monotonic_time_ms.()
    previous_workflow_env = deps.workflow_file_env.()
    smoke_mode = smoke_mode(opts)

    try do
      case resolve_workflow(opts, deps) do
        {:ok, workflow_path, workflow_label} ->
          :ok = deps.set_workflow_file_path.(workflow_path)

          {probes, settings} = run_config_probe(deps)
          provider_config = provider_config(settings)
          probes = append_capability_probe(probes, provider_config, deps)
          {probes, workspace} = append_workspace_probe(probes, deps)
          probes = append_prepare_probe(probes, provider_config, workspace, opts, deps)
          {probes, session} = append_start_probe(probes, provider_config, workspace, opts, deps)
          {probes, turn_result} = append_turn_probe(probes, session, opts, deps)
          probes = append_stop_probe(probes, session, turn_result, opts, deps)
          probes = append_cleanup_probe(probes, workspace, deps)

          build_report(
            workflow_label,
            provider_config,
            smoke_mode,
            probes,
            deps.monotonic_time_ms.() - started_at_ms
          )

        {:error, reason} ->
          probes = [failed_probe("workflow", reason)]
          build_report(nil, nil, smoke_mode, probes, deps.monotonic_time_ms.() - started_at_ms)
      end
    after
      deps.restore_workflow_file_env.(previous_workflow_env)
    end
  end

  @spec format_text(report()) :: String.t()
  def format_text(report) when is_map(report) do
    status = ResultStatus.report_status(report.ok)

    header =
      "agent-provider smoke #{status} provider=#{report.agent_provider_kind || ResultStatus.unknown()} " <>
        "mode=#{report.smoke_mode} probes=#{report.probe_count} passed=#{report.passed_count} failed=#{report.failed_count}"

    probe_lines =
      Enum.map(report.probes, fn probe ->
        status = ResultStatus.line_status(probe.ok)
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
      validate_config: &SymphonyElixir.Config.validate!/0,
      settings: &SymphonyElixir.Config.settings/0,
      provider_capabilities: fn config -> AgentProvider.capabilities(agent_provider_config: config) end,
      mk_temp_dir: &mk_temp_dir/1,
      prepare_workspace: fn workspace, start_opts -> AgentProvider.prepare_workspace(workspace, start_opts) end,
      start_session: fn workspace, start_opts -> AgentProvider.start_session(workspace, start_opts) end,
      run_turn: fn session, prompt, issue, turn_opts -> AgentProvider.run_turn(session, prompt, issue, turn_opts) end,
      stop_session: fn session, stop_opts -> AgentProvider.stop_session(session, stop_opts) end,
      rm_rf: &File.rm_rf/1
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
        with :ok <- deps.validate_config.(),
             {:ok, settings} <- deps.settings.() do
          {:ok, "workflow config valid", settings}
        end
      end)

    {[probe], ok_value(result)}
  end

  defp provider_config(nil), do: nil

  defp provider_config(settings) do
    settings
    |> map_value(:agent_provider)
    |> Config.new()
  end

  defp append_capability_probe(probes, nil, _deps), do: probes

  defp append_capability_probe(probes, provider_config, deps) do
    if probes_ok?(probes) do
      {probe, _result} =
        run_probe("capability", deps, fn ->
          capabilities = deps.provider_capabilities.(provider_config)

          if @turn_capability in capabilities do
            {:ok, "provider supports #{@turn_capability}", capabilities}
          else
            {:error, "provider #{provider_config.kind} does not support #{@turn_capability}"}
          end
        end)

      probes ++ [probe]
    else
      probes
    end
  end

  defp append_workspace_probe(probes, deps) do
    if probes_ok?(probes) do
      {probe, result} =
        run_probe("workspace", deps, fn ->
          case deps.mk_temp_dir.("agent-provider-smoke") do
            {:ok, workspace} -> {:ok, "temporary workspace created", workspace}
            {:error, reason} -> {:error, reason}
          end
        end)

      {probes ++ [probe], ok_value(result)}
    else
      {probes, nil}
    end
  end

  defp append_prepare_probe(probes, nil, _workspace, _opts, _deps), do: probes
  defp append_prepare_probe(probes, _provider_config, nil, _opts, _deps), do: probes

  defp append_prepare_probe(probes, provider_config, workspace, opts, deps) do
    if probes_ok?(probes) do
      {probe, _result} =
        run_probe("prepare-workspace", deps, fn ->
          start_opts = provider_start_opts(provider_config, opts)

          case deps.prepare_workspace.(workspace, start_opts) do
            :ok -> {:ok, "workspace tooling prepared", :ok}
            {:error, reason} -> {:error, reason}
          end
        end)

      probes ++ [probe]
    else
      probes
    end
  end

  defp append_start_probe(probes, nil, _workspace, _opts, _deps), do: {probes, nil}
  defp append_start_probe(probes, _provider_config, nil, _opts, _deps), do: {probes, nil}

  defp append_start_probe(probes, provider_config, workspace, opts, deps) do
    if probes_ok?(probes) do
      {probe, result} =
        run_probe("start-session", deps, fn ->
          case deps.start_session.(workspace, provider_start_opts(provider_config, opts)) do
            {:ok, %Session{} = session} ->
              {:ok, "session started session_id_present=#{present?(session.session_id)} thread_id_present=#{present?(session.thread_id)}", session}

            {:ok, session} ->
              {:ok, "session started", session}

            {:error, reason} ->
              {:error, reason}
          end
        end)

      {probes ++ [probe], ok_value(result)}
    else
      {probes, nil}
    end
  end

  defp append_turn_probe(probes, nil, _opts, _deps), do: {probes, nil}

  defp append_turn_probe(probes, session, opts, deps) do
    cond do
      not probes_ok?(probes) ->
        {probes, nil}

      not Keyword.get(opts, :run_turn, true) ->
        {probes, nil}

      true ->
        issue = smoke_issue(opts)

        {probe, result} =
          run_probe("run-turn", deps, fn ->
            case deps.run_turn.(session, prompt(opts), issue, turn_opts(opts)) do
              {:ok, %TurnResult{status: :completed} = result} ->
                {:ok, "turn completed status=completed turn_id_present=#{present?(result.turn_id)}", result}

              {:ok, %TurnResult{} = result} ->
                {:error, {:agent_turn_terminal_status, result.status}}

              {:ok, result} ->
                {:ok, "turn completed", result}

              {:error, reason} ->
                {:error, reason}
            end
          end)

        {probes ++ [probe], ok_value(result)}
    end
  end

  defp append_stop_probe(probes, nil, _turn_result, _opts, _deps), do: probes

  defp append_stop_probe(probes, session, turn_result, opts, deps) do
    status = stop_status(turn_result, opts)

    {probe, _result} =
      run_probe("stop-session", deps, fn ->
        case deps.stop_session.(session, status: status, issue: smoke_issue(opts)) do
          :ok -> {:ok, "session stopped status=#{status}", :ok}
          {:error, reason} -> {:error, reason}
        end
      end)

    probes ++ [probe]
  end

  defp append_cleanup_probe(probes, nil, _deps), do: probes

  defp append_cleanup_probe(probes, workspace, deps) do
    {probe, _result} =
      run_probe("cleanup", deps, fn ->
        case deps.rm_rf.(workspace) do
          :ok -> {:ok, "temporary workspace removed", :ok}
          {:ok, _paths} -> {:ok, "temporary workspace removed", :ok}
          {:error, reason, path} -> {:error, {:remove_failed, path, reason}}
          {:error, reason} -> {:error, reason}
        end
      end)

    probes ++ [probe]
  end

  defp provider_start_opts(%Config{} = provider_config, opts) do
    [
      agent_provider_config: provider_config,
      dynamic_tool_workflow_planner: fn _opts -> {:ok, empty_tool_context()} end,
      issue: smoke_issue(opts),
      issue_id: opts |> Keyword.get(:issue_id) |> normalize_optional_string(),
      issue_identifier: smoke_issue_identifier(opts),
      run_id: run_id(opts),
      on_message: fn _message -> :ok end
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp turn_opts(opts) do
    [
      on_message: fn _message -> :ok end,
      issue: smoke_issue(opts),
      issue_id: opts |> Keyword.get(:issue_id) |> normalize_optional_string(),
      issue_identifier: smoke_issue_identifier(opts),
      run_id: run_id(opts)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp empty_tool_context do
    DynamicToolContext.empty()
    |> Map.put(:tool_plan, %{
      exposure: "agent_provider_smoke",
      required_capabilities: [],
      tool_names: [],
      resolved_tools: [],
      reason: "agent_provider_smoke_does_not_exercise_workflow_tools"
    })
  end

  defp smoke_issue(opts) do
    %{
      id: opts |> Keyword.get(:issue_id) |> normalize_optional_string(),
      identifier: smoke_issue_identifier(opts),
      title: "Agent provider smoke",
      state: "smoke"
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp smoke_issue_identifier(opts) do
    opts
    |> Keyword.get(:issue_identifier)
    |> normalize_optional_string()
    |> case do
      nil -> "AGENT-PROVIDER-SMOKE"
      value -> value
    end
  end

  defp prompt(opts) do
    opts
    |> Keyword.get(:prompt)
    |> normalize_optional_string()
    |> case do
      nil -> String.trim(@default_prompt)
      value -> value
    end
  end

  defp run_id(opts) do
    opts
    |> Keyword.get(:run_id)
    |> normalize_optional_string()
    |> case do
      nil -> generated_run_id()
      value -> value
    end
  end

  defp generated_run_id, do: "agent-provider-smoke-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))

  defp stop_status(%TurnResult{status: :completed}, _opts), do: :completed
  defp stop_status(_turn_result, opts), do: if(Keyword.get(opts, :run_turn, true), do: :failed, else: :completed)

  defp smoke_mode(opts), do: if(Keyword.get(opts, :run_turn, true), do: "first_turn", else: "start_only")

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
             summary: ResultStatus.failed(),
             error: format_reason(reason)
           }, {:error, reason}}
      end
    rescue
      exception ->
        {%{
           id: id,
           ok: false,
           duration_ms: deps.monotonic_time_ms.() - started_at_ms,
           summary: ResultStatus.failed(),
           error: exception |> Exception.message() |> Redaction.redact_string()
         }, {:error, exception}}
    end
  end

  defp failed_probe(id, reason) do
    %{id: id, ok: false, duration_ms: 0, summary: ResultStatus.failed(), error: format_reason(reason)}
  end

  defp ok_value({:ok, value}), do: value
  defp ok_value(_result), do: nil

  defp probes_ok?(probes), do: Enum.all?(probes, & &1.ok)

  defp build_report(workflow_label, provider_config, smoke_mode, probes, duration_ms) do
    passed_count = Enum.count(probes, & &1.ok)
    failed_count = length(probes) - passed_count

    %{
      workflow: workflow_label,
      agent_provider_kind: provider_kind(provider_config),
      smoke_mode: smoke_mode,
      prompt_transport: provider_option(provider_config, "prompt_transport"),
      command: command_summary(provider_config),
      workspace: "temporary",
      ok: failed_count == 0,
      duration_ms: max(duration_ms, 0),
      probe_count: length(probes),
      passed_count: passed_count,
      failed_count: failed_count,
      probes: probes
    }
  end

  defp provider_kind(%Config{kind: kind}) when is_binary(kind), do: kind
  defp provider_kind(_config), do: nil

  defp provider_option(%Config{options: options}, key) when is_map(options), do: options |> Map.get(key) |> normalize_optional_string()
  defp provider_option(_config, _key), do: nil

  defp command_summary(%Config{options: options}) when is_map(options) do
    cond do
      is_list(Map.get(options, "command_argv")) ->
        options
        |> Map.get("command_argv", [])
        |> Enum.map(&redact_command_part/1)

      is_binary(Map.get(options, "command")) ->
        options
        |> Map.get("command")
        |> Redaction.redact_string()

      true ->
        nil
    end
  end

  defp command_summary(_config), do: nil

  defp redact_command_part(value) when is_binary(value), do: Redaction.redact_string(value)
  defp redact_command_part(value), do: value |> inspect() |> Redaction.redact_string()

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp mk_temp_dir(prefix) when is_binary(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive, :monotonic])}")

    case File.mkdir_p(path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_workflow_file_env({:ok, path}) when is_binary(path), do: Workflow.set_workflow_file_path(path)
  defp restore_workflow_file_env(:error), do: Workflow.clear_workflow_file_path()

  defp map_value(nil, _key), do: nil

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_value, _key), do: nil

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

  defp format_reason(%Error{} = error) do
    [error.code, error.message, error.details]
    |> Enum.reject(&is_nil/1)
    |> Redaction.summarize(512)
  end

  defp format_reason(reason) when is_binary(reason), do: Redaction.redact_string(reason)
  defp format_reason(reason), do: Redaction.summarize(reason, 512)
end

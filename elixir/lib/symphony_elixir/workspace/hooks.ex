defmodule SymphonyElixir.Workspace.Hooks do
  @moduledoc false

  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Workspace.AutomationPack
  alias SymphonyElixir.Workspace.Paths

  @type worker_host :: String.t() | nil
  @type issue_context :: map()
  @type hooks_config :: map()
  @type event_fields_builder :: (issue_context(), Path.t(), worker_host(), map() -> map())
  @type remote_runner :: (String.t() -> {:ok, {term(), integer()}} | {:error, term()})

  @spec run_before_run(Path.t(), issue_context(), hooks_config(), worker_host(), keyword()) ::
          :ok | {:error, term()}
  def run_before_run(workspace, issue_context, hooks, worker_host, opts \\ [])
      when is_binary(workspace) and is_map(issue_context) and is_map(hooks) do
    run_configured_hook(
      Map.get(hooks, :before_run),
      workspace,
      issue_context,
      "before_run",
      worker_host,
      hooks,
      opts
    )
  end

  @spec run_after_run(Path.t(), issue_context(), hooks_config(), worker_host(), keyword()) :: :ok
  def run_after_run(workspace, issue_context, hooks, worker_host, opts \\ [])
      when is_binary(workspace) and is_map(issue_context) and is_map(hooks) do
    run_configured_hook(
      Map.get(hooks, :after_run),
      workspace,
      issue_context,
      "after_run",
      worker_host,
      hooks,
      opts
    )
    |> ignore_failure()
  end

  @spec maybe_run_after_create(
          Path.t(),
          issue_context(),
          boolean(),
          hooks_config(),
          worker_host(),
          keyword()
        ) :: :ok | {:error, term()}
  def maybe_run_after_create(workspace, issue_context, created?, hooks, worker_host, opts \\ [])
      when is_binary(workspace) and is_map(issue_context) and is_boolean(created?) and is_map(hooks) do
    if created? do
      run_configured_hook(
        Map.get(hooks, :after_create),
        workspace,
        issue_context,
        "after_create",
        worker_host,
        hooks,
        opts
      )
    else
      :ok
    end
  end

  @spec maybe_run_before_remove(Path.t(), hooks_config(), worker_host(), keyword()) :: :ok
  def maybe_run_before_remove(workspace, hooks, worker_host, opts \\ [])
      when is_binary(workspace) and is_map(hooks) do
    issue_context = %{issue_id: nil, issue_identifier: Path.basename(workspace)}

    case worker_host do
      nil ->
        maybe_run_local_before_remove(workspace, issue_context, Map.get(hooks, :before_remove), hooks, opts)

      worker_host when is_binary(worker_host) ->
        maybe_run_remote_before_remove(
          workspace,
          issue_context,
          Map.get(hooks, :before_remove),
          worker_host,
          hooks,
          opts
        )
    end
  end

  defp maybe_run_local_before_remove(workspace, issue_context, command, hooks, opts) do
    if File.dir?(workspace) do
      run_configured_hook(command, workspace, issue_context, "before_remove", nil, hooks, opts)
      |> ignore_failure()
    else
      :ok
    end
  end

  defp maybe_run_remote_before_remove(_workspace, _issue_context, nil, _worker_host, _hooks, _opts),
    do: :ok

  defp maybe_run_remote_before_remove(workspace, issue_context, command, worker_host, hooks, opts) do
    script =
      [
        Paths.remote_shell_assign("workspace", workspace),
        workspace_automation_remote_assign(workspace),
        "if [ -d \"$workspace\" ]; then",
        "  cd \"$workspace\"",
        "  #{command}",
        "fi"
      ]
      |> Enum.join("\n")

    run_remote_hook(script, workspace, issue_context, "before_remove", worker_host, hooks, opts)
    |> ignore_failure()
  end

  defp run_configured_hook(nil, _workspace, _issue_context, _hook_name, _worker_host, _hooks, _opts),
    do: :ok

  defp run_configured_hook(command, workspace, issue_context, hook_name, nil, hooks, opts) do
    run_local_hook(command, workspace, issue_context, hook_name, hooks, opts)
  end

  defp run_configured_hook(command, workspace, issue_context, hook_name, worker_host, hooks, opts)
       when is_binary(worker_host) do
    script =
      [
        workspace_automation_remote_assign(workspace),
        "cd #{Paths.shell_escape(workspace)}",
        command
      ]
      |> Enum.join(" && ")

    run_remote_hook(script, workspace, issue_context, hook_name, worker_host, hooks, opts)
  end

  defp run_local_hook(command, workspace, issue_context, hook_name, hooks, opts) do
    timeout_ms = hook_timeout_ms(hooks)

    emit_hook_event(
      :info,
      :workspace_hook_started,
      issue_context,
      workspace,
      nil,
      %{hook_name: hook_name},
      opts
    )

    task =
      Task.async(fn ->
        System.cmd("sh", ["-lc", command],
          cd: workspace,
          env: workspace_automation_env(workspace),
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, timeout_ms) do
      {:ok, cmd_result} ->
        handle_hook_command_result(cmd_result, workspace, issue_context, hook_name, nil, opts)

      nil ->
        Task.shutdown(task, :brutal_kill)

        emit_hook_event(
          :error,
          :workspace_hook_failed,
          issue_context,
          workspace,
          nil,
          %{hook_name: hook_name, error: "timeout=#{timeout_ms}"},
          opts
        )

        {:error, {:workspace_hook_timeout, hook_name, timeout_ms}}
    end
  end

  defp run_remote_hook(script, workspace, issue_context, hook_name, worker_host, hooks, opts)
       when is_binary(worker_host) do
    _timeout_ms = hook_timeout_ms(hooks)

    emit_hook_event(
      :info,
      :workspace_hook_started,
      issue_context,
      workspace,
      worker_host,
      %{hook_name: hook_name},
      opts
    )

    case remote_runner(opts).(script) do
      {:ok, cmd_result} ->
        handle_hook_command_result(cmd_result, workspace, issue_context, hook_name, worker_host, opts)

      {:error, reason} ->
        emit_hook_event(
          :error,
          :workspace_hook_failed,
          issue_context,
          workspace,
          worker_host,
          %{hook_name: hook_name, error: inspect(reason)},
          opts
        )

        {:error, reason}
    end
  end

  defp handle_hook_command_result({_output, 0}, workspace, issue_context, hook_name, worker_host, opts) do
    emit_hook_event(
      :info,
      :workspace_hook_succeeded,
      issue_context,
      workspace,
      worker_host,
      %{hook_name: hook_name},
      opts
    )

    :ok
  end

  defp handle_hook_command_result({output, status}, workspace, issue_context, hook_name, worker_host, opts) do
    emit_hook_event(
      :error,
      :workspace_hook_failed,
      issue_context,
      workspace,
      worker_host,
      %{
        hook_name: hook_name,
        error: "status=#{status}",
        payload_summary: sanitize_output_for_log(output)
      },
      opts
    )

    {:error, {:workspace_hook_failed, hook_name, status, output}}
  end

  @spec sanitize_output_for_log(term(), pos_integer()) :: String.t()
  def sanitize_output_for_log(output, max_bytes \\ 2_048) do
    binary_output =
      output
      |> IO.iodata_to_binary()
      |> Redaction.redact_string()

    if byte_size(binary_output) <= max_bytes do
      binary_output
    else
      binary_part(binary_output, 0, max_bytes) <> "... (truncated)"
    end
  end

  defp emit_hook_event(level, event, issue_context, workspace, worker_host, extra_fields, opts) do
    ObsLogger.emit(
      level,
      event,
      event_fields_builder(opts).(issue_context, workspace, worker_host, extra_fields)
    )
  end

  defp hook_timeout_ms(%{timeout_ms: timeout_ms}) when is_integer(timeout_ms) and timeout_ms > 0,
    do: timeout_ms

  defp hook_timeout_ms(_hooks), do: 30_000

  defp workspace_automation_env(workspace) when is_binary(workspace) do
    AutomationPack.runtime_env(workspace, AgentProvider.workspace_automation_destination_dir())
  end

  defp workspace_automation_remote_assign(workspace) when is_binary(workspace) do
    AutomationPack.remote_shell_assign(workspace, AgentProvider.workspace_automation_destination_dir())
  end

  defp event_fields_builder(opts) do
    case Keyword.get(opts, :event_fields) do
      fun when is_function(fun, 4) ->
        fun

      _other ->
        &default_event_fields/4
    end
  end

  defp remote_runner(opts) do
    case Keyword.get(opts, :remote_runner) do
      fun when is_function(fun, 1) ->
        fun

      _other ->
        fn _script -> {:error, :missing_remote_runner} end
    end
  end

  defp default_event_fields(issue_context, workspace, worker_host, extra_fields) do
    %{
      issue_id: issue_context[:issue_id],
      issue_identifier: issue_context[:issue_identifier],
      run_id: issue_context[:run_id],
      correlation_id: issue_context[:run_id],
      workspace_path: workspace,
      worker_host: worker_host
    }
    |> Map.merge(extra_fields)
  end

  defp ignore_failure(:ok), do: :ok
  defp ignore_failure({:error, _reason}), do: :ok
end

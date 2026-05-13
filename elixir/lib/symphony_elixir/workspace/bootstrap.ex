defmodule SymphonyElixir.Workspace.Bootstrap do
  @moduledoc false

  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.PathSafety
  alias SymphonyElixir.Platform.SSH
  alias SymphonyElixir.Workspace.AutomationPack
  alias SymphonyElixir.Workspace.Paths

  @type worker_host :: String.t() | nil
  @type issue_context :: map()
  @type event_fields_builder :: (issue_context(), Path.t(), worker_host(), map() -> map())
  @type remote_runner :: (String.t() -> {:ok, {term(), integer()}} | {:error, term()})

  @spec maybe_bootstrap_automation_pack(
          Path.t(),
          issue_context(),
          boolean(),
          String.t() | nil,
          worker_host(),
          keyword()
        ) :: :ok | {:error, term()}
  def maybe_bootstrap_automation_pack(workspace, issue_context, created?, override_dir, worker_host, opts \\ [])

  def maybe_bootstrap_automation_pack(_workspace, _issue_context, false, _override_dir, _worker_host, _opts), do: :ok

  def maybe_bootstrap_automation_pack(workspace, issue_context, true, override_dir, worker_host, opts)
      when is_binary(workspace) and is_map(issue_context) do
    emit_bootstrap_event(
      :info,
      :workspace_automation_bootstrap_started,
      issue_context,
      workspace,
      worker_host,
      %{},
      opts
    )

    destination_dirname = AgentProvider.workspace_automation_destination_dir()

    case AutomationPack.source_dir(override_dir) do
      {:ok, source_kind, source_dir} ->
        bootstrap_automation_source(
          source_kind,
          source_dir,
          destination_dirname,
          workspace,
          issue_context,
          worker_host,
          opts
        )

      {:error, reason} = error ->
        emit_bootstrap_failure(reason, error, issue_context, workspace, worker_host, opts)
    end
  end

  defp bootstrap_automation_source(
         source_kind,
         source_dir,
         destination_dirname,
         workspace,
         issue_context,
         worker_host,
         opts
       ) do
    with {:ok, validated_source_dir} <- validate_bootstrap_automation_source(source_dir),
         :ok <-
           copy_bootstrap_automation_pack(
             validated_source_dir,
             destination_dirname,
             workspace,
             worker_host,
             opts
           ) do
      emit_bootstrap_event(
        :info,
        :workspace_automation_bootstrap_succeeded,
        issue_context,
        workspace,
        worker_host,
        %{result_summary: "#{source_kind}:#{validated_source_dir}"},
        opts
      )

      :ok
    else
      {:error, reason} = error ->
        emit_bootstrap_failure(reason, error, issue_context, workspace, worker_host, opts)
    end
  end

  defp emit_bootstrap_failure(reason, error, issue_context, workspace, worker_host, opts) do
    emit_bootstrap_event(
      :error,
      :workspace_automation_bootstrap_failed,
      issue_context,
      workspace,
      worker_host,
      %{
        error: inspect(reason),
        result_summary: automation_bootstrap_failure_summary(reason)
      },
      opts
    )

    error
  end

  defp validate_bootstrap_automation_source(source_dir) when is_binary(source_dir) do
    case PathSafety.canonicalize(source_dir) do
      {:ok, canonical_source_dir} ->
        cond do
          not File.exists?(canonical_source_dir) ->
            {:error, {:workspace_bootstrap_automation_invalid_source, canonical_source_dir, :missing}}

          not File.dir?(canonical_source_dir) ->
            {:error, {:workspace_bootstrap_automation_invalid_source, canonical_source_dir, :not_directory}}

          true ->
            {:ok, canonical_source_dir}
        end

      {:error, {:path_canonicalize_failed, path, reason}} ->
        {:error, {:workspace_bootstrap_automation_invalid_source, path, reason}}
    end
  end

  defp copy_bootstrap_automation_pack(source_dir, destination_dirname, workspace, nil, _opts)
       when is_binary(source_dir) and is_binary(destination_dirname) and is_binary(workspace) do
    destination_dir = Path.join(workspace, destination_dirname)

    if File.exists?(destination_dir) do
      ensure_local_bin_executable(destination_dir)
    else
      case File.cp_r(source_dir, destination_dir) do
        {:ok, _copied_paths} ->
          ensure_local_bin_executable(destination_dir)

        {:error, reason, file} ->
          {:error, {:workspace_bootstrap_automation_copy_failed, :local, reason, file}}
      end
    end
  end

  defp copy_bootstrap_automation_pack(source_dir, destination_dirname, workspace, worker_host, opts)
       when is_binary(source_dir) and is_binary(destination_dirname) and is_binary(workspace) and
              is_binary(worker_host) do
    source_basename = Path.basename(source_dir)
    staging_dir = remote_bootstrap_staging_dir(workspace)

    with :ok <- prepare_remote_bootstrap_automation_destination(workspace, staging_dir, worker_host, opts),
         :ok <- transfer_remote_bootstrap_automation_pack(source_dir, staging_dir, worker_host),
         :ok <-
           finalize_remote_bootstrap_automation_pack(
             workspace,
             staging_dir,
             source_basename,
             destination_dirname,
             worker_host,
             opts
           ) do
      :ok
    end
  end

  defp remote_bootstrap_staging_dir(workspace) when is_binary(workspace) do
    Path.join(Path.dirname(workspace), ".symphony-bootstrap-" <> Path.basename(workspace))
  end

  defp prepare_remote_bootstrap_automation_destination(workspace, staging_dir, worker_host, opts)
       when is_binary(workspace) and is_binary(staging_dir) and is_binary(worker_host) do
    script =
      [
        "set -eu",
        Paths.remote_shell_assign("workspace", workspace),
        Paths.remote_shell_assign("staging_dir", staging_dir),
        "mkdir -p \"$workspace\"",
        "rm -rf \"$staging_dir\"",
        "mkdir -p \"$staging_dir\""
      ]
      |> Enum.join("\n")

    case remote_runner(opts).(script) do
      {:ok, {_output, 0}} ->
        :ok

      {:ok, {output, status}} ->
        {:error, {:workspace_bootstrap_automation_copy_failed, worker_host, status, output}}

      {:error, reason} ->
        {:error, {:workspace_bootstrap_automation_copy_failed, worker_host, reason}}
    end
  end

  defp transfer_remote_bootstrap_automation_pack(source_dir, staging_dir, worker_host)
       when is_binary(source_dir) and is_binary(staging_dir) and is_binary(worker_host) do
    case SSH.copy_dir(worker_host, source_dir, staging_dir, stderr_to_stdout: true) do
      {:ok, {_output, 0}} ->
        :ok

      {:ok, {output, status}} ->
        {:error, {:workspace_bootstrap_automation_copy_failed, worker_host, status, output}}

      {:error, reason} ->
        {:error, {:workspace_bootstrap_automation_copy_failed, worker_host, reason}}
    end
  end

  defp finalize_remote_bootstrap_automation_pack(
         workspace,
         staging_dir,
         source_basename,
         destination_dirname,
         worker_host,
         opts
       )
       when is_binary(workspace) and is_binary(staging_dir) and is_binary(source_basename) and
              is_binary(destination_dirname) and is_binary(worker_host) do
    script =
      [
        "set -eu",
        Paths.remote_shell_assign("workspace", workspace),
        Paths.remote_shell_assign("staging_dir", staging_dir),
        Paths.remote_shell_assign("source_path", Path.join(staging_dir, source_basename)),
        Paths.remote_shell_assign("destination_dir", Path.join(workspace, destination_dirname)),
        "if [ ! -d \"$source_path\" ]; then",
        "  printf '%s\\n' 'remote bootstrap source missing after copy' >&2",
        "  exit 76",
        "fi",
        "mkdir -p \"$workspace\"",
        "rm -rf \"$destination_dir\"",
        "mv \"$source_path\" \"$destination_dir\"",
        "if [ -d \"$destination_dir/bin\" ]; then chmod +x \"$destination_dir\"/bin/* 2>/dev/null || true; fi",
        "rm -rf \"$staging_dir\""
      ]
      |> Enum.join("\n")

    case remote_runner(opts).(script) do
      {:ok, {_output, 0}} ->
        :ok

      {:ok, {output, status}} ->
        {:error, {:workspace_bootstrap_automation_copy_failed, worker_host, status, output}}

      {:error, reason} ->
        {:error, {:workspace_bootstrap_automation_copy_failed, worker_host, reason}}
    end
  end

  defp automation_bootstrap_failure_summary({:workspace_bootstrap_automation_invalid_source, _path, _reason}),
    do: "stage=source_validation"

  defp automation_bootstrap_failure_summary({:workspace_bootstrap_automation_copy_failed, _host, _reason}),
    do: "stage=copy"

  defp automation_bootstrap_failure_summary({:workspace_bootstrap_automation_copy_failed, _host, _status, _output}),
    do: "stage=copy"

  defp automation_bootstrap_failure_summary({:workspace_bootstrap_automation_chmod_failed, _reason}),
    do: "stage=chmod"

  defp automation_bootstrap_failure_summary({:workspace_bootstrap_automation_unavailable, _reason}),
    do: "stage=source_lookup"

  defp ensure_local_bin_executable(destination_dir) when is_binary(destination_dir) do
    bin_dir = Path.join(destination_dir, "bin")

    if File.dir?(bin_dir) do
      bin_dir
      |> File.ls!()
      |> Enum.each(fn entry ->
        path = Path.join(bin_dir, entry)

        if File.regular?(path) do
          File.chmod!(path, 0o755)
        end
      end)
    end

    :ok
  rescue
    error ->
      {:error, {:workspace_bootstrap_automation_chmod_failed, Exception.message(error)}}
  end

  defp emit_bootstrap_event(level, event, issue_context, workspace, worker_host, extra_fields, opts) do
    ObsLogger.emit(
      level,
      event,
      event_fields_builder(opts).(issue_context, workspace, worker_host, extra_fields)
    )
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
end

defmodule SymphonyElixir.AgentProvider.OpenCode.AppServer.Launcher do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, DynamicToolBridge, Environment, Target}
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.AgentProvider.OpenCode.AppServer.Diagnostics
  alias SymphonyElixir.AgentProvider.OpenCode.Settings
  alias SymphonyElixir.PathSafety
  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.Workspace.AutomationPack

  @listening_line_regex ~r/opencode server listening on (?<url>http:\/\/[^\s]+)/
  @port_line_bytes 1_048_576
  @provider_kind Kinds.opencode()

  @spec validate_runtime_placement(keyword()) :: :ok | {:error, term()}
  def validate_runtime_placement(opts) when is_list(opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %Target{placement: :ssh, worker_host: worker_host} ->
        {:error, {:remote_unsupported, worker_host || "ssh"}}

      _target ->
        case Keyword.get(opts, :worker_host) do
          worker_host when is_binary(worker_host) -> {:error, {:remote_unsupported, worker_host}}
          _worker_host -> :ok
        end
    end
  end

  @spec validate_workspace_cwd(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def validate_workspace_cwd(workspace) when is_binary(workspace) do
    expanded_workspace = Path.expand(workspace)

    case PathSafety.canonicalize(expanded_workspace) do
      {:ok, canonical_workspace} ->
        {:ok, canonical_workspace}

      {:error, {:path_canonicalize_failed, path, reason}} ->
        {:error, {:invalid_workspace_cwd, :path_unreadable, path, reason}}
    end
  end

  @spec start_port(Path.t(), Settings.t(), keyword()) :: {:ok, port()} | {:error, term()}
  def start_port(workspace, %Settings{} = settings, opts) when is_binary(workspace) and is_list(opts) do
    with {:ok, env} <- runtime_env(settings, workspace, opts) do
      target = runtime_target(workspace, opts)

      command_spec =
        case Settings.command_argv(settings) do
          argv when is_list(argv) -> CommandSpec.new(argv: argv, env: env, cwd: workspace)
          nil -> CommandSpec.new(command: settings.command, env: env, cwd: workspace)
        end

      target.executor.start(command_spec, target, executor_opts(opts))
    end
  end

  @spec runtime_worker_host(keyword()) :: String.t() | nil
  def runtime_worker_host(opts) when is_list(opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %Target{worker_host: worker_host} when is_binary(worker_host) -> worker_host
      _target -> Keyword.get(opts, :worker_host)
    end
  end

  @spec await_server_url(port(), map()) :: {:ok, String.t()} | {:error, term()}
  def await_server_url(port, context) when is_port(port) and is_map(context) do
    await_server_url(port, context, "")
  end

  defp await_server_url(port, context, pending_line) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        complete_line = pending_line <> IO.chardata_to_string(chunk)

        case parse_listening_url(complete_line) do
          {:ok, url} ->
            {:ok, url}

          :nomatch ->
            Diagnostics.log_port_output("server startup", complete_line)
            await_server_url(port, context, "")
        end

      {^port, {:data, {:noeol, chunk}}} ->
        await_server_url(port, context, pending_line <> IO.chardata_to_string(chunk))

      {^port, {:exit_status, status}} ->
        {:error,
         {:server_start_port_exit,
          Map.merge(context, %{
            exit_status: status,
            message: "OpenCode exited before announcing its listening URL"
          })}}
    after
      Map.fetch!(context, :read_timeout_ms) ->
        {:error,
         {:server_start_timeout,
          Map.merge(context, %{
            message: "OpenCode did not announce its listening URL before read_timeout_ms elapsed"
          })}}
    end
  end

  defp parse_listening_url(line) when is_binary(line) do
    case Regex.named_captures(@listening_line_regex, line) do
      %{"url" => url} -> {:ok, String.trim(url)}
      _captures -> :nomatch
    end
  end

  defp runtime_target(workspace, opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %Target{} = target -> %{target | workspace_path: workspace}
      _target -> Target.new(workspace_path: workspace, worker_host: Keyword.get(opts, :worker_host))
    end
  end

  defp executor_opts(opts) do
    opts
    |> Keyword.put(:line, @port_line_bytes)
    |> Keyword.put_new(:provider_kind, @provider_kind)
  end

  defp runtime_env(%Settings{} = settings, workspace, opts) do
    with {:ok, env} <- Environment.current_env(@provider_kind, settings.telemetry, opts),
         {:ok, bridge_env} <- DynamicToolBridge.runtime_env(opts) do
      provider_env =
        RepoProvider.runtime_env()
        |> Kernel.++(AutomationPack.runtime_env(workspace, ".opencode"))
        |> Map.new()

      {:ok, env |> Map.merge(bridge_env) |> Map.merge(provider_env) |> Map.merge(settings.env)}
    end
  end
end

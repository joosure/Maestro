defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.AppServer.Launcher do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.{DynamicToolBridge, Environment, Target}
  alias SymphonyElixir.AgentProvider.CodeBuddyCode.{CommandRenderer, Settings}
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.PathSafety
  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.Workspace.AutomationPack

  @http_endpoint_line_regex ~r/Endpoint\s+(?<url>http:\/\/(?:127\.0\.0\.1|localhost|\[::1\]):\d+)/
  @port_line_bytes 1_048_576
  @provider_kind Kinds.codebuddy_code()

  @spec validate_runtime_placement(keyword()) :: :ok | {:error, term()}
  def validate_runtime_placement(opts) do
    case runtime_target(nil, opts) do
      %Target{placement: :local} -> :ok
      %Target{worker_host: worker_host} -> {:error, {:remote_unsupported, worker_host}}
    end
  end

  @spec validate_workspace_cwd(Path.t(), String.t() | nil) :: {:ok, Path.t()} | {:error, term()}
  def validate_workspace_cwd(workspace, nil) when is_binary(workspace) do
    expanded_workspace = Path.expand(workspace)

    case PathSafety.canonicalize(expanded_workspace) do
      {:ok, canonical_workspace} -> {:ok, canonical_workspace}
      {:error, {:path_canonicalize_failed, path, reason}} -> {:error, {:invalid_workspace_cwd, :path_unreadable, path, reason}}
    end
  end

  def validate_workspace_cwd(workspace, worker_host) when is_binary(workspace) and is_binary(worker_host) do
    cond do
      String.trim(workspace) == "" -> {:error, {:invalid_workspace_cwd, :empty_remote_workspace, worker_host}}
      String.contains?(workspace, ["\n", "\r", <<0>>]) -> {:error, {:invalid_workspace_cwd, :invalid_remote_workspace, worker_host, workspace}}
      true -> {:ok, workspace}
    end
  end

  @spec start_port(Path.t(), Settings.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def start_port(workspace, %Settings{} = settings, opts) when is_binary(workspace) do
    target = runtime_target(workspace, opts)

    with {:ok, env} <- runtime_env(settings, workspace, opts),
         {:ok, command_spec} <- CommandRenderer.command_spec(workspace, settings, env, opts) do
      target.executor.start(command_spec, target, Keyword.put(opts, :line, @port_line_bytes))
    end
  end

  @spec runtime_worker_host(keyword()) :: String.t() | nil
  def runtime_worker_host(opts) when is_list(opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %Target{worker_host: worker_host} when is_binary(worker_host) -> worker_host
      _target -> Keyword.get(opts, :worker_host)
    end
  end

  @spec await_http_base_url(term(), Settings.t()) :: {:ok, String.t()} | {:error, term()}
  def await_http_base_url(port, %Settings{} = settings) when is_port(port) do
    case Settings.http_port(settings) do
      port_number when is_integer(port_number) ->
        {:ok, "http://#{Settings.http_bind_host(settings)}:#{port_number}"}

      :auto ->
        await_http_endpoint_line(port, settings, "")
    end
  end

  def await_http_base_url(_handle, %Settings{} = settings) do
    case Settings.http_port(settings) do
      port when is_integer(port) ->
        {:ok, "http://#{Settings.http_bind_host(settings)}:#{port}"}

      :auto ->
        {:error, :invalid_codebuddy_http_auto_port_handle}
    end
  end

  defp runtime_target(workspace, opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %Target{} = target ->
        %{target | workspace_path: workspace || target.workspace_path}

      _target ->
        Target.new(workspace_path: workspace, worker_host: Keyword.get(opts, :worker_host))
    end
  end

  defp runtime_env(%Settings{} = settings, workspace, opts) do
    with {:ok, env} <- Environment.current_env(@provider_kind, settings.telemetry, Keyword.put(opts, :include_dynamic_tool_env, false)),
         {:ok, bridge_env} <- DynamicToolBridge.runtime_env(opts) do
      provider_env =
        RepoProvider.runtime_env()
        |> Kernel.++(AutomationPack.runtime_env(workspace, ".codebuddy"))
        |> Map.new()

      {:ok, env |> Map.merge(bridge_env) |> Map.merge(provider_env) |> Map.merge(settings.env)}
    end
  end

  defp await_http_endpoint_line(port, settings, pending_line) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        complete_line = pending_line <> IO.chardata_to_string(chunk)

        case parse_http_endpoint_url(complete_line) do
          {:ok, url} ->
            {:ok, url}

          :nomatch ->
            await_http_endpoint_line(port, settings, "")
        end

      {^port, {:data, {:noeol, chunk}}} ->
        await_http_endpoint_line(port, settings, pending_line <> IO.chardata_to_string(chunk))

      {^port, {:exit_status, status}} ->
        {:error, {:codebuddy_acp_http_start_port_exit, %{exit_status: status}}}
    after
      settings.read_timeout_ms ->
        {:error, {:codebuddy_acp_http_endpoint_timeout, %{message: "CodeBuddy did not announce ACP HTTP endpoint before read_timeout_ms elapsed"}}}
    end
  end

  defp parse_http_endpoint_url(line) when is_binary(line) do
    case Regex.named_captures(@http_endpoint_line_regex, line) do
      %{"url" => url} -> {:ok, normalize_loopback_url(url)}
      _captures -> :nomatch
    end
  end

  defp normalize_loopback_url("http://[::1]:" <> port), do: "http://[::1]:" <> port
  defp normalize_loopback_url(url), do: url
end

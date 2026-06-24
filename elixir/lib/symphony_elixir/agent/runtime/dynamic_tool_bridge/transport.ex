defmodule SymphonyElixir.Agent.Runtime.DynamicToolBridge.Transport do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.{Bridge, Context}
  alias SymphonyElixir.Agent.DynamicTool.Context.RuntimeMetadata
  alias SymphonyElixir.Agent.Runtime.Target
  alias SymphonyElixir.HttpServer
  alias SymphonyElixir.Platform.DynamicToolBridgeContract, as: BridgeContract
  alias SymphonyElixir.Platform.Process, as: PlatformProcess
  alias SymphonyElixir.Platform.SSH

  @loopback_host "127.0.0.1"
  @tunnel_ready_timeout_ms 150
  @shutdown_grace_ms 500
  @shutdown_kill_wait_ms 500

  @type transport :: :local_http | :ssh_tunnel_http | :worker_daemon_http
  @type runtime :: %{
          required(:enabled?) => boolean(),
          required(:env) => map(),
          required(:transport) => transport(),
          optional(:local_port) => pos_integer(),
          optional(:remote_port) => pos_integer(),
          optional(:tunnel) => term(),
          optional(:worker_host) => String.t()
        }

  @spec build(keyword()) :: {:ok, runtime()} | {:error, term()}
  def build(opts) when is_list(opts) do
    with :ok <- reject_unsupported_options(opts),
         {:ok, transport} <- resolve(opts),
         {:ok, enabled?} <- bridge_enabled?(opts) do
      build(enabled?, transport, opts)
    end
  end

  @spec metadata(term()) :: map()
  def metadata(%{enabled?: true, env: env, local_port: local_port, transport: transport} = runtime) do
    %{
      dynamic_tool_bridge_transport: name(transport),
      dynamic_tool_bridge_base_url: Map.get(env, BridgeContract.base_url_env()),
      dynamic_tool_bridge_local_port: local_port,
      dynamic_tool_bridge_remote_port: Map.get(runtime, :remote_port),
      dynamic_tool_bridge_worker_host: Map.get(runtime, :worker_host),
      dynamic_tool_bridge_tunnel_pid: tunnel_os_pid(Map.get(runtime, :tunnel))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def metadata(_runtime), do: %{}

  @spec resolve(keyword()) :: {:ok, transport()} | {:error, term()}
  def resolve(opts) when is_list(opts) do
    {:ok, default_transport(opts)}
  end

  @spec name(transport()) :: String.t()
  def name(:local_http), do: BridgeContract.local_transport()
  def name(:ssh_tunnel_http), do: BridgeContract.ssh_tunnel_transport()
  def name(:worker_daemon_http), do: BridgeContract.worker_daemon_transport()

  defp build(false, transport, _opts) do
    {:ok, %{enabled?: false, env: %{}, transport: transport}}
  end

  defp build(true, transport, opts) do
    bridge_token = bridge_token(opts)

    with {:ok, local_port} <- local_port(transport, opts),
         {:ok, worker_host} <- worker_host(transport, opts),
         {:ok, remote_port} <- remote_port(transport, local_port, opts) do
      build(transport, local_port, remote_port, worker_host, bridge_token)
    else
      {:error, reason} ->
        Bridge.unregister_context(bridge_token)
        {:error, reason}
    end
  end

  defp build(:worker_daemon_http, local_port, _remote_port, _worker_host, bridge_token) do
    {:ok,
     %{
       enabled?: true,
       env: %{},
       local_port: local_port,
       transport: :worker_daemon_http,
       bridge_token: bridge_token,
       daemon_bridge: daemon_bridge_spec(local_port, bridge_token)
     }}
  end

  defp build(transport, local_port, remote_port, worker_host, bridge_token) do
    bridge_port = bridge_port(transport, local_port, remote_port)

    runtime = %{
      enabled?: true,
      env: bridge_env(transport, bridge_port, bridge_token),
      local_port: local_port,
      transport: transport,
      bridge_token: bridge_token
    }

    {:ok, maybe_put_remote(runtime, transport, remote_port, worker_host)}
  end

  defp bridge_env(transport, port, bridge_token) do
    %{
      BridgeContract.base_url_env() => "http://#{@loopback_host}:#{port}#{BridgeContract.base_path()}",
      BridgeContract.token_env() => bridge_token,
      BridgeContract.transport_env() => name(transport)
    }
  end

  defp daemon_bridge_spec(local_port, bridge_token) do
    %{
      "type" => "symphony_dynamic_tool_bridge",
      "transport" => name(:worker_daemon_http),
      "symphony_base_url" => "http://#{@loopback_host}:#{local_port}#{BridgeContract.base_path()}",
      "base_path" => BridgeContract.base_path(),
      "execute_path" => BridgeContract.execute_path(),
      "token" => bridge_token,
      "provider_env" => %{
        BridgeContract.base_url_env() => "daemon_session_loopback",
        BridgeContract.token_env() => "session_scoped_token",
        BridgeContract.transport_env() => name(:worker_daemon_http)
      }
    }
  end

  defp default_transport(opts) do
    cond do
      worker_daemon_target?(opts) -> :worker_daemon_http
      worker_target?(opts) -> :ssh_tunnel_http
      true -> :local_http
    end
  end

  defp bridge_token(opts) do
    case Keyword.get(opts, :tool_context) do
      tool_context when is_map(tool_context) ->
        opts
        |> Context.from_opts()
        |> Map.put(:runtime_metadata, runtime_metadata(opts))
        |> Bridge.register_context()

      _tool_context ->
        Bridge.token()
    end
  end

  defp runtime_metadata(opts) when is_list(opts) do
    RuntimeMetadata.empty()
    |> put_metadata(:run_id, Keyword.get(opts, :run_id))
    |> put_metadata(:issue_id, Keyword.get(opts, :issue_id))
    |> put_metadata(:issue_identifier, Keyword.get(opts, :issue_identifier))
    |> put_metadata(:agent_provider_kind, Keyword.get(opts, :agent_provider_kind))
    |> put_metadata(:session_id, Keyword.get(opts, :session_id))
    |> put_metadata(:thread_id, Keyword.get(opts, :thread_id))
    |> put_metadata(:turn_id, Keyword.get(opts, :turn_id))
    |> put_metadata(:worker_host, Keyword.get(opts, :worker_host))
    |> put_issue_metadata(Keyword.get(opts, :issue))
  end

  defp put_issue_metadata(metadata, %{id: id, identifier: identifier}) do
    metadata
    |> put_metadata(:issue_id, id)
    |> put_metadata(:issue_identifier, identifier)
  end

  defp put_issue_metadata(metadata, _issue), do: metadata

  defp put_metadata(metadata, key, value) when is_atom(key) and is_binary(value) do
    RuntimeMetadata.put(metadata, key, value)
  end

  defp put_metadata(metadata, _key, _value), do: metadata

  defp reject_unsupported_options(opts) do
    cond do
      Keyword.has_key?(opts, :dynamic_tool_bridge_host) ->
        {:error, {:unsupported_dynamic_tool_bridge_option, :dynamic_tool_bridge_host}}

      Keyword.has_key?(opts, :dynamic_tool_bridge_transport) ->
        {:error, {:unsupported_dynamic_tool_bridge_option, :dynamic_tool_bridge_transport}}

      true ->
        :ok
    end
  end

  defp bridge_enabled?(opts) do
    opts
    |> Context.from_opts()
    |> Context.tool_specs()
    |> case do
      [] -> {:ok, false}
      _tool_specs -> {:ok, true}
    end
  rescue
    error ->
      {:error, {:dynamic_tool_bridge_context_failed, Exception.message(error)}}
  end

  defp worker_target?(opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %Target{placement: :ssh} ->
        true

      _target ->
        case Keyword.get(opts, :worker_host) do
          worker_host when is_binary(worker_host) -> String.trim(worker_host) != ""
          _worker_host -> false
        end
    end
  end

  defp worker_daemon_target?(opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %Target{placement: :worker_daemon} -> true
      _target -> false
    end
  end

  defp local_port(:local_http, opts), do: local_port_value(opts)
  defp local_port(:ssh_tunnel_http, opts), do: local_port_value(opts)
  defp local_port(:worker_daemon_http, opts), do: local_port_value(opts)

  defp local_port_value(opts) do
    opts
    |> Keyword.get(:http_port, HttpServer.bound_port())
    |> normalize_port(:dynamic_tool_bridge_http_port_unavailable)
  end

  defp worker_host(:local_http, _opts), do: {:ok, nil}
  defp worker_host(:worker_daemon_http, _opts), do: {:ok, nil}

  defp worker_host(:ssh_tunnel_http, opts) do
    case runtime_worker_host(opts) do
      worker_host when is_binary(worker_host) ->
        case String.trim(worker_host) do
          "" -> {:error, :dynamic_tool_bridge_worker_host_required}
          normalized -> {:ok, normalized}
        end

      _worker_host ->
        {:error, :dynamic_tool_bridge_worker_host_required}
    end
  end

  defp runtime_worker_host(opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %Target{worker_host: worker_host} when is_binary(worker_host) -> worker_host
      _target -> Keyword.get(opts, :worker_host)
    end
  end

  defp remote_port(:local_http, _local_port, _opts), do: {:ok, nil}
  defp remote_port(:worker_daemon_http, _local_port, _opts), do: {:ok, nil}

  defp remote_port(:ssh_tunnel_http, local_port, opts) do
    opts
    |> Keyword.get(BridgeContract.remote_port_option_key(), local_port)
    |> normalize_port(:invalid_dynamic_tool_bridge_remote_port)
  end

  defp normalize_port(port, _error) when is_integer(port) and port in 1..65_535, do: {:ok, port}

  defp normalize_port(port, error) when is_binary(port) do
    case Integer.parse(port) do
      {number, ""} when number in 1..65_535 -> {:ok, number}
      _parsed -> {:error, {error, port}}
    end
  end

  defp normalize_port(_port, error), do: {:error, error}

  defp bridge_port(:local_http, local_port, _remote_port), do: local_port
  defp bridge_port(:ssh_tunnel_http, _local_port, remote_port), do: remote_port

  defp maybe_put_remote(runtime, :local_http, _remote_port, _worker_host), do: runtime

  defp maybe_put_remote(runtime, :ssh_tunnel_http, remote_port, worker_host) do
    runtime
    |> Map.put(:remote_port, remote_port)
    |> Map.put(:worker_host, worker_host)
  end

  @spec start_tunnel(runtime(), keyword()) :: {:ok, term()} | {:error, term()}
  def start_tunnel(%{enabled?: false}, _opts), do: {:ok, nil}
  def start_tunnel(%{transport: :local_http}, _opts), do: {:ok, nil}
  def start_tunnel(%{transport: :worker_daemon_http}, _opts), do: {:ok, nil}

  def start_tunnel(
        %{transport: :ssh_tunnel_http, worker_host: worker_host, remote_port: remote_port, local_port: local_port},
        opts
      ) do
    forwarder = Keyword.get(opts, :dynamic_tool_bridge_ssh_forwarder, &SSH.start_remote_port_forward/5)
    forward_opts = Keyword.get(opts, :dynamic_tool_bridge_ssh_forward_opts, [])

    case forwarder.(worker_host, remote_port, @loopback_host, local_port, forward_opts) do
      {:ok, tunnel} -> await_tunnel_ready(tunnel, opts)
      {:error, reason} -> {:error, {:dynamic_tool_bridge_tunnel_start_failed, worker_host, reason}}
      other -> {:error, {:dynamic_tool_bridge_tunnel_start_failed, worker_host, other}}
    end
  end

  defp await_tunnel_ready(tunnel, opts) when is_port(tunnel) do
    timeout_ms = Keyword.get(opts, :dynamic_tool_bridge_tunnel_ready_timeout_ms, @tunnel_ready_timeout_ms)

    receive do
      {^tunnel, {:exit_status, status}} ->
        {:error, {:dynamic_tool_bridge_tunnel_start_failed, :ssh_tunnel_exited, status}}
    after
      max(timeout_ms, 0) ->
        {:ok, tunnel}
    end
  end

  defp await_tunnel_ready(tunnel, _opts), do: {:ok, tunnel}

  @spec stop_tunnel(term()) :: :ok
  def stop_tunnel(tunnel) when is_port(tunnel) do
    tunnel
    |> PlatformProcess.port_os_pid()
    |> PlatformProcess.terminate_os_process(
      process_group?: true,
      grace_ms: @shutdown_grace_ms,
      kill_wait_ms: @shutdown_kill_wait_ms
    )

    PlatformProcess.close_port(tunnel)
  end

  def stop_tunnel(_tunnel), do: :ok

  defp tunnel_os_pid(tunnel) when is_port(tunnel), do: PlatformProcess.port_os_pid(tunnel)
  defp tunnel_os_pid(_tunnel), do: nil
end

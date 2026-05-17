defmodule SymphonyWorkerDaemon.BridgeProxy.ProxyOptions do
  @moduledoc false

  alias SymphonyElixir.Platform.DynamicToolBridgeContract
  alias SymphonyWorkerDaemon.BridgeProxy.{PortReservation, Requester}

  @loopback_ip {127, 0, 0, 1}
  @loopback_host "127.0.0.1"
  @base_path DynamicToolBridgeContract.base_path()
  @base_url_env DynamicToolBridgeContract.base_url_env()
  @token_env DynamicToolBridgeContract.token_env()
  @transport_env DynamicToolBridgeContract.transport_env()
  @transport DynamicToolBridgeContract.worker_daemon_transport()
  @default_timeout_ms 30_000

  @spec ensure_enabled(keyword()) :: :ok | {:error, :dynamic_tool_bridge_proxy_disabled}
  def ensure_enabled(opts) when is_list(opts) do
    if Keyword.get(opts, :enable_dynamic_tool_bridge_proxy?, false) do
      :ok
    else
      {:error, :dynamic_tool_bridge_proxy_disabled}
    end
  end

  @spec upstream_token(map()) :: {:ok, String.t()} | {:error, :dynamic_tool_bridge_upstream_token_missing}
  def upstream_token(%{"token" => token}) when is_binary(token) do
    case String.trim(token) do
      "" -> {:error, :dynamic_tool_bridge_upstream_token_missing}
      value -> {:ok, value}
    end
  end

  def upstream_token(_bridge_spec), do: {:error, :dynamic_tool_bridge_upstream_token_missing}

  @spec port(keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def port(opts) when is_list(opts) do
    case Keyword.get(opts, :bridge_proxy_port) do
      port when is_integer(port) and port in 1..65_535 -> {:ok, port}
      nil -> PortReservation.reserve(@loopback_ip)
      port -> {:error, {:invalid_dynamic_tool_bridge_proxy_port, port}}
    end
  end

  @spec plug_opts(String.t(), String.t(), String.t(), keyword()) :: keyword()
  def plug_opts(upstream_base_url, upstream_token, session_token, opts) when is_list(opts) do
    [
      upstream_base_url: upstream_base_url,
      upstream_token: upstream_token,
      session_token: session_token,
      requester: Keyword.get(opts, :bridge_proxy_requester, &Requester.request/5),
      timeout_ms: Keyword.get(opts, :bridge_proxy_timeout_ms, @default_timeout_ms),
      max_header_bytes: Keyword.get(opts, :max_header_bytes),
      max_request_body_bytes: Keyword.get(opts, :max_request_body_bytes)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  @spec provider_env(pos_integer(), String.t()) :: map()
  def provider_env(port, session_token) when is_integer(port) and is_binary(session_token) do
    %{
      @base_url_env => "http://#{@loopback_host}:#{port}#{@base_path}",
      @token_env => session_token,
      @transport_env => @transport
    }
  end
end

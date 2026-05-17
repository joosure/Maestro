defmodule SymphonyElixir.Platform.DynamicToolBridgeContract do
  @moduledoc """
  Stable external-process contract for the Agent Dynamic Tool bridge.

  This module intentionally lives in the low-level platform namespace so both
  the main application and worker daemon can share the same protocol strings
  without coupling the daemon to higher-level agent contexts.
  """

  @base_path "/api/v1/agent-tools/dynamic"
  @execute_suffix "/execute"
  @execute_path @base_path <> @execute_suffix
  @base_url_env "SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL"
  @token_env "SYMPHONY_DYNAMIC_TOOL_BRIDGE_TOKEN"
  @transport_env "SYMPHONY_DYNAMIC_TOOL_BRIDGE_TRANSPORT"
  @token_config_key :dynamic_tool_bridge_token
  @remote_port_option_key :dynamic_tool_bridge_remote_port
  @local_transport "local_http"
  @ssh_tunnel_transport "ssh_tunnel_http"
  @worker_daemon_transport "worker_daemon_http"

  @spec base_path() :: String.t()
  def base_path, do: @base_path

  @spec execute_suffix() :: String.t()
  def execute_suffix, do: @execute_suffix

  @spec execute_path() :: String.t()
  def execute_path, do: @execute_path

  @spec base_url_env() :: String.t()
  def base_url_env, do: @base_url_env

  @spec token_env() :: String.t()
  def token_env, do: @token_env

  @spec transport_env() :: String.t()
  def transport_env, do: @transport_env

  @spec token_config_key() :: atom()
  def token_config_key, do: @token_config_key

  @spec remote_port_option_key() :: atom()
  def remote_port_option_key, do: @remote_port_option_key

  @spec local_transport() :: String.t()
  def local_transport, do: @local_transport

  @spec ssh_tunnel_transport() :: String.t()
  def ssh_tunnel_transport, do: @ssh_tunnel_transport

  @spec worker_daemon_transport() :: String.t()
  def worker_daemon_transport, do: @worker_daemon_transport
end

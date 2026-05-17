defmodule SymphonyElixir.Agent.DynamicTool.BridgeContract do
  @moduledoc """
  Stable external-process contract for the Agent Dynamic Tool bridge.
  """

  alias SymphonyElixir.Platform.DynamicToolBridgeContract
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @spec base_path() :: String.t()
  defdelegate base_path(), to: DynamicToolBridgeContract

  @spec execute_suffix() :: String.t()
  defdelegate execute_suffix(), to: DynamicToolBridgeContract

  @spec execute_path() :: String.t()
  defdelegate execute_path(), to: DynamicToolBridgeContract

  @spec base_url_env() :: String.t()
  defdelegate base_url_env(), to: DynamicToolBridgeContract

  @spec token_env() :: String.t()
  defdelegate token_env(), to: DynamicToolBridgeContract

  @spec transport_env() :: String.t()
  defdelegate transport_env(), to: DynamicToolBridgeContract

  @spec token_config_key() :: atom()
  defdelegate token_config_key(), to: DynamicToolBridgeContract

  @spec remote_port_option_key() :: atom()
  defdelegate remote_port_option_key(), to: DynamicToolBridgeContract

  @spec local_transport() :: String.t()
  defdelegate local_transport(), to: DynamicToolBridgeContract

  @spec ssh_tunnel_transport() :: String.t()
  defdelegate ssh_tunnel_transport(), to: DynamicToolBridgeContract

  @spec worker_daemon_transport() :: String.t()
  defdelegate worker_daemon_transport(), to: DynamicToolBridgeContract

  @spec response_success(term()) :: Response.envelope()
  defdelegate response_success(payload), to: Response, as: :success

  @spec response_failure(term()) :: Response.envelope()
  defdelegate response_failure(payload), to: Response, as: :failure

  @spec response_error(String.t()) :: Response.envelope()
  defdelegate response_error(message), to: Response, as: :error

  @spec response_error(String.t() | nil, String.t(), map()) :: Response.envelope()
  defdelegate response_error(code, message, fields \\ %{}), to: Response, as: :error

  @spec response_error_payload(String.t() | nil, String.t(), map()) :: map()
  defdelegate response_error_payload(code, message, fields \\ %{}), to: Response, as: :error_payload

  @spec response_success?(term()) :: boolean()
  defdelegate response_success?(payload), to: Response, as: :success?
end

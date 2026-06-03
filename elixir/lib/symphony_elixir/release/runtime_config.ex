defmodule SymphonyElixir.Release.RuntimeConfig do
  @moduledoc false

  alias SymphonyElixir.Platform.Env
  alias SymphonyElixir.Release.WorkflowSource

  @host_env "HOST"
  @port_env "PORT"
  @default_host "0.0.0.0"
  @default_port "4000"

  @enforce_keys [:host, :port, :workflow_source]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          host: String.t(),
          port: String.t(),
          workflow_source: WorkflowSource.t()
        }

  @spec host_env() :: String.t()
  def host_env, do: @host_env

  @spec port_env() :: String.t()
  def port_env, do: @port_env

  @spec default_host() :: String.t()
  def default_host, do: @default_host

  @spec default_port() :: String.t()
  def default_port, do: @default_port

  @spec from_env(map()) :: t()
  def from_env(env_map) when is_map(env_map) do
    %__MODULE__{
      host: Env.value(env_map, @host_env, @default_host),
      port: Env.value(env_map, @port_env, @default_port),
      workflow_source: WorkflowSource.from_env(env_map)
    }
  end
end

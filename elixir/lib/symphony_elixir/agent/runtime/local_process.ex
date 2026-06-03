defmodule SymphonyElixir.Agent.Runtime.LocalProcess do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyElixir.Agent.Runtime.LocalProcess.{Registry, Sweeper}

  @default_registry Registry

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [Keyword.delete(opts, :id)]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  defdelegate start_link(opts \\ []), to: Registry

  @spec default_registry() :: GenServer.server()
  def default_registry, do: @default_registry

  @spec register(port(), CommandSpec.t(), Target.t(), keyword(), GenServer.server()) :: :ok
  defdelegate register(port, command_spec, target, opts, server \\ @default_registry), to: Registry

  @spec unregister(term(), GenServer.server()) :: :ok
  defdelegate unregister(handle, server \\ @default_registry), to: Registry

  @spec sweep(keyword()) :: Sweeper.sweep_result()
  defdelegate sweep(opts \\ []), to: Sweeper
end

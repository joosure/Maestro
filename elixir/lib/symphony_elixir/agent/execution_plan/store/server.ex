defmodule SymphonyElixir.Agent.ExecutionPlan.Store.Server do
  @moduledoc false

  use GenServer

  alias SymphonyElixir.Agent.ExecutionPlan.Store.Commands
  alias SymphonyElixir.Agent.ExecutionPlan.Store.Persistence

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            backend: module() | nil,
            backend_state: term()
          }

    defstruct backend: nil,
              backend_state: nil
  end

  @spec start_link(keyword(), module()) :: GenServer.on_start()
  def start_link(opts \\ [], default_name \\ __MODULE__) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: default_name)
    end
  end

  @impl true
  def init(opts), do: Persistence.init(opts)

  @impl true
  def handle_call(message, _from, %State{} = state) do
    {reply, next_state} = Commands.run(message, state)
    {:reply, reply, next_state}
  end
end

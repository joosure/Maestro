defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Server do
  @moduledoc """
  GenServer process boundary for workflow structured-plan store operations.

  Public API functions live in `Store`. Transaction orchestration lives in
  `Store.Commands`; persistence reads/writes live in `Store.Persistence`.
  """

  use GenServer

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Commands
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Persistence

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            backend: module() | nil,
            backend_state: term(),
            agent_store: atom() | pid() | nil
          }

    defstruct backend: nil,
              backend_state: nil,
              agent_store: nil
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} ->
        GenServer.start_link(__MODULE__, opts |> Keyword.delete(:name) |> Keyword.put(:agent_store_mode, :local))

      {:ok, name} ->
        GenServer.start_link(__MODULE__, opts, name: name)

      :error ->
        GenServer.start_link(__MODULE__, opts, name: Store)
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

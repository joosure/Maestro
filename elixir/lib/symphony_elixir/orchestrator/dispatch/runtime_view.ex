defmodule SymphonyElixir.Orchestrator.Dispatch.RuntimeView do
  @moduledoc false

  @type t :: %{
          optional(:running) => map(),
          optional(:claimed) => [term()],
          optional(:orchestrator_slots) => integer(),
          optional(:worker_slots_available?) => boolean()
        }

  @spec running(t()) :: map()
  def running(%{running: running}) when is_map(running), do: running
  def running(_runtime), do: %{}

  @spec claimed(t()) :: [term()]
  def claimed(%{claimed: claimed}) when is_struct(claimed, MapSet), do: Enum.to_list(claimed)
  def claimed(%{claimed: claimed}) when is_list(claimed), do: claimed
  def claimed(_runtime), do: []

  @spec orchestrator_slots(t()) :: integer()
  def orchestrator_slots(%{orchestrator_slots: slots}) when is_integer(slots), do: slots
  def orchestrator_slots(_runtime), do: 0

  @spec worker_slots_available?(t()) :: boolean()
  def worker_slots_available?(%{worker_slots_available?: worker_slots_available?})
      when is_boolean(worker_slots_available?),
      do: worker_slots_available?

  def worker_slots_available?(_runtime), do: false
end

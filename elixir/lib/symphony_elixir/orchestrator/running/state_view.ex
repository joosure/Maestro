defmodule SymphonyElixir.Orchestrator.Running.StateView do
  @moduledoc false

  @spec running_entries(map()) :: map()
  def running_entries(%{running: running}) when is_map(running), do: running
  def running_entries(_state), do: %{}

  @spec claimed_entries(map()) :: MapSet.t()
  def claimed_entries(%{claimed: claimed}) when is_struct(claimed, MapSet), do: claimed
  def claimed_entries(_state), do: MapSet.new()

  @spec retry_attempts(map()) :: map()
  def retry_attempts(%{retry_attempts: retry_attempts}) when is_map(retry_attempts),
    do: retry_attempts

  def retry_attempts(_state), do: %{}

  @spec put_running(map(), map()) :: map()
  def put_running(%{running: _} = state, running) when is_map(running), do: %{state | running: running}
  def put_running(state, _running), do: state

  @spec put_claimed(map(), MapSet.t()) :: map()
  def put_claimed(%{claimed: _} = state, claimed) when is_struct(claimed, MapSet),
    do: %{state | claimed: claimed}

  def put_claimed(state, _claimed), do: state

  @spec put_retry_attempts(map(), map()) :: map()
  def put_retry_attempts(%{retry_attempts: _} = state, retry_attempts) when is_map(retry_attempts),
    do: %{state | retry_attempts: retry_attempts}

  def put_retry_attempts(state, _retry_attempts), do: state
end

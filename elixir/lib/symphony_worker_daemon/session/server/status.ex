defmodule SymphonyWorkerDaemon.Session.Server.Status do
  @moduledoc false

  @spec exit_status_name(integer()) :: String.t()
  def exit_status_name(0), do: "exited"
  def exit_status_name(_status), do: "failed"

  @spec put_stop_reason(map(), term()) :: map()
  def put_stop_reason(state, nil), do: state
  def put_stop_reason(state, reason) when is_binary(reason), do: Map.put(state, :stop_reason, reason)
  def put_stop_reason(state, reason) when is_atom(reason), do: Map.put(state, :stop_reason, Atom.to_string(reason))
  def put_stop_reason(state, reason), do: Map.put(state, :stop_reason, inspect(reason))
end

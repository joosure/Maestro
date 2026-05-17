defmodule SymphonyWorkerDaemon.Protocol.ResponseStatus do
  @moduledoc """
  Stable non-session lifecycle statuses used by Worker Daemon mutation responses.
  """

  @accepted "accepted"

  @spec accepted() :: String.t()
  def accepted, do: @accepted
end

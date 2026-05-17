defmodule SymphonyElixir.Orchestrator.Retry.Status do
  @moduledoc false

  @retry_scheduled "retry_scheduled"

  @spec retry_scheduled() :: String.t()
  def retry_scheduled, do: @retry_scheduled
end

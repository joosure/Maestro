defmodule SymphonyElixir.Storage.Retention.NoopBackend do
  @moduledoc false

  @behaviour SymphonyElixir.Storage.Retention

  @impl true
  def prune(_opts) do
    {:ok,
     %{
       deleted_count: 0,
       policies: []
     }}
  end
end

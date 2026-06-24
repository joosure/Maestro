defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.AdminBackend do
  @moduledoc false

  @callback reset(keyword()) :: :ok | {:error, term()}
end

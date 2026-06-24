defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.Admin do
  @moduledoc """
  Administrative controls for Coding PR Delivery known-target storage.

  This module owns destructive storage operations. Runtime code should use the
  `KnownTarget.Storage` facade for ordinary load/put/delete operations and call
  this module only from admin or test boundaries.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.BackendSelector
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.Validator

  @spec reset(keyword()) :: :ok | {:error, term()}
  def reset(opts) do
    with {:ok, opts} <- Validator.validate_opts(opts),
         {:ok, backend} <- BackendSelector.fetch_admin(opts) do
      backend.reset(opts)
    end
  end
end

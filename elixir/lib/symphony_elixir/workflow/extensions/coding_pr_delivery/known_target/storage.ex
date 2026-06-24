defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage do
  @moduledoc """
  Business storage port for Coding PR Delivery known targets.

  Callers depend on this port instead of a physical persistence backend. The
  default backend stores records through the workflow extension state boundary.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.BackendSelector
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.Validator

  @callback load(keyword()) :: {:ok, [KnownTarget.t()]} | {:error, term()}
  @callback put(KnownTarget.t(), keyword()) :: :ok | {:error, term()}
  @callback put_many([KnownTarget.t()], keyword()) :: :ok | {:error, term()}
  @callback delete(String.t(), keyword()) :: :ok | {:error, term()}

  @spec default_backend() :: module()
  def default_backend, do: BackendSelector.default_backend()

  @spec load(keyword()) :: {:ok, [KnownTarget.t()]} | {:error, term()}
  def load(opts) do
    with {:ok, opts} <- Validator.validate_opts(opts),
         {:ok, backend} <- BackendSelector.fetch(opts) do
      backend.load(opts)
    end
  end

  @spec put(KnownTarget.t(), keyword()) :: :ok | {:error, term()}
  def put(target, opts) do
    with {:ok, opts} <- Validator.validate_opts(opts),
         :ok <- Validator.validate_target(target),
         {:ok, backend} <- BackendSelector.fetch(opts) do
      backend.put(target, opts)
    end
  end

  @spec put_many([KnownTarget.t()], keyword()) :: :ok | {:error, term()}
  def put_many(targets, opts) do
    with {:ok, opts} <- Validator.validate_opts(opts),
         :ok <- Validator.validate_targets(targets),
         {:ok, backend} <- BackendSelector.fetch(opts) do
      backend.put_many(targets, opts)
    end
  end

  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(issue_id, opts) do
    with {:ok, opts} <- Validator.validate_opts(opts),
         :ok <- Validator.validate_issue_id(issue_id),
         {:ok, backend} <- BackendSelector.fetch(opts) do
      backend.delete(issue_id, opts)
    end
  end
end

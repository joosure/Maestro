defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.BackendSelector do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.Error
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.StateStoreBackend

  @ordinary_callbacks [
    load: 1,
    put: 2,
    put_many: 2,
    delete: 2
  ]

  @admin_callbacks [
    reset: 1
  ]

  @spec default_backend() :: module()
  def default_backend, do: StateStoreBackend

  @spec fetch(keyword()) :: {:ok, module()} | {:error, map()}
  def fetch(opts) when is_list(opts) do
    opts
    |> Keyword.get(:backend, default_backend())
    |> validate()
  end

  @spec fetch_admin(keyword()) :: {:ok, module()} | {:error, map()}
  def fetch_admin(opts) when is_list(opts) do
    opts
    |> Keyword.get(:backend, default_backend())
    |> validate(@admin_callbacks)
  end

  @spec validate(term()) :: {:ok, module()} | {:error, map()}
  def validate(backend), do: validate(backend, @ordinary_callbacks)

  defp validate(backend, required_callbacks) when is_atom(backend) and not is_nil(backend) and is_list(required_callbacks) do
    with true <- Code.ensure_loaded?(backend),
         [] <- missing_callbacks(backend, required_callbacks) do
      {:ok, backend}
    else
      false -> {:error, Error.invalid_backend(backend, :backend_not_loaded)}
      missing_callbacks when is_list(missing_callbacks) -> {:error, Error.invalid_backend_contract(backend, missing_callbacks)}
    end
  end

  defp validate(backend, _required_callbacks), do: {:error, Error.invalid_backend(backend, :backend_not_module)}

  defp missing_callbacks(backend, required_callbacks) do
    Enum.reject(required_callbacks, fn {name, arity} ->
      function_exported?(backend, name, arity)
    end)
  end
end

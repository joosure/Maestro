defmodule SymphonyElixir.Agent.Credential.Accounts.Lifecycle do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Accounts.ProviderKind
  alias SymphonyElixir.Agent.Credential.Store

  @spec list(String.t() | nil, keyword() | map() | nil) :: {:ok, [Store.account()]} | {:error, term()}
  def list(nil, opts), do: Store.list_all(opts)

  def list(provider_kind, opts) when is_binary(provider_kind) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind) do
      Store.list(provider_kind, opts)
    end
  end

  @spec pause(String.t(), String.t(), keyword(), keyword() | map() | nil) :: {:ok, Store.account()} | {:error, term()}
  def pause(provider_kind, id, opts, store_opts) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind) do
      Store.pause(provider_kind, id, opts, store_opts)
    end
  end

  @spec resume(String.t(), String.t(), keyword() | map() | nil) :: {:ok, Store.account()} | {:error, term()}
  def resume(provider_kind, id, store_opts) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind) do
      Store.resume(provider_kind, id, store_opts)
    end
  end

  @spec enable(String.t(), String.t(), keyword() | map() | nil) :: {:ok, Store.account()} | {:error, term()}
  def enable(provider_kind, id, store_opts) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind) do
      Store.enable(provider_kind, id, store_opts)
    end
  end

  @spec disable(String.t(), String.t(), keyword() | map() | nil) :: {:ok, Store.account()} | {:error, term()}
  def disable(provider_kind, id, store_opts) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind) do
      Store.disable(provider_kind, id, store_opts)
    end
  end

  @spec remove(String.t(), String.t(), keyword() | map() | nil) :: :ok | {:error, term()}
  def remove(provider_kind, id, store_opts) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind) do
      Store.remove(provider_kind, id, store_opts)
    end
  end

  @spec list_leases(String.t() | nil, String.t() | nil, keyword() | map() | nil) :: {:ok, [map()]} | {:error, term()}
  def list_leases(nil, nil, opts), do: Store.list_leases(nil, nil, opts)

  def list_leases(provider_kind, nil, opts) when is_binary(provider_kind) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind) do
      Store.list_leases(provider_kind, nil, opts)
    end
  end

  def list_leases(provider_kind, id, opts) when is_binary(provider_kind) and is_binary(id) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind) do
      Store.list_leases(provider_kind, id, opts)
    end
  end

  @spec release_lease(String.t(), String.t(), String.t(), keyword() | map() | nil) :: {:ok, map()} | {:error, term()}
  def release_lease(provider_kind, id, lease_id, store_opts) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind) do
      Store.release_lease(provider_kind, id, lease_id, store_opts)
    end
  end
end

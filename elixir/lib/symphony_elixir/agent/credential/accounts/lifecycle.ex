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
end

defmodule SymphonyElixir.Agent.Credential.Accounts do
  @moduledoc """
  Operator account lifecycle API backed by the provider-neutral credential store.
  """

  alias SymphonyElixir.Agent.Credential.Accounts.{
    Environment,
    Import,
    Lifecycle,
    Login,
    ProviderKind,
    Verification
  }

  alias SymphonyElixir.Agent.Credential.Store

  @type account :: Store.account()

  @spec list(String.t() | nil, keyword() | map() | nil) :: {:ok, [account()]} | {:error, term()}
  def list(provider_kind \\ nil, opts \\ nil), do: Lifecycle.list(provider_kind, opts)

  @spec login(String.t(), String.t(), keyword(), keyword() | map() | nil) :: {:ok, account()} | {:error, term()}
  def login(provider_kind, id, opts \\ [], store_opts \\ nil) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind) do
      Login.login(provider_kind, id, opts, store_opts)
    end
  end

  @spec import_account(String.t(), String.t(), keyword(), keyword() | map() | nil) :: {:ok, account()} | {:error, term()}
  def import_account(provider_kind, id, opts \\ [], store_opts \\ nil) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind) do
      Import.import_account(provider_kind, id, opts, store_opts)
    end
  end

  @spec verify(String.t(), String.t(), keyword(), keyword() | map() | nil) :: {:ok, map()} | {:error, term()}
  def verify(provider_kind, id, opts \\ [], store_opts \\ nil) do
    with {:ok, provider_kind} <- ProviderKind.canonical(provider_kind),
         {:ok, account} <- Store.get(provider_kind, id, store_opts) do
      Verification.verify(account, opts, store_opts)
    end
  end

  @spec pause(String.t(), String.t(), keyword(), keyword() | map() | nil) :: {:ok, account()} | {:error, term()}
  def pause(provider_kind, id, opts \\ [], store_opts \\ nil), do: Lifecycle.pause(provider_kind, id, opts, store_opts)

  @spec resume(String.t(), String.t(), keyword() | map() | nil) :: {:ok, account()} | {:error, term()}
  def resume(provider_kind, id, store_opts \\ nil), do: Lifecycle.resume(provider_kind, id, store_opts)

  @spec enable(String.t(), String.t(), keyword() | map() | nil) :: {:ok, account()} | {:error, term()}
  def enable(provider_kind, id, store_opts \\ nil), do: Lifecycle.enable(provider_kind, id, store_opts)

  @spec disable(String.t(), String.t(), keyword() | map() | nil) :: {:ok, account()} | {:error, term()}
  def disable(provider_kind, id, store_opts \\ nil), do: Lifecycle.disable(provider_kind, id, store_opts)

  @spec remove(String.t(), String.t(), keyword() | map() | nil) :: :ok | {:error, term()}
  def remove(provider_kind, id, store_opts \\ nil), do: Lifecycle.remove(provider_kind, id, store_opts)

  @spec list_leases(String.t() | nil, String.t() | nil, keyword() | map() | nil) :: {:ok, [map()]} | {:error, term()}
  def list_leases(provider_kind \\ nil, id \\ nil, store_opts \\ nil), do: Lifecycle.list_leases(provider_kind, id, store_opts)

  @spec release_lease(String.t(), String.t(), String.t(), keyword() | map() | nil) :: {:ok, map()} | {:error, term()}
  def release_lease(provider_kind, id, lease_id, store_opts \\ nil),
    do: Lifecycle.release_lease(provider_kind, id, lease_id, store_opts)

  @spec account_summary(account() | nil) :: map() | nil
  def account_summary(account), do: Store.account_summary(account)

  @spec credential_env(account() | nil) :: [{String.t(), String.t()}]
  def credential_env(account), do: Environment.credential_env(account)

  @spec normalize_provider_kind(String.t() | nil) :: String.t() | nil
  def normalize_provider_kind(provider_kind), do: ProviderKind.normalize(provider_kind)
end

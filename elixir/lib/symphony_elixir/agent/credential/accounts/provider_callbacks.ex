defmodule SymphonyElixir.Agent.Credential.Accounts.ProviderCallbacks do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Registry

  @spec account_login(String.t(), String.t(), keyword(), keyword() | map() | nil) ::
          {:ok, map()} | {:error, term()} | :unsupported
  def account_login(provider_kind, id, opts, store_opts) do
    case provider_adapter(provider_kind) do
      {:ok, adapter} ->
        if adapter_callback_exported?(adapter, :account_login, 3) do
          adapter.account_login(id, opts, store_opts)
        else
          :unsupported
        end

      _adapter ->
        :unsupported
    end
  end

  @spec account_verify(map(), keyword(), keyword() | map() | nil) ::
          {:ok, map()} | {:error, term()} | :unsupported
  def account_verify(account, opts, store_opts) when is_map(account) do
    case provider_adapter(account.agent_provider_kind) do
      {:ok, adapter} ->
        if adapter_callback_exported?(adapter, :account_verify, 3) do
          adapter.account_verify(account, opts, store_opts)
        else
          :unsupported
        end

      _adapter ->
        :unsupported
    end
  end

  defp provider_adapter(provider_kind) when is_binary(provider_kind) do
    {:ok, Registry.fetch!(provider_kind)}
  rescue
    _error -> :error
  end

  defp adapter_callback_exported?(adapter, function, arity) when is_atom(adapter) do
    case Code.ensure_loaded(adapter) do
      {:module, ^adapter} -> function_exported?(adapter, function, arity)
      {:error, _reason} -> false
    end
  end
end

defmodule SymphonyElixir.Agent.Credential.Accounts.Verification do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Accounts.{Command, Environment, ProviderCallbacks}
  alias SymphonyElixir.Agent.Credential.Store

  @spec verify(Store.account(), keyword(), keyword() | map() | nil) :: {:ok, map()} | {:error, term()}
  def verify(account, opts, store_opts) do
    case ProviderCallbacks.account_verify(account, opts, store_opts) do
      :unsupported -> default_verify(account, opts)
      result -> result
    end
  end

  defp default_verify(account, opts) do
    command = Keyword.get(opts, :command) || default_provider_command(account.agent_provider_kind)

    account.agent_provider_kind
    |> verify_args()
    |> case do
      {:ok, args} ->
        Command.run(command, args, Environment.credential_env(account), opts)

      {:error, reason} ->
        {:error, reason}
    end
    |> case do
      {:ok, output} -> {:ok, %{account: Store.account_summary(account), output: String.trim(output)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_args("claude_code"), do: {:ok, ["auth", "status", "--json"]}
  defp verify_args("opencode"), do: {:ok, ["--version"]}
  defp verify_args(provider), do: {:error, {:unsupported_account_verify_provider, provider}}

  defp default_provider_command("claude_code"), do: "claude"
  defp default_provider_command(provider), do: provider
end

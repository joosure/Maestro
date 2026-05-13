defmodule SymphonyElixir.CLI.Accounts.Renderer do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Accounts, as: AgentAccounts

  @spec stored(map()) :: :ok
  def stored(account) do
    IO.puts("Stored #{account.agent_provider_kind} account #{account.id}#{email_suffix(account)}")
  end

  @spec imported(map()) :: :ok
  def imported(account) do
    IO.puts("Imported #{account.agent_provider_kind} account #{account.id}#{email_suffix(account)}")
  end

  @spec listed([map()]) :: :ok
  def listed([]), do: IO.puts("No accounts configured")

  def listed(accounts) when is_list(accounts) do
    Enum.each(accounts, fn account ->
      summary = AgentAccounts.account_summary(account) || account

      [
        account_value(summary, :agent_provider_kind),
        account_value(summary, :id),
        account_value(summary, :email) || "-",
        account_value(summary, :state) || "unknown",
        account_value(summary, :credential_kind) || "-",
        account_value(summary, :failure_reason) || "-"
      ]
      |> Enum.join("\t")
      |> IO.puts()
    end)
  end

  @spec verified(map(), String.t(), String.t()) :: :ok
  def verified(result, provider_kind, id) do
    account = Map.get(result, :account) || %{}
    provider_kind = account_value(account, :agent_provider_kind) || provider_kind
    account_id = account_value(account, :id) || id
    IO.puts("Verified #{provider_kind} account #{account_id}#{email_suffix(account)}")

    case Map.get(result, :output) do
      output when is_binary(output) and output != "" -> IO.puts(output)
      _output -> :ok
    end
  end

  @spec paused(map()) :: :ok
  def paused(account) do
    IO.puts("Paused #{account.agent_provider_kind} account #{account.id}#{email_suffix(account)}")
  end

  @spec resumed(map()) :: :ok
  def resumed(account) do
    IO.puts("Resumed #{account.agent_provider_kind} account #{account.id}#{email_suffix(account)}")
  end

  @spec removed(String.t(), String.t()) :: :ok
  def removed(provider_kind, id) do
    IO.puts("Removed #{AgentAccounts.normalize_provider_kind(provider_kind) || provider_kind} account #{id}")
  end

  @spec enabled(map()) :: :ok
  def enabled(account) do
    IO.puts("Enabled #{account.agent_provider_kind} account #{account.id}#{email_suffix(account)}")
  end

  @spec disabled(map()) :: :ok
  def disabled(account) do
    IO.puts("Disabled #{account.agent_provider_kind} account #{account.id}#{email_suffix(account)}")
  end

  @spec format_error(term()) :: String.t()
  def format_error(reason), do: inspect(reason, limit: 20, printable_limit: 1_000)

  defp email_suffix(%{email: email}) when is_binary(email) and email != "", do: " (#{email})"
  defp email_suffix(%{"email" => email}) when is_binary(email) and email != "", do: " (#{email})"
  defp email_suffix(_account), do: ""

  defp account_value(account, key) when is_map(account), do: Map.get(account, key) || Map.get(account, Atom.to_string(key))
end

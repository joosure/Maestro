defmodule SymphonyElixir.Agent.Credential.Accounts.ProviderKind do
  @moduledoc false

  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(provider_kind) when is_binary(provider_kind) do
    case provider_kind |> String.trim() |> String.downcase() do
      provider when provider in ["claude", "claudecode", "claude_code"] -> "claude_code"
      provider when provider in ["opencode", "open_code"] -> "opencode"
      "" -> nil
      other -> other
    end
  end

  def normalize(_provider_kind), do: nil

  @spec canonical(String.t() | nil) :: {:ok, String.t()} | {:error, :missing_agent_provider_kind}
  def canonical(provider_kind) do
    case normalize(provider_kind) do
      nil -> {:error, :missing_agent_provider_kind}
      provider_kind -> {:ok, provider_kind}
    end
  end
end

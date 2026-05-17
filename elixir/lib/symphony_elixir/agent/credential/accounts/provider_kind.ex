defmodule SymphonyElixir.Agent.Credential.Accounts.ProviderKind do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Kinds

  @spec normalize(term()) :: String.t() | nil
  def normalize(provider_kind), do: Kinds.normalize(provider_kind)

  @spec canonical(String.t() | nil) :: {:ok, String.t()} | {:error, :missing_agent_provider_kind}
  def canonical(provider_kind) do
    case normalize(provider_kind) do
      nil -> {:error, :missing_agent_provider_kind}
      provider_kind -> {:ok, provider_kind}
    end
  end
end

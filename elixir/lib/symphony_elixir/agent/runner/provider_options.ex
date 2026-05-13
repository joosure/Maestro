defmodule SymphonyElixir.Agent.Runner.ProviderOptions do
  @moduledoc false

  @spec from_session(term()) :: keyword()
  def from_session(%{agent_provider_kind: kind}) when is_binary(kind), do: [kind: kind]
  def from_session(_session), do: []
end

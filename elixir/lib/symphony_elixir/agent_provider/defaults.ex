defmodule SymphonyElixir.AgentProvider.Defaults do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Kinds

  @default_kind Kinds.codex()

  @spec default_kind() :: String.t()
  def default_kind, do: @default_kind
end

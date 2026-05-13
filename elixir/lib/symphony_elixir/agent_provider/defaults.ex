defmodule SymphonyElixir.AgentProvider.Defaults do
  @moduledoc false

  @default_kind "codex"

  @spec default_kind() :: String.t()
  def default_kind, do: @default_kind
end

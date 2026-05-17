defmodule SymphonyElixir.RepoProvider.Defaults do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Kinds

  @default_kind Kinds.github()

  @spec default_kind() :: String.t()
  def default_kind, do: @default_kind
end

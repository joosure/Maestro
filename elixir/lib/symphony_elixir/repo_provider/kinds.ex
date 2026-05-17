defmodule SymphonyElixir.RepoProvider.Kinds do
  @moduledoc """
  Stable repo-provider kind identifiers.

  Repo-provider `kind` values are part of the workflow/config extension
  contract, so production code should reference them through this module
  instead of scattering raw string literals.
  """

  @github "github"
  @cnb "cnb"
  @memory "memory"

  @spec github() :: String.t()
  def github, do: @github

  @spec cnb() :: String.t()
  def cnb, do: @cnb

  @spec memory() :: String.t()
  def memory, do: @memory

  @spec built_in() :: [String.t()]
  def built_in, do: [github(), cnb(), memory()]

  @spec label(term()) :: String.t()
  def label(@github), do: "GitHub"
  def label(@cnb), do: "CNB"
  def label(_kind), do: "repo-provider"
end

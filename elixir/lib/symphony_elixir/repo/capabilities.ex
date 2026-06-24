defmodule SymphonyElixir.Repo.Capabilities do
  @moduledoc """
  Repo-core capability strings.

  These capabilities describe local repository operations exposed by the
  provider-neutral Repo context.
  """

  @behaviour SymphonyElixir.Capability.Source

  @checkout "repo.checkout"
  @diff "repo.diff"
  @commit "repo.commit"
  @push "repo.push"

  @spec checkout() :: String.t()
  def checkout, do: @checkout

  @spec diff() :: String.t()
  def diff, do: @diff

  @spec commit() :: String.t()
  def commit, do: @commit

  @spec push() :: String.t()
  def push, do: @push

  @impl true
  def capabilities, do: core()

  @impl true
  def typed_tool_capabilities, do: core()

  @spec core() :: [String.t()]
  def core do
    [
      checkout(),
      diff(),
      commit(),
      push()
    ]
  end
end

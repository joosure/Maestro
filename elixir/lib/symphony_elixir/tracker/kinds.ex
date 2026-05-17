defmodule SymphonyElixir.Tracker.Kinds do
  @moduledoc """
  Stable tracker adapter kind identifiers.

  Tracker `kind` values are public configuration and extension identifiers.
  Keep new first-party tracker kinds here, while custom adapters can still
  register arbitrary kind strings through application configuration.
  """

  @linear "linear"
  @tapd "tapd"
  @memory "memory"

  @spec linear() :: String.t()
  def linear, do: @linear

  @spec tapd() :: String.t()
  def tapd, do: @tapd

  @spec memory() :: String.t()
  def memory, do: @memory

  @spec built_in() :: [String.t()]
  def built_in, do: [linear(), tapd(), memory()]
end

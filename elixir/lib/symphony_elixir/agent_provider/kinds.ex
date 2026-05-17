defmodule SymphonyElixir.AgentProvider.Kinds do
  @moduledoc """
  Canonical provider-kind strings for agent provider adapters.
  """

  @codex "codex"
  @claude_code "claude_code"
  @mock "mock"
  @opencode "opencode"

  @claude_code_aliases ["claude", "claudecode", @claude_code]
  @opencode_aliases [@opencode, "open_code"]

  @spec codex() :: String.t()
  def codex, do: @codex

  @spec claude_code() :: String.t()
  def claude_code, do: @claude_code

  @spec mock() :: String.t()
  def mock, do: @mock

  @spec opencode() :: String.t()
  def opencode, do: @opencode

  @spec claude_code_aliases() :: [String.t()]
  def claude_code_aliases, do: @claude_code_aliases

  @spec opencode_aliases() :: [String.t()]
  def opencode_aliases, do: @opencode_aliases

  @spec normalize(term()) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(provider_kind) when is_binary(provider_kind) do
    case provider_kind |> String.trim() |> String.downcase() do
      "" -> nil
      provider when provider in @claude_code_aliases -> @claude_code
      provider when provider in @opencode_aliases -> @opencode
      provider -> provider
    end
  end

  def normalize(provider_kind) when is_atom(provider_kind) do
    provider_kind
    |> Atom.to_string()
    |> normalize()
  end

  def normalize(_provider_kind), do: nil
end

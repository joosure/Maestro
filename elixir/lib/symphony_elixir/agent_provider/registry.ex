defmodule SymphonyElixir.AgentProvider.Registry do
  @moduledoc """
  Registry for AI coding agent provider adapters.
  """

  alias SymphonyElixir.AgentProvider.Kinds

  @codex_kind Kinds.codex()
  @claude_code_kind Kinds.claude_code()
  @codebuddy_code_kind Kinds.codebuddy_code()
  @mock_kind Kinds.mock()
  @opencode_kind Kinds.opencode()

  @default_adapters %{
    @codex_kind => SymphonyElixir.AgentProvider.Codex.Adapter,
    @claude_code_kind => SymphonyElixir.AgentProvider.ClaudeCode.Adapter,
    @codebuddy_code_kind => SymphonyElixir.AgentProvider.CodeBuddyCode.Adapter,
    @mock_kind => SymphonyElixir.AgentProvider.Mock.Adapter,
    @opencode_kind => SymphonyElixir.AgentProvider.OpenCode.Adapter
  }

  @spec default_kind() :: String.t()
  def default_kind, do: SymphonyElixir.AgentProvider.Defaults.default_kind()

  @spec supported_kinds() :: [String.t()]
  def supported_kinds do
    adapters()
    |> Map.keys()
  end

  @spec fetch(term()) :: module() | nil
  def fetch(kind) when is_binary(kind), do: Map.get(adapters(), kind)
  def fetch(_kind), do: nil

  @spec fetch!(term()) :: module()
  def fetch!(kind) do
    case fetch(kind) do
      nil ->
        raise ArgumentError,
              "Unknown agent provider kind: #{inspect(kind)}. Supported: #{inspect(supported_kinds())}"

      adapter ->
        adapter
    end
  end

  @spec adapters() :: %{optional(String.t()) => module()}
  def adapters do
    overrides =
      :symphony_elixir
      |> Application.get_env(:agent_provider_adapters, %{})
      |> normalize_adapters()

    Map.merge(@default_adapters, overrides)
  end

  defp normalize_adapters(adapters) when is_map(adapters), do: adapters

  defp normalize_adapters(adapters) when is_list(adapters) do
    Map.new(adapters, fn {kind, adapter} -> {to_string(kind), adapter} end)
  end

  defp normalize_adapters(_adapters), do: %{}
end

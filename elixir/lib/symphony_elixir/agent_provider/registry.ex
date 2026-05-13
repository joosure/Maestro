defmodule SymphonyElixir.AgentProvider.Registry do
  @moduledoc """
  Registry for AI coding agent provider adapters.
  """

  @default_adapters %{
    "codex" => SymphonyElixir.AgentProvider.Codex.Adapter,
    "claude_code" => SymphonyElixir.AgentProvider.ClaudeCode.Adapter,
    "mock" => SymphonyElixir.AgentProvider.Mock.Adapter,
    "opencode" => SymphonyElixir.AgentProvider.OpenCode.Adapter
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

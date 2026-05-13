defmodule SymphonyElixir.Tracker.Registry do
  @moduledoc """
  Tracker adapter registry.

  Maps tracker `kind` strings to adapter modules. The default mapping
  is bundled with the application; tests and future extensions can
  override or extend it through `:tracker_adapters` application config.

  ## Override Mechanism

  Set `:tracker_adapters` in your application environment to add or
  replace adapter mappings:

      config :symphony_elixir, :tracker_adapters, %{
        "jira" => MyApp.Tracker.Jira.Adapter
      }

  Overrides are merged on top of the built-in defaults, so existing
  adapters remain available unless explicitly replaced.

  ## Testing

  In tests, configure `Application.put_env/3` before the test to
  inject a stub adapter:

      setup do
        Application.put_env(:symphony_elixir, :tracker_adapters, %{
          "test" => MyApp.Tracker.TestStub
        })
        on_exit(fn -> Application.delete_env(:symphony_elixir, :tracker_adapters) end)
      end
  """

  @default_adapters %{
    "linear" => SymphonyElixir.Tracker.Linear.Adapter,
    "tapd" => SymphonyElixir.Tracker.Tapd.Adapter,
    "memory" => SymphonyElixir.Tracker.Memory
  }

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
              "Unknown tracker kind: #{inspect(kind)}. Supported: #{inspect(supported_kinds())}"

      adapter ->
        adapter
    end
  end

  @spec adapters() :: %{optional(String.t()) => module()}
  def adapters do
    overrides =
      :symphony_elixir
      |> Application.get_env(:tracker_adapters, %{})
      |> normalize_adapters()

    Map.merge(@default_adapters, overrides)
  end

  defp normalize_adapters(adapters) when is_map(adapters), do: adapters

  defp normalize_adapters(adapters) when is_list(adapters) do
    Map.new(adapters, fn
      {kind, adapter} -> {to_string(kind), adapter}
    end)
  end

  defp normalize_adapters(_adapters), do: %{}
end

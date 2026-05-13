defmodule SymphonyElixir.Observability.LogFile.RuntimeConfig do
  @moduledoc false

  alias SymphonyElixir.Observability.LogFile.PathConfig

  @default_max_bytes 10 * 1024 * 1024
  @default_max_files 5
  @default_observability %{
    file_enabled: true,
    console_enabled: false,
    log_format: :json
  }

  @type observability :: %{
          required(:file_enabled) => boolean(),
          required(:console_enabled) => boolean(),
          required(:log_format) => :json | :text
        }

  @type t :: %{
          required(:path) => Path.t(),
          required(:max_bytes) => integer(),
          required(:max_files) => integer(),
          required(:observability) => observability()
        }

  @spec load() :: t()
  def load do
    %{
      path: configured_path(),
      max_bytes: configured_max_bytes(),
      max_files: configured_max_files(),
      observability:
        Application.get_env(:symphony_elixir, :observability, %{})
        |> normalize_observability()
    }
  end

  @spec load_from_observability(map() | struct()) :: t()
  def load_from_observability(observability) do
    %{
      path: configured_path(),
      max_bytes: configured_max_bytes(),
      max_files: configured_max_files(),
      observability: normalize_observability(observability)
    }
  end

  defp configured_path do
    Application.get_env(:symphony_elixir, :log_file, PathConfig.default_log_file())
  end

  defp configured_max_bytes do
    Application.get_env(:symphony_elixir, :log_file_max_bytes, @default_max_bytes)
  end

  defp configured_max_files do
    Application.get_env(:symphony_elixir, :log_file_max_files, @default_max_files)
  end

  defp normalize_observability(observability) when is_struct(observability) do
    observability
    |> Map.from_struct()
    |> normalize_observability()
  end

  defp normalize_observability(observability) when is_map(observability) do
    %{
      file_enabled:
        normalize_boolean(
          fetch_observability_value(observability, :file_enabled),
          @default_observability.file_enabled
        ),
      console_enabled:
        normalize_boolean(
          fetch_observability_value(observability, :console_enabled),
          @default_observability.console_enabled
        ),
      log_format: normalize_log_format(fetch_observability_value(observability, :log_format))
    }
  end

  defp normalize_observability(_observability), do: @default_observability

  defp fetch_observability_value(map, key) when is_map(map) do
    cond do
      Map.has_key?(map, key) ->
        Map.get(map, key)

      Map.has_key?(map, Atom.to_string(key)) ->
        Map.get(map, Atom.to_string(key))

      true ->
        nil
    end
  end

  defp normalize_boolean(value, _default) when is_boolean(value), do: value
  defp normalize_boolean(nil, default), do: default
  defp normalize_boolean(_other, default), do: default

  defp normalize_log_format(nil), do: @default_observability.log_format
  defp normalize_log_format(value) when value in [:json, "json", "json_lines", "jsonl"], do: :json
  defp normalize_log_format(value) when value in [:text, "text"], do: :text
  defp normalize_log_format(_value), do: @default_observability.log_format
end

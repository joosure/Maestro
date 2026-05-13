defmodule SymphonyElixir.Agent.Runtime.CommandSpec do
  @moduledoc false

  @type t :: %__MODULE__{
          argv: [String.t()] | nil,
          command: String.t() | nil,
          env: map(),
          cwd: Path.t() | nil,
          metadata: map()
        }

  defstruct argv: nil,
            command: nil,
            env: %{},
            cwd: nil,
            metadata: %{}

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      argv: normalize_argv(value(attrs, :argv) || value(attrs, :command_argv)),
      command: normalize_optional_string(value(attrs, :command)),
      env: normalize_env(value(attrs, :env)),
      cwd: normalize_optional_string(value(attrs, :cwd)),
      metadata: normalize_metadata(value(attrs, :metadata))
    }
  end

  @spec command_summary(t()) :: map()
  def command_summary(%__MODULE__{argv: [command | args]}) do
    %{shape: "command_argv", command: command, argc: length(args) + 1}
  end

  def command_summary(%__MODULE__{command: command}) when is_binary(command) do
    %{shape: "command", command: command}
  end

  def command_summary(%__MODULE__{}), do: %{shape: "unset"}

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp normalize_argv(argv) when is_list(argv) do
    Enum.map(argv, &to_string/1)
  end

  defp normalize_argv(_argv), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil

  defp normalize_env(env) when is_map(env), do: env
  defp normalize_env(_env), do: %{}

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}
end

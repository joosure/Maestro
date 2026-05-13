defmodule SymphonyElixir.AgentProvider.SettingsNormalizer do
  @moduledoc false

  import Ecto.Changeset

  alias SymphonyElixir.Agent.Runtime.Environment
  alias SymphonyElixir.Config.InputNormalizer

  @invalid_command_chars ["\n", "\r", <<0>>]
  @env_name_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @spec option_value(map(), String.t(), term()) :: term()
  def option_value(options, field, default_value) when is_map(options) and is_binary(field),
    do: Map.get(options, field, default_value)

  @spec command_config(map(), [String.t()]) :: {String.t() | nil, [String.t()] | nil}
  def command_config(options, default_command_argv) when is_map(options) and is_list(default_command_argv) do
    command = option_value(options, "command", nil)
    command_argv = option_value(options, "command_argv", nil)

    cond do
      command_argv_present?(command_argv) -> {nil, command_argv}
      command_present?(command) -> {command, nil}
      true -> {nil, default_command_argv}
    end
  end

  @spec validate_command_choice(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_command_choice(changeset) do
    command = get_field(changeset, :command)
    command_argv = get_field(changeset, :command_argv)

    if command_present?(command) and command_argv_present?(command_argv) do
      add_error(changeset, :command, "must not be set when command_argv is set")
    else
      changeset
    end
  end

  @spec validate_command(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_command(changeset) do
    validate_change(changeset, :command, fn :command, command ->
      cond do
        is_nil(command) ->
          []

        not is_binary(command) ->
          [command: "must be a string"]

        String.trim(command) == "" ->
          [command: "can't be blank"]

        String.contains?(command, @invalid_command_chars) ->
          [command: "must not contain newline, carriage return, or NUL bytes"]

        true ->
          []
      end
    end)
  end

  @spec validate_command_argv(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_command_argv(changeset) do
    validate_change(changeset, :command_argv, fn :command_argv, argv ->
      cond do
        is_nil(argv) ->
          []

        not is_list(argv) ->
          [command_argv: "must be a list of strings"]

        argv == [] ->
          [command_argv: "must not be empty"]

        true ->
          command_argv_errors(argv)
      end
    end)
  end

  @spec validate_env(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_env(changeset) do
    validate_change(changeset, :env, fn :env, env ->
      cond do
        is_nil(env) ->
          []

        not is_map(env) ->
          [env: "must be a map"]

        true ->
          env_errors(env)
      end
    end)
  end

  @spec validate_telemetry(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_telemetry(changeset) do
    validate_change(changeset, :telemetry, fn :telemetry, telemetry ->
      case Environment.validate_telemetry(telemetry) do
        :ok -> []
        {:error, message} -> [telemetry: message]
      end
    end)
  end

  @spec validate_supported_options(map(), [String.t()], String.t()) :: :ok | {:error, term()}
  def validate_supported_options(options, supported_options, provider)
      when is_map(options) and is_list(supported_options) and is_binary(provider) do
    unknown_options =
      options
      |> Map.keys()
      |> Enum.reject(&(&1 in supported_options))

    case unknown_options do
      [] -> :ok
      _options -> {:error, {:unsupported_agent_provider_options, provider, Enum.sort(unknown_options)}}
    end
  end

  @spec normalize_env(term()) :: map()
  def normalize_env(env) when is_map(env) do
    env
    |> InputNormalizer.normalize_keys()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, key, normalize_env_value(value))
    end)
  end

  def normalize_env(_env), do: %{}

  @spec normalize_telemetry(term()) :: map()
  def normalize_telemetry(telemetry), do: Environment.normalize_telemetry(telemetry)

  @spec normalize_optional_string(term()) :: String.t() | nil
  def normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize_optional_string(_value), do: nil

  defp command_argv_errors(argv) when is_list(argv) do
    argv
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} ->
      cond do
        not is_binary(entry) ->
          [command_argv: "entry #{index} must be a string"]

        String.trim(entry) == "" ->
          [command_argv: "entry #{index} can't be blank"]

        String.contains?(entry, @invalid_command_chars) ->
          [command_argv: "entry #{index} must not contain newline, carriage return, or NUL bytes"]

        true ->
          []
      end
    end)
  end

  defp env_errors(env) when is_map(env) do
    Enum.flat_map(env, fn
      {key, value} when is_binary(key) and (is_binary(value) or is_nil(value)) ->
        if valid_env_name?(key), do: [], else: [env: "contains invalid environment variable name #{inspect(key)}"]

      {key, _value} ->
        [env: "entry #{inspect(key)} must be a string or nil value"]
    end)
  end

  defp normalize_env_value(nil), do: nil
  defp normalize_env_value(value) when is_binary(value), do: InputNormalizer.resolve_optional_string_setting(value)
  defp normalize_env_value(value), do: value

  defp valid_env_name?(key) when is_binary(key), do: Regex.match?(@env_name_pattern, key)
  defp command_present?(command), do: is_binary(command) and String.trim(command) != ""
  defp command_argv_present?(argv), do: is_list(argv) and argv != []
end

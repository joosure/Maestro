defmodule SymphonyElixir.AgentProvider.OpenCode.Settings do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.AgentProvider.SettingsNormalizer
  alias SymphonyElixir.Config.InputNormalizer

  @primary_key false
  @provider "opencode"
  @supported_options ~w(command command_argv env prompt_transport agent model variant telemetry credential_ref turn_timeout_ms read_timeout_ms stall_timeout_ms)
  @supported_variants ~w(low medium high max)
  @default_command_argv ["opencode", "serve", "--hostname", "127.0.0.1", "--port", "0"]
  @default_prompt_transport "http_sse"

  @type t :: %__MODULE__{
          command: String.t() | nil,
          command_argv: [String.t()] | nil,
          env: map(),
          prompt_transport: String.t(),
          agent: String.t(),
          model: String.t() | nil,
          variant: String.t() | nil,
          telemetry: map(),
          credential_ref: String.t() | nil,
          turn_timeout_ms: pos_integer(),
          read_timeout_ms: pos_integer(),
          stall_timeout_ms: non_neg_integer()
        }

  embedded_schema do
    field(:command, :string)
    field(:command_argv, {:array, :string})
    field(:env, :map, default: %{})
    field(:prompt_transport, :string, default: @default_prompt_transport)
    field(:agent, :string, default: "build")
    field(:model, :string)
    field(:variant, :string)
    field(:telemetry, :map, default: %{})
    field(:credential_ref, :string)
    field(:turn_timeout_ms, :integer, default: 3_600_000)
    field(:read_timeout_ms, :integer, default: 5_000)
    field(:stall_timeout_ms, :integer, default: 300_000)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(
      attrs,
      [
        :command,
        :command_argv,
        :env,
        :prompt_transport,
        :agent,
        :model,
        :variant,
        :telemetry,
        :credential_ref,
        :turn_timeout_ms,
        :read_timeout_ms,
        :stall_timeout_ms
      ],
      empty_values: []
    )
    |> SettingsNormalizer.validate_command_choice()
    |> SettingsNormalizer.validate_command()
    |> SettingsNormalizer.validate_command_argv()
    |> SettingsNormalizer.validate_env()
    |> SettingsNormalizer.validate_telemetry()
    |> update_change(:model, &SettingsNormalizer.normalize_optional_string/1)
    |> update_change(:agent, &SettingsNormalizer.normalize_optional_string/1)
    |> update_change(:variant, &SettingsNormalizer.normalize_optional_string/1)
    |> update_change(:credential_ref, &SettingsNormalizer.normalize_optional_string/1)
    |> validate_required([:agent])
    |> validate_inclusion(:prompt_transport, [@default_prompt_transport])
    |> validate_model()
    |> validate_variant()
    |> validate_number(:turn_timeout_ms, greater_than: 0)
    |> validate_number(:read_timeout_ms, greater_than: 0)
    |> validate_number(:stall_timeout_ms, greater_than_or_equal_to: 0)
  end

  @spec validate_options(map()) :: :ok | {:error, Ecto.Changeset.t() | term()}
  def validate_options(options) when is_map(options) do
    options = InputNormalizer.normalize_keys(options)

    with :ok <- SettingsNormalizer.validate_supported_options(options, @supported_options, @provider) do
      case changeset(%__MODULE__{}, options) |> apply_action(:validate) do
        {:ok, _settings} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @spec finalize_options(map()) :: map()
  def finalize_options(options) when is_map(options) do
    options = InputNormalizer.normalize_keys(options)
    defaults = %__MODULE__{}
    {command, command_argv} = SettingsNormalizer.command_config(options, @default_command_argv)

    %{
      "command" => command,
      "command_argv" => command_argv,
      "env" =>
        options
        |> SettingsNormalizer.option_value("env", defaults.env)
        |> SettingsNormalizer.normalize_env(),
      "prompt_transport" => SettingsNormalizer.option_value(options, "prompt_transport", defaults.prompt_transport),
      "agent" =>
        options
        |> SettingsNormalizer.option_value("agent", defaults.agent)
        |> SettingsNormalizer.normalize_optional_string(),
      "model" =>
        options
        |> SettingsNormalizer.option_value("model", defaults.model)
        |> SettingsNormalizer.normalize_optional_string(),
      "variant" =>
        options
        |> SettingsNormalizer.option_value("variant", defaults.variant)
        |> SettingsNormalizer.normalize_optional_string(),
      "telemetry" =>
        options
        |> SettingsNormalizer.option_value("telemetry", defaults.telemetry)
        |> SettingsNormalizer.normalize_telemetry(),
      "credential_ref" =>
        options
        |> SettingsNormalizer.option_value("credential_ref", defaults.credential_ref)
        |> SettingsNormalizer.normalize_optional_string(),
      "turn_timeout_ms" => SettingsNormalizer.option_value(options, "turn_timeout_ms", defaults.turn_timeout_ms),
      "read_timeout_ms" => SettingsNormalizer.option_value(options, "read_timeout_ms", defaults.read_timeout_ms),
      "stall_timeout_ms" => SettingsNormalizer.option_value(options, "stall_timeout_ms", defaults.stall_timeout_ms)
    }
  end

  @spec defaults() :: map()
  def defaults, do: finalize_options(%{})

  @spec from_options(map()) :: t()
  def from_options(options) when is_map(options) do
    options = finalize_options(options)

    %__MODULE__{
      command: Map.get(options, "command"),
      command_argv: Map.get(options, "command_argv"),
      env: Map.get(options, "env", %{}),
      prompt_transport: Map.get(options, "prompt_transport"),
      agent: Map.get(options, "agent"),
      model: Map.get(options, "model"),
      variant: Map.get(options, "variant"),
      telemetry: Map.get(options, "telemetry", %{}),
      credential_ref: Map.get(options, "credential_ref"),
      turn_timeout_ms: Map.get(options, "turn_timeout_ms"),
      read_timeout_ms: Map.get(options, "read_timeout_ms"),
      stall_timeout_ms: Map.get(options, "stall_timeout_ms")
    }
  end

  @spec command_argv(t()) :: [String.t()] | nil
  def command_argv(%__MODULE__{command_argv: argv}) when is_list(argv), do: argv
  def command_argv(%__MODULE__{}), do: nil

  defp validate_model(changeset) do
    validate_change(changeset, :model, fn :model, value ->
      cond do
        is_nil(value) ->
          []

        is_binary(value) and String.contains?(value, "/") ->
          []

        true ->
          [model: "must use provider/model format"]
      end
    end)
  end

  defp validate_variant(changeset) do
    validate_change(changeset, :variant, fn :variant, value ->
      cond do
        is_nil(value) -> []
        value in @supported_variants -> []
        true -> [variant: "must be one of #{Enum.join(@supported_variants, ", ")}"]
      end
    end)
  end
end

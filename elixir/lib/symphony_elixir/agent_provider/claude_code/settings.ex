defmodule SymphonyElixir.AgentProvider.ClaudeCode.Settings do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.AgentProvider.SettingsNormalizer
  alias SymphonyElixir.Config.InputNormalizer

  @primary_key false
  @provider Kinds.claude_code()
  @supported_options ~w(command command_argv env prompt_transport model effort permission_mode telemetry credential_ref quota_probe turn_timeout_ms read_timeout_ms stall_timeout_ms)
  @supported_efforts ~w(low medium high xhigh max)
  @permission_modes ~w(acceptEdits auto bypassPermissions default dontAsk plan)
  @default_command_argv ["claude"]
  @default_prompt_transport "stream_json"

  @type t :: %__MODULE__{
          command: String.t() | nil,
          command_argv: [String.t()] | nil,
          env: map(),
          prompt_transport: String.t(),
          model: String.t() | nil,
          effort: String.t() | nil,
          permission_mode: String.t(),
          telemetry: map(),
          credential_ref: String.t() | nil,
          quota_probe: map(),
          turn_timeout_ms: pos_integer(),
          read_timeout_ms: pos_integer(),
          stall_timeout_ms: non_neg_integer()
        }

  embedded_schema do
    field(:command, :string)
    field(:command_argv, {:array, :string})
    field(:env, :map, default: %{})
    field(:prompt_transport, :string, default: @default_prompt_transport)
    field(:model, :string)
    field(:effort, :string)
    field(:permission_mode, :string, default: "bypassPermissions")
    field(:telemetry, :map, default: %{})
    field(:credential_ref, :string)
    field(:quota_probe, :map, default: %{})
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
        :model,
        :effort,
        :permission_mode,
        :telemetry,
        :credential_ref,
        :quota_probe,
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
    |> validate_quota_probe()
    |> update_change(:model, &SettingsNormalizer.normalize_optional_string/1)
    |> update_change(:effort, &SettingsNormalizer.normalize_optional_string/1)
    |> update_change(:credential_ref, &SettingsNormalizer.normalize_optional_string/1)
    |> update_change(:permission_mode, &SettingsNormalizer.normalize_optional_string/1)
    |> validate_inclusion(:prompt_transport, [@default_prompt_transport])
    |> validate_effort()
    |> validate_inclusion(:permission_mode, @permission_modes)
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
      "model" =>
        options
        |> SettingsNormalizer.option_value("model", defaults.model)
        |> SettingsNormalizer.normalize_optional_string(),
      "effort" =>
        options
        |> SettingsNormalizer.option_value("effort", defaults.effort)
        |> SettingsNormalizer.normalize_optional_string(),
      "permission_mode" => SettingsNormalizer.option_value(options, "permission_mode", defaults.permission_mode),
      "telemetry" =>
        options
        |> SettingsNormalizer.option_value("telemetry", defaults.telemetry)
        |> SettingsNormalizer.normalize_telemetry(),
      "credential_ref" =>
        options
        |> SettingsNormalizer.option_value("credential_ref", defaults.credential_ref)
        |> SettingsNormalizer.normalize_optional_string(),
      "quota_probe" =>
        options
        |> SettingsNormalizer.option_value("quota_probe", defaults.quota_probe)
        |> normalize_quota_probe(),
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
      model: Map.get(options, "model"),
      effort: Map.get(options, "effort"),
      permission_mode: Map.get(options, "permission_mode"),
      telemetry: Map.get(options, "telemetry", %{}),
      credential_ref: Map.get(options, "credential_ref"),
      quota_probe: Map.get(options, "quota_probe", %{}),
      turn_timeout_ms: Map.get(options, "turn_timeout_ms"),
      read_timeout_ms: Map.get(options, "read_timeout_ms"),
      stall_timeout_ms: Map.get(options, "stall_timeout_ms")
    }
  end

  @spec command_argv(t()) :: [String.t()] | nil
  def command_argv(%__MODULE__{command_argv: argv}) when is_list(argv), do: argv
  def command_argv(%__MODULE__{}), do: nil

  defp validate_quota_probe(changeset) do
    validate_change(changeset, :quota_probe, fn :quota_probe, quota_probe ->
      cond do
        is_nil(quota_probe) -> []
        is_map(quota_probe) -> quota_probe_errors(quota_probe)
        true -> [quota_probe: "must be a map"]
      end
    end)
  end

  defp quota_probe_errors(quota_probe) when is_map(quota_probe) do
    Enum.flat_map(quota_probe, fn
      {key, value} when key in ["model", :model] and (is_binary(value) or is_nil(value)) -> []
      {key, value} when key in ["timeout_ms", :timeout_ms] and is_integer(value) and value > 0 -> []
      {key, _value} -> [quota_probe: "contains unsupported or invalid option #{inspect(key)}"]
    end)
  end

  defp validate_effort(changeset) do
    validate_change(changeset, :effort, fn :effort, value ->
      cond do
        is_nil(value) -> []
        value in @supported_efforts -> []
        true -> [effort: "must be one of #{Enum.join(@supported_efforts, ", ")}"]
      end
    end)
  end

  defp normalize_quota_probe(quota_probe) when is_map(quota_probe) do
    quota_probe
    |> InputNormalizer.normalize_keys()
    |> Enum.reduce(%{}, fn
      {"model", value}, acc -> maybe_put(acc, "model", SettingsNormalizer.normalize_optional_string(value))
      {"timeout_ms", value}, acc when is_integer(value) and value > 0 -> Map.put(acc, "timeout_ms", value)
      {_key, _value}, acc -> acc
    end)
  end

  defp normalize_quota_probe(_quota_probe), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

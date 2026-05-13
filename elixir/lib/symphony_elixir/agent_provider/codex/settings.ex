defmodule SymphonyElixir.AgentProvider.Codex.Settings do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.Config
  alias SymphonyElixir.Config.InputNormalizer
  alias SymphonyElixir.Config.Schema

  @primary_key false
  @supported_options ~w(command command_argv prompt_transport approval_policy thread_sandbox turn_sandbox_policy credential_ref turn_timeout_ms read_timeout_ms stall_timeout_ms)
  @invalid_command_chars ["\n", "\r", <<0>>]

  @type t :: %__MODULE__{
          command: String.t() | nil,
          command_argv: [String.t()] | nil,
          prompt_transport: String.t() | nil,
          approval_policy: String.t() | map() | nil,
          thread_sandbox: String.t() | nil,
          turn_sandbox_policy: map() | nil,
          credential_ref: String.t() | nil,
          turn_timeout_ms: pos_integer() | nil,
          read_timeout_ms: pos_integer() | nil,
          stall_timeout_ms: non_neg_integer() | nil
        }

  defmodule StringOrMap do
    @moduledoc false
    @behaviour Ecto.Type

    @spec type() :: :map
    def type, do: :map

    @spec embed_as(term()) :: :self
    def embed_as(_format), do: :self

    @spec equal?(term(), term()) :: boolean()
    def equal?(left, right), do: left == right

    @spec cast(term()) :: {:ok, String.t() | map()} | :error
    def cast(value) when is_binary(value) or is_map(value), do: {:ok, value}
    def cast(_value), do: :error

    @spec load(term()) :: {:ok, String.t() | map()} | :error
    def load(value) when is_binary(value) or is_map(value), do: {:ok, value}
    def load(_value), do: :error

    @spec dump(term()) :: {:ok, String.t() | map()} | :error
    def dump(value) when is_binary(value) or is_map(value), do: {:ok, value}
    def dump(_value), do: :error
  end

  embedded_schema do
    field(:command, :string, default: "codex app-server")
    field(:command_argv, {:array, :string})
    field(:prompt_transport, :string, default: "json_rpc")

    field(:approval_policy, StringOrMap, default: "on-request")

    field(:thread_sandbox, :string, default: "workspace-write")
    field(:turn_sandbox_policy, :map)
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
        :prompt_transport,
        :approval_policy,
        :thread_sandbox,
        :turn_sandbox_policy,
        :credential_ref,
        :turn_timeout_ms,
        :read_timeout_ms,
        :stall_timeout_ms
      ],
      empty_values: []
    )
    |> validate_required([:command])
    |> validate_command()
    |> validate_command_argv()
    |> update_change(:credential_ref, &normalize_optional_string/1)
    |> validate_inclusion(:prompt_transport, ["json_rpc"])
    |> validate_number(:turn_timeout_ms, greater_than: 0)
    |> validate_number(:read_timeout_ms, greater_than: 0)
    |> validate_number(:stall_timeout_ms, greater_than_or_equal_to: 0)
  end

  @spec validate_options(map()) :: :ok | {:error, Ecto.Changeset.t() | term()}
  def validate_options(options) when is_map(options) do
    with :ok <- validate_supported_options(options) do
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

    %{
      "command" => option_value(options, "command", defaults.command),
      "command_argv" => option_value(options, "command_argv", defaults.command_argv),
      "prompt_transport" => option_value(options, "prompt_transport", defaults.prompt_transport),
      "approval_policy" =>
        options
        |> option_value("approval_policy", defaults.approval_policy)
        |> InputNormalizer.normalize_keys(),
      "thread_sandbox" => option_value(options, "thread_sandbox", defaults.thread_sandbox),
      "turn_sandbox_policy" =>
        options
        |> option_value("turn_sandbox_policy", defaults.turn_sandbox_policy)
        |> InputNormalizer.normalize_optional_map(),
      "credential_ref" => normalize_optional_string(option_value(options, "credential_ref", defaults.credential_ref)),
      "turn_timeout_ms" => option_value(options, "turn_timeout_ms", defaults.turn_timeout_ms),
      "read_timeout_ms" => option_value(options, "read_timeout_ms", defaults.read_timeout_ms),
      "stall_timeout_ms" => option_value(options, "stall_timeout_ms", defaults.stall_timeout_ms)
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
      prompt_transport: Map.get(options, "prompt_transport"),
      approval_policy: Map.get(options, "approval_policy"),
      thread_sandbox: Map.get(options, "thread_sandbox"),
      turn_sandbox_policy: Map.get(options, "turn_sandbox_policy"),
      credential_ref: Map.get(options, "credential_ref"),
      turn_timeout_ms: Map.get(options, "turn_timeout_ms"),
      read_timeout_ms: Map.get(options, "read_timeout_ms"),
      stall_timeout_ms: Map.get(options, "stall_timeout_ms")
    }
  end

  @spec command_argv(t()) :: [String.t()] | nil
  def command_argv(%__MODULE__{command_argv: argv}) when is_list(argv), do: argv
  def command_argv(%__MODULE__{}), do: nil

  @spec current!() :: t()
  def current! do
    options = Config.agent_provider_options()

    from_options(options)
  end

  @spec runtime_settings(Path.t() | nil, keyword()) ::
          {:ok,
           %{
             approval_policy: String.t() | map(),
             thread_sandbox: String.t(),
             turn_sandbox_policy: map()
           }}
          | {:error, term()}
  def runtime_settings(workspace \\ nil, opts \\ []) do
    runtime_settings_from(current!(), workspace, opts)
  end

  @spec runtime_settings_from(t(), Path.t() | nil, keyword()) ::
          {:ok,
           %{
             approval_policy: String.t() | map(),
             thread_sandbox: String.t(),
             turn_sandbox_policy: map()
           }}
          | {:error, term()}
  def runtime_settings_from(%__MODULE__{} = codex, workspace \\ nil, opts \\ []) do
    with {:ok, settings} <- runtime_config_settings(opts),
         {:ok, turn_sandbox_policy} <-
           Schema.resolve_runtime_turn_sandbox_policy(settings, workspace, opts) do
      {:ok,
       %{
         approval_policy: codex.approval_policy,
         thread_sandbox: codex.thread_sandbox,
         turn_sandbox_policy: turn_sandbox_policy
       }}
    end
  end

  defp runtime_config_settings(opts) when is_list(opts) do
    case Keyword.get(opts, :settings) do
      %Schema{} = settings -> {:ok, settings}
      nil -> Config.settings()
      settings -> {:error, {:invalid_runtime_settings, settings}}
    end
  end

  defp option_value(options, field, default_value) when is_map(options) and is_binary(field),
    do: Map.get(options, field, default_value)

  defp validate_command(changeset) do
    validate_change(changeset, :command, fn :command, command ->
      cond do
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

  defp validate_command_argv(changeset) do
    validate_change(changeset, :command_argv, fn :command_argv, argv ->
      cond do
        is_nil(argv) ->
          []

        not is_list(argv) ->
          [command_argv: "must be a list of strings"]

        argv == [] ->
          [command_argv: "must not be empty"]

        true ->
          argv_errors(argv)
      end
    end)
  end

  defp argv_errors(argv) when is_list(argv) do
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

  defp validate_supported_options(options) when is_map(options) do
    unknown_options =
      options
      |> InputNormalizer.normalize_keys()
      |> Map.keys()
      |> Enum.reject(&(&1 in @supported_options))

    case unknown_options do
      [] -> :ok
      _ -> {:error, {:unsupported_agent_provider_options, "codex", Enum.sort(unknown_options)}}
    end
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil
end

defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.Settings do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.AgentProvider.CodeBuddyCode.CredentialEnv
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.AgentProvider.SettingsNormalizer
  alias SymphonyElixir.Config.InputNormalizer

  @primary_key false
  @provider Kinds.codebuddy_code()
  @supported_options ~w(transport command command_argv env model agent permission_mode allowed_tools disallowed_tools acp mcp plugin http telemetry credential_ref quota_probe turn_timeout_ms read_timeout_ms stall_timeout_ms)
  @permission_modes ~w(restricted planned_tools provider_default bypass_permissions)
  @transports ~w(acp_stdio acp_http)
  @default_command_argv ["codebuddy"]
  @default_transport "acp_stdio"
  @default_acp_endpoint_path "/api/v1/acp"
  @default_http_bind_host "127.0.0.1"
  @default_http_port :auto
  @default_http_allowlist ["health"]
  @auxiliary_http_allowlist_ids ~w(auth_status health version metrics_summary session_stats plugin_inventory)
  @default_mcp_server_name "symphony_dynamic_tools"
  @managed_credential_env_keys [
    CredentialEnv.api_key_env(),
    CredentialEnv.auth_token_env(),
    CredentialEnv.api_key_disabled_env(),
    CredentialEnv.base_url_env(),
    CredentialEnv.internet_environment_env()
  ]

  @type t :: %__MODULE__{
          transport: String.t(),
          command: String.t() | nil,
          command_argv: [String.t()] | nil,
          env: map(),
          model: String.t() | nil,
          agent: String.t() | nil,
          permission_mode: String.t(),
          allowed_tools: [String.t()],
          disallowed_tools: [String.t()],
          acp: map(),
          mcp: map(),
          plugin: map(),
          http: map(),
          telemetry: map(),
          credential_ref: String.t() | nil,
          quota_probe: map(),
          turn_timeout_ms: pos_integer(),
          read_timeout_ms: pos_integer(),
          stall_timeout_ms: non_neg_integer()
        }

  embedded_schema do
    field(:transport, :string, default: @default_transport)
    field(:command, :string)
    field(:command_argv, {:array, :string})
    field(:env, :map, default: %{})
    field(:model, :string)
    field(:agent, :string)
    field(:permission_mode, :string, default: "restricted")
    field(:allowed_tools, {:array, :string}, default: [])
    field(:disallowed_tools, {:array, :string}, default: [])
    field(:acp, :map, default: %{})
    field(:mcp, :map, default: %{"enabled" => false})
    field(:plugin, :map, default: %{"enabled" => false})
    field(:http, :map, default: %{"enabled" => false, "mode" => "auxiliary"})
    field(:telemetry, :map, default: %{"enabled" => false})
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
        :transport,
        :command,
        :command_argv,
        :env,
        :model,
        :agent,
        :permission_mode,
        :allowed_tools,
        :disallowed_tools,
        :acp,
        :mcp,
        :plugin,
        :http,
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
    |> update_change(:model, &SettingsNormalizer.normalize_optional_string/1)
    |> update_change(:agent, &SettingsNormalizer.normalize_optional_string/1)
    |> update_change(:credential_ref, &SettingsNormalizer.normalize_optional_string/1)
    |> update_change(:permission_mode, &SettingsNormalizer.normalize_optional_string/1)
    |> validate_inclusion(:transport, @transports)
    |> validate_inclusion(:permission_mode, @permission_modes)
    |> validate_string_list(:allowed_tools)
    |> validate_string_list(:disallowed_tools)
    |> validate_nested_maps()
    |> validate_current_baseline_gates()
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
      "transport" => SettingsNormalizer.option_value(options, "transport", defaults.transport),
      "command" => command,
      "command_argv" => command_argv,
      "env" =>
        options
        |> SettingsNormalizer.option_value("env", defaults.env)
        |> SettingsNormalizer.normalize_env(),
      "model" =>
        options
        |> SettingsNormalizer.option_value("model", defaults.model)
        |> SettingsNormalizer.normalize_optional_string(),
      "agent" =>
        options
        |> SettingsNormalizer.option_value("agent", defaults.agent)
        |> SettingsNormalizer.normalize_optional_string(),
      "permission_mode" => SettingsNormalizer.option_value(options, "permission_mode", defaults.permission_mode),
      "allowed_tools" => normalize_string_list(SettingsNormalizer.option_value(options, "allowed_tools", defaults.allowed_tools)),
      "disallowed_tools" => normalize_string_list(SettingsNormalizer.option_value(options, "disallowed_tools", defaults.disallowed_tools)),
      "acp" => normalize_map(SettingsNormalizer.option_value(options, "acp", defaults.acp)),
      "mcp" => normalize_map(SettingsNormalizer.option_value(options, "mcp", defaults.mcp)),
      "plugin" => normalize_map(SettingsNormalizer.option_value(options, "plugin", defaults.plugin)),
      "http" => normalize_map(SettingsNormalizer.option_value(options, "http", defaults.http)),
      "telemetry" => normalize_map(SettingsNormalizer.option_value(options, "telemetry", defaults.telemetry)),
      "credential_ref" =>
        options
        |> SettingsNormalizer.option_value("credential_ref", defaults.credential_ref)
        |> SettingsNormalizer.normalize_optional_string(),
      "quota_probe" => normalize_map(SettingsNormalizer.option_value(options, "quota_probe", defaults.quota_probe)),
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
      transport: Map.get(options, "transport"),
      command: Map.get(options, "command"),
      command_argv: Map.get(options, "command_argv"),
      env: Map.get(options, "env", %{}),
      model: Map.get(options, "model"),
      agent: Map.get(options, "agent"),
      permission_mode: Map.get(options, "permission_mode"),
      allowed_tools: Map.get(options, "allowed_tools", []),
      disallowed_tools: Map.get(options, "disallowed_tools", []),
      acp: Map.get(options, "acp", %{}),
      mcp: Map.get(options, "mcp", %{}),
      plugin: Map.get(options, "plugin", %{}),
      http: Map.get(options, "http", %{}),
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

  @spec default_mcp_server_name() :: String.t()
  def default_mcp_server_name, do: @default_mcp_server_name

  @spec mcp_enabled?(t()) :: boolean()
  def mcp_enabled?(%__MODULE__{mcp: mcp}) when is_map(mcp) do
    Map.get(InputNormalizer.normalize_keys(mcp), "enabled") == true
  end

  def mcp_enabled?(%__MODULE__{}), do: false

  @spec mcp_server_name(t()) :: String.t()
  def mcp_server_name(%__MODULE__{mcp: mcp}) when is_map(mcp) do
    case Map.get(InputNormalizer.normalize_keys(mcp), "server_name") do
      value when is_binary(value) and value != "" -> value
      _value -> @default_mcp_server_name
    end
  end

  def mcp_server_name(%__MODULE__{}), do: @default_mcp_server_name

  @spec acp_endpoint_path(t()) :: String.t()
  def acp_endpoint_path(%__MODULE__{acp: acp}) when is_map(acp) do
    case Map.get(InputNormalizer.normalize_keys(acp), "endpoint_path") do
      value when is_binary(value) and value != "" -> value
      _value -> @default_acp_endpoint_path
    end
  end

  def acp_endpoint_path(%__MODULE__{}), do: @default_acp_endpoint_path

  @spec http_bind_host(t()) :: String.t()
  def http_bind_host(%__MODULE__{http: http}) when is_map(http) do
    case Map.get(InputNormalizer.normalize_keys(http), "bind_host") do
      value when is_binary(value) and value != "" -> value
      _value -> @default_http_bind_host
    end
  end

  def http_bind_host(%__MODULE__{}), do: @default_http_bind_host

  @spec http_port(t()) :: pos_integer() | :auto
  def http_port(%__MODULE__{http: http}) when is_map(http) do
    case Map.get(InputNormalizer.normalize_keys(http), "port") do
      value when is_integer(value) and value > 0 and value <= 65_535 -> value
      "auto" -> :auto
      _value -> @default_http_port
    end
  end

  def http_port(%__MODULE__{}), do: @default_http_port

  @spec http_enabled?(t()) :: boolean()
  def http_enabled?(%__MODULE__{http: http}) when is_map(http) do
    Map.get(InputNormalizer.normalize_keys(http), "enabled") == true
  end

  def http_enabled?(%__MODULE__{}), do: false

  @spec http_auth_mode(t()) :: String.t()
  def http_auth_mode(%__MODULE__{http: http}) when is_map(http) do
    case Map.get(InputNormalizer.normalize_keys(http), "auth_mode") do
      mode when mode in ~w(provider_required runtime_gateway none_for_loopback_smoke) -> mode
      _mode -> "provider_required"
    end
  end

  def http_auth_mode(%__MODULE__{}), do: "provider_required"

  @spec http_gateway_auth_ref(t()) :: String.t() | nil
  def http_gateway_auth_ref(%__MODULE__{http: http}) when is_map(http) do
    http
    |> InputNormalizer.normalize_keys()
    |> Map.get("gateway_auth_ref")
    |> SettingsNormalizer.normalize_optional_string()
  end

  def http_gateway_auth_ref(%__MODULE__{}), do: nil

  @spec http_allowlist(t()) :: [String.t()]
  def http_allowlist(%__MODULE__{http: http}) when is_map(http) do
    case Map.get(InputNormalizer.normalize_keys(http), "allowlist") do
      values when is_list(values) ->
        values
        |> Enum.map(&to_string/1)
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(&1 in @auxiliary_http_allowlist_ids))
        |> case do
          [] -> @default_http_allowlist
          identifiers -> Enum.uniq(identifiers)
        end

      _value ->
        @default_http_allowlist
    end
  end

  def http_allowlist(%__MODULE__{}), do: @default_http_allowlist

  defp validate_string_list(changeset, field) when is_atom(field) do
    validate_change(changeset, field, fn ^field, values ->
      cond do
        is_nil(values) -> []
        not is_list(values) -> [{field, "must be a list of strings"}]
        true -> string_list_errors(field, values)
      end
    end)
  end

  defp string_list_errors(field, values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {value, index} when is_binary(value) ->
        if String.trim(value) == "", do: [{field, "entry #{index} can't be blank"}], else: []

      {_value, index} ->
        [{field, "entry #{index} must be a string"}]
    end)
  end

  defp validate_nested_maps(changeset) do
    changeset
    |> validate_map_schema(:acp, ~w(endpoint_path handshake_timeout_ms cancel_timeout_ms client_file_proxy client_terminal_proxy))
    |> validate_map_schema(:mcp, ~w(enabled server_name discovery approve_generated_server allow_project_config_merge))
    |> validate_map_schema(:plugin, ~w(enabled discovery allow_repository_plugins approve_generated_plugin))
    |> validate_map_schema(:http, ~w(enabled mode required bind_host port base_url auth_mode gateway_auth_ref allowlist))
    |> validate_map_schema(:telemetry, ~w(enabled endpoint headers capture_raw_traces))
    |> validate_map_schema(:quota_probe, ~w())
  end

  defp validate_map_schema(changeset, field, allowed_keys) do
    validate_change(changeset, field, fn ^field, value ->
      cond do
        is_nil(value) ->
          []

        not is_map(value) ->
          [{field, "must be a map"}]

        true ->
          nested_map_errors(field, InputNormalizer.normalize_keys(value), allowed_keys)
      end
    end)
  end

  defp nested_map_errors(field, value, allowed_keys) do
    unknown =
      value
      |> Map.keys()
      |> Enum.reject(&(&1 in allowed_keys))
      |> Enum.sort()

    case unknown do
      [] -> nested_value_errors(field, value)
      keys -> [{field, "contains unsupported option(s): #{Enum.join(keys, ", ")}"}]
    end
  end

  defp nested_value_errors(:acp, value) do
    []
    |> maybe_error(:acp, value, "endpoint_path", &absolute_path_or_nil?/1, "endpoint_path must be an absolute path string")
    |> maybe_error(:acp, value, "handshake_timeout_ms", &positive_integer_or_nil?/1, "handshake_timeout_ms must be a positive integer")
    |> maybe_error(:acp, value, "cancel_timeout_ms", &positive_integer_or_nil?/1, "cancel_timeout_ms must be a positive integer")
    |> maybe_error(:acp, value, "client_file_proxy", &boolean_or_nil?/1, "client_file_proxy must be a boolean")
    |> maybe_error(:acp, value, "client_terminal_proxy", &boolean_or_nil?/1, "client_terminal_proxy must be a boolean")
  end

  defp nested_value_errors(:mcp, value) do
    []
    |> maybe_error(:mcp, value, "enabled", &boolean_or_nil?/1, "enabled must be a boolean")
    |> maybe_error(:mcp, value, "server_name", &mcp_server_name_or_nil?/1, "server_name must contain only letters, digits, underscores, or hyphens")
    |> maybe_error(:mcp, value, "discovery", &enum_or_nil?(&1, ~w(explicit_config project_pointer)), "discovery is unsupported")
    |> maybe_error(:mcp, value, "approve_generated_server", &boolean_or_nil?/1, "approve_generated_server must be a boolean")
    |> maybe_error(:mcp, value, "allow_project_config_merge", &boolean_or_nil?/1, "allow_project_config_merge must be a boolean")
  end

  defp nested_value_errors(:plugin, value) do
    []
    |> maybe_error(:plugin, value, "enabled", &boolean_or_nil?/1, "enabled must be a boolean")
    |> maybe_error(:plugin, value, "discovery", &enum_or_nil?(&1, ~w(explicit_dir project_pointer)), "discovery is unsupported")
    |> maybe_error(:plugin, value, "allow_repository_plugins", &boolean_or_nil?/1, "allow_repository_plugins must be a boolean")
    |> maybe_error(:plugin, value, "approve_generated_plugin", &boolean_or_nil?/1, "approve_generated_plugin must be a boolean")
  end

  defp nested_value_errors(:http, value) do
    []
    |> maybe_error(:http, value, "enabled", &boolean_or_nil?/1, "enabled must be a boolean")
    |> maybe_error(:http, value, "mode", &enum_or_nil?(&1, ~w(auxiliary)), "mode is unsupported")
    |> maybe_error(:http, value, "required", &boolean_or_nil?/1, "required must be a boolean")
    |> maybe_error(:http, value, "bind_host", &non_empty_string_or_nil?/1, "bind_host must be a non-empty string")
    |> maybe_error(:http, value, "port", &port_value_or_nil?/1, "port must be a positive integer or auto")
    |> maybe_error(:http, value, "base_url", &non_empty_string_or_nil?/1, "base_url must be a non-empty string")
    |> maybe_error(:http, value, "auth_mode", &enum_or_nil?(&1, ~w(provider_required runtime_gateway none_for_loopback_smoke)), "auth_mode is unsupported")
    |> maybe_error(:http, value, "gateway_auth_ref", &non_empty_string_or_nil?/1, "gateway_auth_ref must be a non-empty string")
    |> maybe_error(:http, value, "allowlist", &http_allowlist_or_nil?/1, "allowlist must contain supported auxiliary HTTP endpoint identifiers")
  end

  defp nested_value_errors(:telemetry, value) do
    []
    |> maybe_error(:telemetry, value, "enabled", &boolean_or_nil?/1, "enabled must be a boolean")
    |> maybe_error(:telemetry, value, "endpoint", &non_empty_string_or_nil?/1, "endpoint must be a non-empty string")
    |> maybe_error(:telemetry, value, "headers", &map_or_nil?/1, "headers must be a map")
    |> maybe_error(:telemetry, value, "capture_raw_traces", &boolean_or_nil?/1, "capture_raw_traces must be a boolean")
  end

  defp nested_value_errors(:quota_probe, value) when map_size(value) == 0, do: []
  defp nested_value_errors(:quota_probe, _value), do: [quota_probe: "is not supported for the current CodeBuddy baseline"]

  defp maybe_error(errors, field, map, key, validator, message) do
    if Map.has_key?(map, key) and not validator.(Map.get(map, key)) do
      [{field, message} | errors]
    else
      errors
    end
  end

  defp validate_current_baseline_gates(changeset) do
    changeset
    |> validate_managed_credential_env_isolation()
    |> validate_acp_http_phase_gate()
    |> validate_mcp_phase_gate()
    |> reject_enabled(:plugin, "CodeBuddy plugins are unsupported for the current codebuddy_code baseline")
    |> validate_auxiliary_http_phase_gate()
    |> reject_enabled(:telemetry, "telemetry is unsupported for the current codebuddy_code baseline")
    |> reject_enabled(:acp, "client_file_proxy", "ACP file proxy is unsupported for the current codebuddy_code baseline")
    |> reject_enabled(:acp, "client_terminal_proxy", "ACP terminal proxy is unsupported for the current codebuddy_code baseline")
  end

  defp validate_acp_http_phase_gate(changeset) do
    if get_field(changeset, :transport) == "acp_http" do
      http =
        changeset
        |> get_field(:http)
        |> normalize_map()

      changeset
      |> reject_acp_http_mcp()
      |> reject_non_loopback_bind_host(http)
      |> reject_http_required(http)
      |> reject_http_base_url(http)
      |> reject_http_gateway_auth(http)
      |> reject_http_auth_mode(http)
    else
      changeset
    end
  end

  defp reject_acp_http_mcp(changeset) do
    case get_field(changeset, :mcp) do
      %{} = map ->
        if Map.get(InputNormalizer.normalize_keys(map), "enabled") == true do
          add_error(changeset, :mcp, "MCP Dynamic Tools are unsupported over codebuddy_code acp_http Phase 3")
        else
          changeset
        end

      _value ->
        changeset
    end
  end

  defp reject_non_loopback_bind_host(changeset, http) do
    case Map.get(http, "bind_host") do
      nil -> changeset
      host when host in ["127.0.0.1", "localhost", "::1"] -> changeset
      host -> add_error(changeset, :http, "acp_http bind_host must be loopback-only, got #{host}")
    end
  end

  defp reject_http_required(changeset, http) do
    if Map.get(http, "required") == true do
      add_error(changeset, :http, "auxiliary HTTP required mode is unsupported for codebuddy_code Phase 3")
    else
      changeset
    end
  end

  defp reject_http_base_url(changeset, http) do
    case Map.get(http, "base_url") do
      nil -> changeset
      _value -> add_error(changeset, :http, "custom acp_http base_url is unsupported for codebuddy_code Phase 3")
    end
  end

  defp reject_http_gateway_auth(changeset, http) do
    case Map.get(http, "gateway_auth_ref") do
      nil ->
        changeset

      _value ->
        if Map.get(http, "enabled") == true and Map.get(http, "auth_mode") == "runtime_gateway" do
          changeset
        else
          add_error(changeset, :http, "gateway auth is supported only for enabled runtime_gateway auxiliary HTTP")
        end
    end
  end

  defp reject_http_auth_mode(changeset, http) do
    case Map.get(http, "auth_mode") do
      nil -> changeset
      "provider_required" -> changeset
      "none_for_loopback_smoke" -> changeset
      "runtime_gateway" -> reject_runtime_gateway_without_ref(changeset, http)
      mode -> add_error(changeset, :http, "acp_http auth_mode #{mode} is unsupported")
    end
  end

  defp reject_runtime_gateway_without_ref(changeset, http) do
    if Map.get(http, "enabled") == true and non_empty_string_or_nil?(Map.get(http, "gateway_auth_ref")) and not is_nil(Map.get(http, "gateway_auth_ref")) do
      changeset
    else
      add_error(changeset, :http, "runtime_gateway auxiliary HTTP requires gateway_auth_ref")
    end
  end

  defp validate_auxiliary_http_phase_gate(changeset) do
    http =
      changeset
      |> get_field(:http)
      |> normalize_map()

    if Map.get(http, "enabled") == true and get_field(changeset, :transport) != "acp_http" do
      add_error(changeset, :http, "auxiliary HTTP requires acp_http transport")
    else
      changeset
    end
  end

  defp validate_mcp_phase_gate(changeset) do
    case get_field(changeset, :mcp) do
      %{} = map ->
        mcp = InputNormalizer.normalize_keys(map)

        if Map.get(mcp, "enabled") == true do
          changeset
          |> reject_mcp_discovery(mcp)
          |> reject_mcp_project_merge(mcp)
          |> reject_mcp_manual_approval(mcp)
          |> reject_custom_mcp_server_name(mcp)
        else
          changeset
        end

      _value ->
        changeset
    end
  end

  defp reject_mcp_discovery(changeset, mcp) do
    discovery = Map.get(mcp, "discovery", "explicit_config")

    if discovery == "explicit_config" do
      changeset
    else
      add_error(changeset, :mcp, "MCP discovery #{discovery} is unsupported for codebuddy_code Phase 2")
    end
  end

  defp reject_mcp_project_merge(changeset, mcp) do
    if Map.get(mcp, "allow_project_config_merge") == true do
      add_error(changeset, :mcp, "project MCP config merge is unsupported for codebuddy_code Phase 2")
    else
      changeset
    end
  end

  defp reject_mcp_manual_approval(changeset, mcp) do
    if Map.get(mcp, "approve_generated_server") == false do
      add_error(changeset, :mcp, "generated MCP server approval must be rendered non-interactively for codebuddy_code Phase 2")
    else
      changeset
    end
  end

  defp reject_custom_mcp_server_name(changeset, mcp) do
    case Map.get(mcp, "server_name") do
      nil ->
        changeset

      @default_mcp_server_name ->
        changeset

      _server_name ->
        add_error(changeset, :mcp, "custom MCP server_name is unsupported for codebuddy_code Phase 2")
    end
  end

  defp validate_managed_credential_env_isolation(changeset) do
    case get_field(changeset, :credential_ref) do
      nil ->
        changeset

      "" ->
        changeset

      _credential_ref ->
        env =
          changeset
          |> get_field(:env)
          |> normalize_map()

        conflicts =
          env
          |> Map.keys()
          |> Enum.map(&to_string/1)
          |> Enum.filter(&(&1 in @managed_credential_env_keys))
          |> Enum.sort()

        case conflicts do
          [] ->
            changeset

          keys ->
            add_error(changeset, :env, "managed CodeBuddy credentials own #{Enum.join(keys, ", ")}")
        end
    end
  end

  defp reject_enabled(changeset, field, message) do
    case get_field(changeset, field) do
      %{} = map ->
        if Map.get(InputNormalizer.normalize_keys(map), "enabled") == true, do: add_error(changeset, field, message), else: changeset

      _value ->
        changeset
    end
  end

  defp reject_enabled(changeset, field, nested_key, message) do
    case get_field(changeset, field) do
      %{} = map ->
        if Map.get(InputNormalizer.normalize_keys(map), nested_key) == true, do: add_error(changeset, field, message), else: changeset

      _value ->
        changeset
    end
  end

  defp normalize_map(value) when is_map(value), do: InputNormalizer.normalize_keys(value)
  defp normalize_map(_value), do: %{}

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_string_list(_values), do: []

  defp positive_integer_or_nil?(nil), do: true
  defp positive_integer_or_nil?(value), do: is_integer(value) and value > 0
  defp boolean_or_nil?(nil), do: true
  defp boolean_or_nil?(value), do: is_boolean(value)
  defp map_or_nil?(nil), do: true
  defp map_or_nil?(value), do: is_map(value)
  defp http_allowlist_or_nil?(nil), do: true

  defp http_allowlist_or_nil?(value) when is_list(value) do
    Enum.all?(value, fn identifier -> is_binary(identifier) and identifier in @auxiliary_http_allowlist_ids end)
  end

  defp http_allowlist_or_nil?(_value), do: false
  defp non_empty_string_or_nil?(nil), do: true
  defp non_empty_string_or_nil?(value), do: is_binary(value) and String.trim(value) != ""
  defp mcp_server_name_or_nil?(nil), do: true
  defp mcp_server_name_or_nil?(value), do: is_binary(value) and Regex.match?(~r/^[A-Za-z0-9_-]+$/, value)
  defp absolute_path_or_nil?(nil), do: true
  defp absolute_path_or_nil?(value), do: is_binary(value) and Path.type(value) == :absolute
  defp enum_or_nil?(nil, _allowed), do: true
  defp enum_or_nil?(value, allowed), do: value in allowed
  defp port_value_or_nil?(nil), do: true
  defp port_value_or_nil?("auto"), do: true
  defp port_value_or_nil?(value), do: is_integer(value) and value > 0 and value <= 65_535
end

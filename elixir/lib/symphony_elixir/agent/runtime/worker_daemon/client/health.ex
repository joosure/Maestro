defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.Health do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.{Connection, Transport}
  alias SymphonyWorkerDaemon.CommandPolicy.CapabilityContract
  alias SymphonyWorkerDaemon.Protocol
  alias SymphonyWorkerDaemon.Protocol.{Features, HealthStatus}

  @capability_kind_key CapabilityContract.kind_key()
  @capability_scope_key CapabilityContract.scope_key()
  @capability_available_key CapabilityContract.available_key()
  @capability_command_key CapabilityContract.command_key()
  @capability_path_key CapabilityContract.path_key()
  @capability_name_key CapabilityContract.name_key()

  @spec health(Target.t(), keyword()) :: {:ok, Protocol.health_response()} | {:error, term()}
  def health(%Target{} = target, opts \\ []) do
    with {:ok, endpoint} <- Connection.endpoint(target, opts),
         token <- Connection.token(opts),
         {:ok, payload} <-
           Transport.request(:get, endpoint, Protocol.health_path(), token, nil, opts) do
      Protocol.normalize_health_response(payload)
    end
  end

  @spec preflight(Target.t(), keyword()) :: {:ok, Protocol.health_response()} | {:error, term()}
  def preflight(%Target{} = target, opts \\ []) do
    with {:ok, endpoint} <- Connection.endpoint(target, opts),
         token <- Connection.token(opts),
         {:ok, health} <- request_preflight(target, endpoint, token, opts) do
      {:ok, health}
    end
  end

  @spec maybe_preflight(CommandSpec.t(), Target.t(), String.t(), String.t() | nil, keyword()) ::
          {:ok, Protocol.health_response()} | {:error, term()}
  def maybe_preflight(command_spec, target, endpoint, token, opts) do
    if Keyword.get(opts, :worker_daemon_preflight?, true) do
      request_preflight(command_spec, target, endpoint, token, opts)
    else
      {:ok, %{}}
    end
  end

  @spec request_preflight(Target.t(), String.t(), String.t() | nil, keyword()) ::
          {:ok, Protocol.health_response()} | {:error, term()}
  def request_preflight(%Target{} = target, endpoint, token, opts) do
    request_preflight(nil, target, endpoint, token, opts)
  end

  @spec request_preflight(
          CommandSpec.t() | nil,
          Target.t(),
          String.t(),
          String.t() | nil,
          keyword()
        ) ::
          {:ok, Protocol.health_response()} | {:error, term()}
  def request_preflight(command_spec, %Target{} = target, endpoint, token, opts) do
    with {:ok, payload} <-
           Transport.request(:get, endpoint, Protocol.health_path(), token, nil, opts),
         {:ok, health} <- Protocol.normalize_health_response(payload),
         :ok <- validate_health(target, health, opts),
         :ok <- validate_command_capability(command_spec, health) do
      {:ok, health}
    end
  end

  @spec validate_health(Target.t(), Protocol.health_response(), keyword()) ::
          :ok | {:error, term()}
  def validate_health(%Target{} = target, health, opts \\ [])
      when is_map(health) and is_list(opts) do
    with :ok <- validate_protocol_version(health),
         :ok <- validate_worker_id(target, health, opts),
         :ok <- validate_health_status(health, opts),
         :ok <- validate_features(health, opts) do
      :ok
    end
  end

  defp validate_protocol_version(%{protocol_version: version}) do
    expected_version = Protocol.protocol_version()

    if version == expected_version do
      :ok
    else
      {:error, {:worker_daemon_protocol_mismatch, expected_version, version}}
    end
  end

  defp validate_worker_id(%Target{} = target, health, opts) do
    expected_worker_id =
      opts
      |> Keyword.get(:worker_daemon_worker_id)
      |> normalize_optional_string()
      |> case do
        worker_id when is_binary(worker_id) ->
          worker_id

        nil ->
          Connection.metadata_value(target.metadata, :worker_daemon_worker_id)
          |> normalize_optional_string()
      end

    case {expected_worker_id, Map.get(health, :worker_id)} do
      {nil, _actual_worker_id} -> :ok
      {expected, expected} -> :ok
      {expected, actual} -> {:error, {:worker_daemon_worker_mismatch, expected, actual}}
    end
  end

  defp validate_health_status(health, opts) do
    accepted_statuses =
      opts
      |> Keyword.get(
        :worker_daemon_accepted_health_statuses,
        HealthStatus.default_accepted_statuses()
      )
      |> normalize_string_list()

    status = Map.get(health, :status)

    if status in accepted_statuses do
      :ok
    else
      {:error, {:worker_daemon_not_ready, status}}
    end
  end

  defp validate_features(health, opts) do
    required_features =
      opts
      |> Keyword.get(:worker_daemon_required_features, [])
      |> normalize_string_list()
      |> Kernel.++(Protocol.session_required_features())
      |> maybe_require_event_stream(opts)
      |> maybe_require_dynamic_tool_bridge(opts)
      |> Enum.uniq()

    available_features = health |> Map.get(:features, []) |> normalize_string_list()
    missing_features = required_features -- available_features

    case missing_features do
      [] -> :ok
      _features -> {:error, {:worker_daemon_missing_features, missing_features}}
    end
  end

  defp validate_command_capability(nil, _health), do: :ok

  defp validate_command_capability(%CommandSpec{argv: [command | _args]}, health)
       when is_binary(command) do
    capabilities = Map.get(health, :capabilities, [])

    cond do
      executable_policy_any?(capabilities) ->
        :ok

      executable_capability?(capabilities, command) ->
        :ok

      true ->
        {:error, {:worker_daemon_command_not_available, %{command: command, name: Path.basename(command)}}}
    end
  end

  defp validate_command_capability(%CommandSpec{}, _health), do: :ok

  defp executable_policy_any?(capabilities) when is_list(capabilities) do
    Enum.any?(capabilities, fn capability ->
      map_value(capability, @capability_kind_key) == CapabilityContract.executable_policy_kind() and
        map_value(capability, @capability_scope_key) == CapabilityContract.any_scope() and
        map_value(capability, @capability_available_key) != false
    end)
  end

  defp executable_capability?(capabilities, command) when is_list(capabilities) do
    command_name = Path.basename(command)

    Enum.any?(capabilities, fn capability ->
      map_value(capability, @capability_kind_key) == CapabilityContract.executable_kind() and
        map_value(capability, @capability_available_key) != false and
        (map_value(capability, @capability_command_key) == command or
           map_value(capability, @capability_path_key) == command or
           map_value(capability, @capability_name_key) == command_name)
    end)
  end

  defp maybe_require_dynamic_tool_bridge(required_features, opts) do
    if dynamic_tool_bridge_requested?(opts) do
      [Features.dynamic_tool_bridge_proxy() | required_features]
    else
      required_features
    end
  end

  defp maybe_require_event_stream(required_features, opts) do
    if Keyword.get(opts, :worker_daemon_stream_events?, false) do
      [Features.session_events() | required_features]
    else
      required_features
    end
  end

  defp dynamic_tool_bridge_requested?(opts) do
    is_map(Keyword.get(opts, :dynamic_tool_bridge_spec)) or
      daemon_bridge_requested?(Keyword.get(opts, :dynamic_tool_bridge_runtime))
  end

  defp daemon_bridge_requested?(runtime) when is_map(runtime),
    do: is_map(Map.get(runtime, :daemon_bridge) || Map.get(runtime, "daemon_bridge"))

  defp daemon_bridge_requested?(_runtime), do: false

  defp map_value(map, @capability_kind_key) when is_map(map),
    do: known_key_value(map, @capability_kind_key, :kind)

  defp map_value(map, @capability_scope_key) when is_map(map),
    do: known_key_value(map, @capability_scope_key, :scope)

  defp map_value(map, @capability_available_key) when is_map(map),
    do: known_key_value(map, @capability_available_key, :available)

  defp map_value(map, @capability_command_key) when is_map(map),
    do: known_key_value(map, @capability_command_key, :command)

  defp map_value(map, @capability_path_key) when is_map(map),
    do: known_key_value(map, @capability_path_key, :path)

  defp map_value(map, @capability_name_key) when is_map(map),
    do: known_key_value(map, @capability_name_key, :name)

  defp map_value(_map, _key), do: nil

  defp known_key_value(map, string_key, atom_key) do
    cond do
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> nil
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(_values), do: []
end

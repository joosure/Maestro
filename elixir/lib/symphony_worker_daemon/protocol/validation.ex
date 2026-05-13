defmodule SymphonyWorkerDaemon.Protocol.Validation do
  @moduledoc false

  alias SymphonyWorkerDaemon.Protocol.Validation.{Fields, Payload}

  @default_request_bytes 1_048_576
  @default_command_bytes 65_536
  @default_caller_bytes 16_384
  @default_env_bytes 65_536
  @default_dynamic_tool_bridge_bytes 65_536
  @default_input_bytes 1_048_576
  @create_request_keys [
    "protocol_version",
    "request_id",
    "session_id",
    "run_id",
    "caller",
    "command",
    "workspace",
    "env",
    "resource_budget",
    "timeout_policy",
    "required_features",
    "dynamic_tool_bridge"
  ]
  @caller_keys ["provider_kind", "worker_pool", "owner", "tenant_id", "deployment_id"]
  @command_keys ["mode", "argv", "command"]
  @workspace_keys ["cwd", "workspace_path", "remote_workspace_path", "workspace_root"]
  @timeout_policy_keys ["startup_timeout_ms", "idle_timeout_ms", "session_timeout_ms"]
  @resource_budget_keys ["output_buffer_bytes", "output_buffer_limit", "max_output_bytes"]
  @dynamic_tool_bridge_keys [
    "type",
    "transport",
    "symphony_base_url",
    "base_path",
    "execute_path",
    "token",
    "provider_env"
  ]
  @input_request_keys ["protocol_version", "request_id", "input", "encoding"]
  @stop_request_keys ["protocol_version", "request_id", "idempotency_key", "reason"]
  @cleanup_request_keys ["protocol_version", "request_id", "idempotency_key"]

  @spec validate_create_request(map(), [String.t()], keyword()) :: :ok | {:error, term()}
  def validate_create_request(request, supported_features, opts) when is_map(request) and is_list(supported_features) and is_list(opts) do
    with :ok <- validate_protocol_version(request, protocol_version(opts)),
         :ok <- validate_request_id(request),
         :ok <- Fields.allowed_keys(request, "request", @create_request_keys),
         :ok <- validate_caller(request),
         :ok <- validate_create_nested_schema(request),
         :ok <- validate_required_features(request, supported_features),
         :ok <- validate_timeout_policy(request),
         :ok <- validate_resource_budget(request),
         :ok <- validate_create_payload_limits(request, opts) do
      :ok
    end
  end

  def validate_create_request(_request, _supported_features, _opts), do: {:error, :worker_daemon_create_request_invalid}

  @spec validate_input_request(map(), keyword()) :: :ok | {:error, term()}
  def validate_input_request(request, opts) when is_map(request) and is_list(opts) do
    with :ok <- validate_mutation_request(request, opts, @input_request_keys),
         :ok <- validate_input_payload(request),
         :ok <- Payload.size("input", Map.get(request, "input", ""), Payload.limit(opts, :max_protocol_input_bytes, @default_input_bytes)) do
      :ok
    end
  end

  def validate_input_request(_request, _opts), do: {:error, :worker_daemon_input_request_invalid}

  @spec validate_stop_request(map(), keyword()) :: :ok | {:error, term()}
  def validate_stop_request(request, opts) when is_map(request) and is_list(opts) do
    with :ok <- validate_mutation_request(request, opts, @stop_request_keys),
         :ok <- validate_idempotency_key(request),
         :ok <- Fields.optional_string(request, "reason") do
      :ok
    end
  end

  def validate_stop_request(_request, _opts), do: {:error, :worker_daemon_stop_request_invalid}

  @spec validate_cleanup_request(map(), keyword()) :: :ok | {:error, term()}
  def validate_cleanup_request(request, opts) when is_map(request) and is_list(opts) do
    with :ok <- validate_mutation_request(request, opts, @cleanup_request_keys),
         :ok <- validate_idempotency_key(request) do
      :ok
    end
  end

  def validate_cleanup_request(_request, _opts), do: {:error, :worker_daemon_cleanup_request_invalid}

  defp protocol_version(opts), do: Keyword.fetch!(opts, :protocol_version)

  defp validate_protocol_version(%{"protocol_version" => expected_version}, expected_version), do: :ok

  defp validate_protocol_version(%{"protocol_version" => protocol_version}, expected_version) do
    {:error, {:unsupported_protocol_version, expected_version, protocol_version}}
  end

  defp validate_protocol_version(_request, _expected_version), do: {:error, :protocol_version_missing}

  defp validate_request_id(%{"request_id" => request_id}) when is_binary(request_id) and request_id != "", do: :ok
  defp validate_request_id(_request), do: {:error, :request_id_missing}

  defp validate_caller(%{"caller" => caller}) when is_map(caller), do: :ok
  defp validate_caller(_request), do: {:error, :caller_missing}

  defp validate_create_nested_schema(request) when is_map(request) do
    with :ok <- Fields.allowed_nested_keys(request, "caller", @caller_keys),
         :ok <- Fields.allowed_nested_keys(request, "command", @command_keys),
         :ok <- Fields.allowed_nested_keys(request, "workspace", @workspace_keys),
         :ok <- Fields.optional_map(request, "env"),
         :ok <- validate_dynamic_tool_bridge_schema(request) do
      :ok
    end
  end

  defp validate_dynamic_tool_bridge_schema(request) when is_map(request) do
    case Map.get(request, "dynamic_tool_bridge") do
      nil ->
        :ok

      value when is_map(value) ->
        with :ok <- Fields.allowed_keys(value, "dynamic_tool_bridge", @dynamic_tool_bridge_keys),
             :ok <- Fields.optional_string(value, "type"),
             :ok <- Fields.optional_string(value, "transport"),
             :ok <- Fields.optional_string(value, "symphony_base_url"),
             :ok <- Fields.optional_string(value, "base_path"),
             :ok <- Fields.optional_string(value, "execute_path"),
             :ok <- Fields.optional_string(value, "token"),
             :ok <- Fields.optional_map(value, "provider_env") do
          :ok
        end

      _value ->
        {:error, {:payload_invalid, "dynamic_tool_bridge"}}
    end
  end

  defp validate_required_features(request, supported_features) do
    case Map.get(request, "required_features") do
      nil ->
        :ok

      required_features when is_list(required_features) ->
        missing = Payload.string_list(required_features) -- Payload.string_list(supported_features)

        case missing do
          [] -> :ok
          _features -> {:error, {:unsupported_required_features, missing}}
        end

      _required_features ->
        {:error, {:payload_invalid, "required_features"}}
    end
  end

  defp validate_timeout_policy(request) when is_map(request) do
    validate_positive_integer_map(request, "timeout_policy", @timeout_policy_keys)
  end

  defp validate_resource_budget(request) when is_map(request) do
    validate_positive_integer_map(request, "resource_budget", @resource_budget_keys)
  end

  defp validate_positive_integer_map(request, field, allowed_keys)
       when is_map(request) and is_binary(field) and is_list(allowed_keys) do
    case Map.get(request, field) do
      nil ->
        :ok

      value when is_map(value) ->
        with :ok <- Fields.allowed_keys(value, field, allowed_keys) do
          Enum.reduce_while(allowed_keys, :ok, fn key, :ok ->
            case known_policy_value(value, key) do
              nil -> {:cont, :ok}
              value -> validate_positive_integer_field(value, field, key)
            end
          end)
        end

      _value ->
        {:error, {:payload_invalid, field}}
    end
  end

  defp validate_positive_integer_field(value, _field, _key) when is_integer(value) and value > 0, do: {:cont, :ok}

  defp validate_positive_integer_field(value, field, key) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> {:cont, :ok}
      _invalid -> {:halt, {:error, {:payload_invalid, field <> "." <> key}}}
    end
  end

  defp validate_positive_integer_field(_value, field, key), do: {:halt, {:error, {:payload_invalid, field <> "." <> key}}}

  defp known_policy_value(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, known_policy_atom_key(key))
    end
  end

  defp known_policy_atom_key("session_timeout_ms"), do: :session_timeout_ms
  defp known_policy_atom_key("startup_timeout_ms"), do: :startup_timeout_ms
  defp known_policy_atom_key("idle_timeout_ms"), do: :idle_timeout_ms
  defp known_policy_atom_key("output_buffer_bytes"), do: :output_buffer_bytes
  defp known_policy_atom_key("output_buffer_limit"), do: :output_buffer_limit
  defp known_policy_atom_key("max_output_bytes"), do: :max_output_bytes
  defp known_policy_atom_key(_key), do: nil

  defp validate_mutation_request(request, opts, allowed_keys) do
    with :ok <- validate_protocol_version(request, protocol_version(opts)),
         :ok <- validate_request_id(request),
         :ok <- Fields.allowed_keys(request, "request", allowed_keys) do
      Payload.size("request", request, Payload.limit(opts, :max_protocol_request_bytes, @default_request_bytes))
    end
  end

  defp validate_idempotency_key(%{"idempotency_key" => idempotency_key}) when is_binary(idempotency_key) and idempotency_key != "", do: :ok
  defp validate_idempotency_key(_request), do: {:error, :idempotency_key_missing}

  defp validate_input_payload(%{"input" => input} = request) when is_binary(input) do
    case Map.get(request, "encoding", "utf-8") do
      "utf-8" -> :ok
      _encoding -> {:error, {:payload_invalid, "encoding"}}
    end
  end

  defp validate_input_payload(_request), do: {:error, {:payload_invalid, "input"}}

  defp validate_create_payload_limits(request, opts) do
    with :ok <- Payload.size("request", request, Payload.limit(opts, :max_protocol_request_bytes, @default_request_bytes)),
         :ok <- Payload.size("caller", Map.get(request, "caller", %{}), Payload.limit(opts, :max_protocol_caller_bytes, @default_caller_bytes)),
         :ok <- Payload.size("command", Map.get(request, "command", %{}), Payload.limit(opts, :max_protocol_command_bytes, @default_command_bytes)),
         :ok <- Payload.size("env", Map.get(request, "env", %{}), Payload.limit(opts, :max_protocol_env_bytes, @default_env_bytes)),
         :ok <-
           Payload.size(
             "dynamic_tool_bridge",
             Map.get(request, "dynamic_tool_bridge", %{}),
             Payload.limit(opts, :max_protocol_dynamic_tool_bridge_bytes, @default_dynamic_tool_bridge_bytes)
           ) do
      :ok
    end
  end
end

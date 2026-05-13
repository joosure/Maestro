defmodule SymphonyElixir.Agent.Runtime.Environment do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential
  alias SymphonyElixir.Agent.Runtime.DynamicToolBridge.Environment, as: DynamicToolBridgeEnvironment
  alias SymphonyElixir.Config.InputNormalizer

  @supported_telemetry_options ~w(
    enabled
    include_traces
    include_metrics
    include_logs
    log_user_prompts
    log_tool_details
    otlp_endpoint
    otlp_protocol
    otlp_traces_endpoint
    otlp_traces_protocol
    otlp_metrics_endpoint
    otlp_metrics_protocol
    otlp_logs_endpoint
    otlp_logs_protocol
    resource_attributes
  )
  @boolean_telemetry_options ~w(enabled include_traces include_metrics include_logs log_user_prompts log_tool_details)
  @string_telemetry_options ~w(
    otlp_endpoint
    otlp_protocol
    otlp_traces_endpoint
    otlp_traces_protocol
    otlp_metrics_endpoint
    otlp_metrics_protocol
    otlp_logs_endpoint
    otlp_logs_protocol
  )

  @spec current_env(String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, term()}
  def current_env(provider_kind, telemetry \\ %{}, opts \\ []) when is_binary(provider_kind) do
    with {:ok, dynamic_tool_env} <- dynamic_tool_env(opts) do
      env =
        dynamic_tool_env
        |> Map.merge(credential_env(opts))
        |> Map.merge(telemetry_env(provider_kind, telemetry, opts))

      {:ok, env}
    end
  end

  defp dynamic_tool_env(opts) do
    if Keyword.get(opts, :include_dynamic_tool_env, true) do
      DynamicToolBridgeEnvironment.current_env(opts)
    else
      {:ok, %{}}
    end
  end

  @spec telemetry_env(String.t(), map() | nil, keyword()) :: map()
  def telemetry_env(provider_kind, telemetry, opts \\ [])

  def telemetry_env(provider_kind, telemetry, opts) when is_binary(provider_kind) and is_map(telemetry) do
    telemetry = normalize_telemetry(telemetry)

    if Map.get(telemetry, "enabled", false) do
      %{}
      |> maybe_put_exporter("OTEL_TRACES_EXPORTER", Map.get(telemetry, "include_traces", true))
      |> maybe_put_exporter("OTEL_METRICS_EXPORTER", Map.get(telemetry, "include_metrics", true))
      |> maybe_put_exporter("OTEL_LOGS_EXPORTER", Map.get(telemetry, "include_logs", true))
      |> maybe_put_env("OTEL_EXPORTER_OTLP_ENDPOINT", Map.get(telemetry, "otlp_endpoint"))
      |> maybe_put_env("OTEL_EXPORTER_OTLP_PROTOCOL", Map.get(telemetry, "otlp_protocol"))
      |> maybe_put_env("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", Map.get(telemetry, "otlp_traces_endpoint"))
      |> maybe_put_env("OTEL_EXPORTER_OTLP_TRACES_PROTOCOL", Map.get(telemetry, "otlp_traces_protocol"))
      |> maybe_put_env("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT", Map.get(telemetry, "otlp_metrics_endpoint"))
      |> maybe_put_env("OTEL_EXPORTER_OTLP_METRICS_PROTOCOL", Map.get(telemetry, "otlp_metrics_protocol"))
      |> maybe_put_env("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT", Map.get(telemetry, "otlp_logs_endpoint"))
      |> maybe_put_env("OTEL_EXPORTER_OTLP_LOGS_PROTOCOL", Map.get(telemetry, "otlp_logs_protocol"))
      |> maybe_put_flag("OTEL_LOG_USER_PROMPTS", Map.get(telemetry, "log_user_prompts", false))
      |> maybe_put_flag("OTEL_LOG_TOOL_DETAILS", Map.get(telemetry, "log_tool_details", false))
      |> maybe_put_env("OTEL_RESOURCE_ATTRIBUTES", resource_attributes(provider_kind, telemetry, opts))
      |> maybe_put_claude_code_flags(provider_kind, telemetry)
    else
      %{}
    end
  end

  def telemetry_env(_provider_kind, _telemetry, _opts), do: %{}

  @spec validate_telemetry(term()) :: :ok | {:error, String.t()}
  def validate_telemetry(nil), do: :ok

  def validate_telemetry(telemetry) when is_map(telemetry) do
    telemetry = InputNormalizer.normalize_keys(telemetry)

    with :ok <- validate_supported_telemetry_options(telemetry),
         :ok <- validate_boolean_telemetry_options(telemetry),
         :ok <- validate_string_telemetry_options(telemetry),
         :ok <- validate_resource_attributes(Map.get(telemetry, "resource_attributes")) do
      :ok
    end
  end

  def validate_telemetry(_telemetry), do: {:error, "must be a map"}

  @spec normalize_telemetry(term()) :: map()
  def normalize_telemetry(nil), do: %{}

  def normalize_telemetry(telemetry) when is_map(telemetry) do
    telemetry
    |> InputNormalizer.normalize_keys()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, key, normalize_telemetry_value(key, value))
    end)
  end

  def normalize_telemetry(_telemetry), do: %{}

  defp credential_env(opts) when is_list(opts) do
    opts
    |> Keyword.get(:agent_credential_material)
    |> Credential.material_env()
  end

  defp normalize_telemetry_value(key, value) when key in @boolean_telemetry_options and is_boolean(value), do: value

  defp normalize_telemetry_value(key, value) when key in @string_telemetry_options and is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_telemetry_value("resource_attributes", attrs) when is_map(attrs) do
    attrs
    |> InputNormalizer.normalize_keys()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      normalized_value = normalize_attribute_value(value)

      if is_nil(normalized_value) do
        acc
      else
        Map.put(acc, key, normalized_value)
      end
    end)
  end

  defp normalize_telemetry_value(_key, value), do: value

  defp validate_supported_telemetry_options(telemetry) do
    unsupported =
      telemetry
      |> Map.keys()
      |> Enum.reject(&(&1 in @supported_telemetry_options))
      |> Enum.sort()

    case unsupported do
      [] -> :ok
      _ -> {:error, "contains unsupported options #{Enum.join(unsupported, ", ")}"}
    end
  end

  defp validate_boolean_telemetry_options(telemetry) do
    invalid =
      telemetry
      |> Enum.filter(fn {key, value} -> key in @boolean_telemetry_options and not is_boolean(value) end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    case invalid do
      [] -> :ok
      _ -> {:error, "boolean options must be true or false: #{Enum.join(invalid, ", ")}"}
    end
  end

  defp validate_string_telemetry_options(telemetry) do
    invalid =
      telemetry
      |> Enum.filter(fn {key, value} -> key in @string_telemetry_options and not (is_binary(value) or is_nil(value)) end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    case invalid do
      [] -> :ok
      _ -> {:error, "string options must be strings: #{Enum.join(invalid, ", ")}"}
    end
  end

  defp validate_resource_attributes(nil), do: :ok

  defp validate_resource_attributes(attrs) when is_map(attrs) do
    invalid =
      attrs
      |> Enum.reject(fn {key, value} ->
        (is_binary(key) or is_atom(key)) and valid_attribute_value?(value)
      end)

    case invalid do
      [] -> :ok
      _ -> {:error, "resource_attributes must be a map of string, number, boolean, or nil values"}
    end
  end

  defp validate_resource_attributes(_attrs), do: {:error, "resource_attributes must be a map"}

  defp valid_attribute_value?(value)
       when is_binary(value) or is_integer(value) or is_float(value) or is_boolean(value) or is_nil(value),
       do: true

  defp valid_attribute_value?(_value), do: false

  defp resource_attributes(provider_kind, telemetry, opts) do
    default_attributes(provider_kind, opts)
    |> Map.merge(Map.get(telemetry, "resource_attributes", %{}) || %{})
    |> serialize_resource_attributes()
  end

  defp default_attributes(provider_kind, opts) do
    issue = Keyword.get(opts, :issue)

    %{
      "agent.provider" => provider_kind,
      "agent.session_id" => Keyword.get(opts, :session_id),
      "issue.id" => map_value(issue, :id) || Keyword.get(opts, :issue_id),
      "issue.identifier" => map_value(issue, :identifier) || Keyword.get(opts, :issue_identifier),
      "run.id" => Keyword.get(opts, :run_id),
      "service.name" => "symphony-agent-provider"
    }
  end

  defp serialize_resource_attributes(attrs) when is_map(attrs) do
    attrs
    |> Enum.flat_map(fn {key, value} ->
      case normalize_attribute_value(value) do
        nil -> []
        normalized_value -> [{to_string(key), normalized_value}]
      end
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join(",", fn {key, value} -> "#{escape_attribute(key)}=#{escape_attribute(value)}" end)
  end

  defp normalize_attribute_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_attribute_value(value) when is_integer(value) or is_float(value) or is_boolean(value), do: to_string(value)
  defp normalize_attribute_value(_value), do: nil

  defp escape_attribute(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace(",", "\\,")
    |> String.replace("=", "\\=")
  end

  defp maybe_put_exporter(env, key, true), do: Map.put(env, key, "otlp")
  defp maybe_put_exporter(env, _key, _enabled?), do: env

  defp maybe_put_flag(env, key, true), do: Map.put(env, key, "1")
  defp maybe_put_flag(env, _key, _enabled?), do: env

  defp maybe_put_env(env, _key, value) when value in [nil, ""], do: env
  defp maybe_put_env(env, key, value) when is_binary(key), do: Map.put(env, key, to_string(value))

  defp maybe_put_claude_code_flags(env, "claude_code", telemetry) do
    env
    |> Map.put("CLAUDE_CODE_ENABLE_TELEMETRY", "1")
    |> maybe_put_flag("CLAUDE_CODE_ENHANCED_TELEMETRY_BETA", Map.get(telemetry, "include_traces", true))
  end

  defp maybe_put_claude_code_flags(env, _provider_kind, _telemetry), do: env

  defp map_value(nil, _key), do: nil
  defp map_value(map, key) when is_map(map), do: Map.get(map, key)
  defp map_value(_value, _key), do: nil
end

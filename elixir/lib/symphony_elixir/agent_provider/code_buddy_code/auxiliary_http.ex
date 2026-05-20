defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.AuxiliaryHttp do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Accounts.Secret
  alias SymphonyElixir.Agent.Credential.Store
  alias SymphonyElixir.AgentProvider.CodeBuddyCode.Settings
  alias SymphonyElixir.Observability.Redaction

  @gateway_provider_kind "gateway"
  @type endpoint :: %{
          identifier: String.t(),
          method: String.t(),
          path: String.t(),
          request_header_required?: boolean()
        }

  @allowed_identifiers ~w(auth_status health version metrics_summary session_stats plugin_inventory)
  @request_header "x-codebuddy-request"

  @spec allowed_identifiers() :: [String.t()]
  def allowed_identifiers, do: @allowed_identifiers

  @spec resolve(String.t()) :: {:ok, endpoint()} | {:error, {:unsupported_auxiliary_http_endpoint, String.t()}}
  def resolve(identifier) when identifier in @allowed_identifiers do
    {:ok, endpoint(identifier)}
  end

  def resolve(identifier) when is_binary(identifier), do: {:error, {:unsupported_auxiliary_http_endpoint, identifier}}

  @spec collect(String.t(), Settings.t(), keyword()) :: map()
  def collect(base_url, %Settings{} = settings, opts \\ []) when is_binary(base_url) and is_list(opts) do
    case resolve_gateway_auth_opts(settings, opts) do
      {:ok, opts} ->
        settings
        |> Settings.http_allowlist()
        |> Enum.reduce(%{"errors" => []}, fn identifier, acc -> collect_identifier(base_url, settings, opts, identifier, acc) end)
        |> drop_empty_errors()

      {:error, reason} ->
        %{"errors" => [error_metadata("gateway_auth", reason)]}
    end
  rescue
    error ->
      %{"errors" => [%{"reason" => Redaction.summarize(error, 256)}]}
  end

  defp collect_identifier(base_url, settings, opts, identifier, acc) do
    with {:ok, endpoint} <- resolve(identifier),
         {:ok, response} <- get_endpoint(base_url, settings, opts, endpoint) do
      Map.put(acc, identifier, project(identifier, response))
    else
      {:error, reason} ->
        put_error(acc, identifier, reason)
    end
  end

  defp get_endpoint(base_url, settings, opts, endpoint) do
    with {:ok, headers} <- request_headers(endpoint, settings, opts) do
      request =
        Req.new(
          base_url: base_url,
          retry: false,
          receive_timeout: settings.read_timeout_ms,
          connect_options: [timeout: settings.read_timeout_ms]
        )

      case Req.get(request, url: endpoint.path, headers: headers) do
        {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
        {:ok, %{status: status, body: body}} -> {:error, Map.merge(endpoint_error(endpoint), %{"response_status" => status, "response_body" => preview(body)})}
        {:error, reason} -> {:error, Map.merge(endpoint_error(endpoint), %{"reason" => preview(reason)})}
      end
    end
  rescue
    error -> {:error, Map.merge(endpoint_error(endpoint), %{"reason" => preview(error)})}
  end

  defp request_headers(endpoint, settings, opts) do
    base_headers =
      %{"accept" => "application/json"}
      |> maybe_put_request_header(endpoint)

    with {:ok, auth_headers} <- auth_headers(settings, opts) do
      {:ok, Map.merge(base_headers, auth_headers)}
    end
  end

  defp maybe_put_request_header(headers, %{request_header_required?: true}), do: Map.put(headers, @request_header, "1")
  defp maybe_put_request_header(headers, _endpoint), do: headers

  defp auth_headers(settings, opts) do
    auth_mode = Settings.http_auth_mode(settings)
    material = gateway_auth_material(opts)

    cond do
      auth_mode == "runtime_gateway" and is_nil(material) ->
        {:error, %{"reason" => "missing runtime gateway auth material"}}

      is_nil(material) ->
        {:ok, %{}}

      true ->
        {:ok, %{"authorization" => "Bearer " <> material}}
    end
  end

  defp gateway_auth_material(opts) when is_list(opts) do
    opts
    |> Keyword.get(:codebuddy_auxiliary_http_gateway_auth, Keyword.get(opts, :gateway_auth))
    |> normalize_gateway_auth_material()
  end

  defp resolve_gateway_auth_opts(settings, opts) do
    cond do
      not is_nil(gateway_auth_material(opts)) ->
        {:ok, opts}

      Settings.http_auth_mode(settings) != "runtime_gateway" ->
        {:ok, opts}

      true ->
        settings
        |> Settings.http_gateway_auth_ref()
        |> resolve_gateway_auth_ref(opts)
    end
  end

  defp resolve_gateway_auth_ref(nil, _opts), do: {:error, %{"reason" => "missing runtime gateway auth material"}}

  defp resolve_gateway_auth_ref(ref, opts) when is_binary(ref) do
    with {:ok, credential_ref} <- gateway_credential_ref(ref),
         :ok <- ensure_gateway_store_enabled(opts),
         {:ok, material} <- resolve_gateway_credential_ref(credential_ref, opts) do
      {:ok, Keyword.put(opts, :codebuddy_auxiliary_http_gateway_auth, %{bearer: material})}
    else
      {:error, reason} -> {:error, gateway_auth_error(reason)}
    end
  end

  defp gateway_credential_ref("credential://" <> _rest = ref), do: {:ok, ref}
  defp gateway_credential_ref("secret://" <> id), do: {:ok, "credential://#{@gateway_provider_kind}/#{id}"}
  defp gateway_credential_ref("secret:" <> id), do: {:ok, "credential://#{@gateway_provider_kind}/#{id}"}
  defp gateway_credential_ref(_ref), do: {:error, :unsupported_gateway_auth_ref}

  defp ensure_gateway_store_enabled(opts) do
    if Store.enabled?(opts), do: :ok, else: {:error, :gateway_auth_credential_store_disabled}
  end

  defp resolve_gateway_credential_ref(credential_ref, opts) do
    case Store.acquire(@gateway_provider_kind, credential_ref, opts) do
      {:ok, lease} ->
        result = gateway_secret_from_lease(lease)
        _release_result = Store.release(lease, opts)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp gateway_secret_from_lease(%{metadata: metadata}) when is_map(metadata) do
    case metadata[:account] || metadata["account"] do
      %{secret_file: secret_file} when is_binary(secret_file) ->
        case Secret.read(secret_file) do
          material when is_binary(material) and material != "" -> {:ok, material}
          _material -> {:error, :missing_gateway_auth_secret}
        end

      _account ->
        {:error, :missing_gateway_auth_account}
    end
  end

  defp gateway_auth_error(reason) do
    %{
      "reason" => "gateway auth credential unavailable",
      "details" => Redaction.summarize(reason, 256)
    }
  end

  defp normalize_gateway_auth_material(%{password: password}) when is_binary(password) and password != "", do: password
  defp normalize_gateway_auth_material(%{"password" => password}) when is_binary(password) and password != "", do: password
  defp normalize_gateway_auth_material(%{bearer: token}) when is_binary(token) and token != "", do: token
  defp normalize_gateway_auth_material(%{"bearer" => token}) when is_binary(token) and token != "", do: token
  defp normalize_gateway_auth_material(%{token: token}) when is_binary(token) and token != "", do: token
  defp normalize_gateway_auth_material(%{"token" => token}) when is_binary(token) and token != "", do: token
  defp normalize_gateway_auth_material(value) when is_binary(value) and value != "", do: value
  defp normalize_gateway_auth_material(_value), do: nil

  defp endpoint("auth_status"), do: %{identifier: "auth_status", method: "GET", path: "/api/v1/auth/status", request_header_required?: false}
  defp endpoint("health"), do: %{identifier: "health", method: "GET", path: "/api/v1/health", request_header_required?: true}
  defp endpoint("version"), do: %{identifier: "version", method: "GET", path: "/api/v1/info", request_header_required?: true}
  defp endpoint("metrics_summary"), do: %{identifier: "metrics_summary", method: "GET", path: "/api/v1/metrics", request_header_required?: true}
  defp endpoint("session_stats"), do: %{identifier: "session_stats", method: "GET", path: "/api/v1/stats/session", request_header_required?: true}
  defp endpoint("plugin_inventory"), do: %{identifier: "plugin_inventory", method: "GET", path: "/api/v1/plugins", request_header_required?: true}

  defp project("auth_status", %{} = payload), do: take(payload, ["authEnabled", "authenticated"])
  defp project("health", payload), do: payload |> data() |> take(["status", "uptime", "platforms"])
  defp project("version", payload), do: payload |> data() |> take(["version", "nodeVersion", "os", "arch", "gatewayMode", "uptime"])

  defp project("metrics_summary", payload) do
    body = data(payload)

    body
    |> take(["cpuCount", "cpuUsedPct", "diskTotal", "diskUsed", "memTotalMib", "memUsedMib", "ts"])
    |> maybe_put_instance_count(Map.get(body, "instances"))
  end

  defp project("session_stats", payload) do
    body = data(payload)

    body
    |> take(["apiDuration", "runningTime", "startupTime"])
    |> maybe_put_numeric_map("fileChangeStats", Map.get(body, "fileChangeStats"))
    |> maybe_put_usage_shape(Map.get(body, "tokenUsageByModel"))
  end

  defp project("plugin_inventory", payload) do
    case data(payload) do
      plugins when is_list(plugins) ->
        Enum.map(plugins, &project_plugin/1)

      _plugins ->
        []
    end
  end

  defp project(_identifier, _payload), do: %{}

  defp data(%{"data" => data}) when is_map(data) or is_list(data), do: data
  defp data(_payload), do: %{}

  defp take(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case Map.fetch(map, key) do
        {:ok, value} -> Map.put(acc, key, bounded_value(value))
        :error -> acc
      end
    end)
  end

  defp maybe_put_instance_count(map, instances) when is_list(instances), do: Map.put(map, "instance_count", length(instances))
  defp maybe_put_instance_count(map, _instances), do: map

  defp maybe_put_numeric_map(map, key, value) when is_map(value) do
    numeric =
      value
      |> Enum.filter(fn {_nested_key, nested_value} -> is_number(nested_value) end)
      |> Map.new()

    if map_size(numeric) == 0, do: map, else: Map.put(map, key, numeric)
  end

  defp maybe_put_numeric_map(map, _key, _value), do: map

  defp maybe_put_usage_shape(map, value) when is_map(value) do
    Map.put(map, "tokenUsageByModel", %{"present" => true, "model_count" => map_size(value)})
  end

  defp maybe_put_usage_shape(map, _value), do: map

  defp project_plugin(plugin) when is_map(plugin) do
    plugin
    |> take(["id", "name", "version", "enabled", "sourceType", "source_type"])
  end

  defp project_plugin(_plugin), do: %{}

  defp bounded_value(value) when is_binary(value), do: value |> Redaction.redact_string() |> truncate_string(256)
  defp bounded_value(value) when is_boolean(value) or is_number(value) or is_nil(value), do: value

  defp bounded_value(values) when is_list(values) do
    values
    |> Enum.take(20)
    |> Enum.map(&bounded_value/1)
  end

  defp bounded_value(value) when is_map(value) do
    value
    |> Enum.take(20)
    |> Enum.map(fn {key, nested_value} -> {to_string(key), bounded_value(nested_value)} end)
    |> Map.new()
  end

  defp bounded_value(_value), do: "<redacted>"

  defp put_error(acc, identifier, reason) do
    Map.update(acc, "errors", [error_metadata(identifier, reason)], &[error_metadata(identifier, reason) | &1])
  end

  defp error_metadata(identifier, reason) when is_map(reason) do
    reason
    |> Map.put_new("identifier", identifier)
    |> redact_error_metadata()
  end

  defp error_metadata(identifier, reason), do: %{"identifier" => identifier, "reason" => preview(reason)}

  defp endpoint_error(endpoint), do: %{"method" => endpoint.method, "path" => endpoint.path}

  defp redact_error_metadata(metadata) do
    metadata
    |> Enum.reject(fn {key, _value} -> String.downcase(to_string(key)) in ["authorization", "password", "token"] end)
    |> Map.new(fn
      {key, value} when key in ["response_body", "reason"] -> {key, preview(value)}
      {key, value} -> {key, bounded_value(value)}
    end)
  end

  defp drop_empty_errors(%{"errors" => []} = map), do: Map.delete(map, "errors")
  defp drop_empty_errors(%{"errors" => errors} = map), do: Map.put(map, "errors", Enum.reverse(errors))
  defp drop_empty_errors(map), do: map

  defp preview(value), do: Redaction.summarize(value, 256)

  defp truncate_string(value, max_bytes) when is_binary(value) and byte_size(value) > max_bytes do
    binary_part(value, 0, max_bytes) <> "...<truncated>"
  rescue
    _error -> Redaction.summarize(value, max_bytes)
  end

  defp truncate_string(value, _max_bytes), do: value
end

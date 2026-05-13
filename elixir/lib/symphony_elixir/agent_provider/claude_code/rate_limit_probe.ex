defmodule SymphonyElixir.AgentProvider.ClaudeCode.RateLimitProbe do
  @moduledoc false

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"
  @oauth_beta "oauth-2025-04-20"
  @claude_code_system "You are Claude Code, Anthropic's official CLI for Claude."
  @default_model "claude-haiku-4-5"
  @limit_id "anthropic_oauth"

  @type rate_limits :: map()

  @spec probe(map(), keyword()) :: {:ok, rate_limits()} | {:error, term()}
  def probe(account, opts \\ []) when is_map(account) and is_list(opts) do
    with {:ok, token} <- read_oauth_token(account) do
      req_fun = Keyword.get(opts, :req_fun) || Keyword.get(opts, :claude_rate_limit_req_fun) || (&default_request/2)
      payload = probe_payload(Keyword.get(opts, :model, @default_model))
      headers = probe_headers(token)

      case req_fun.(payload, headers) do
        {:ok, %{status: status, headers: response_headers}} when status >= 200 and status < 300 ->
          rate_limits_from_response(response_headers)

        {:ok, %{status: status, headers: response_headers} = response} ->
          Logger.warning("Claude Code quota probe returned HTTP #{status}: #{summarize_body(Map.get(response, :body))}")

          case rate_limits_from_response(response_headers) do
            {:ok, rate_limits} -> {:ok, rate_limits}
            {:error, :empty_rate_limit_headers} -> {:error, {:anthropic_http_status, status}}
          end

        {:error, reason} ->
          Logger.warning("Claude Code quota probe failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @spec rate_limits_from_response([{String.t(), String.t()}] | map()) ::
          {:ok, rate_limits()} | {:error, :empty_rate_limit_headers}
  def rate_limits_from_response(headers) do
    normalized = normalize_headers(headers)

    session = bucket_from_headers(normalized, "5h")
    weekly = bucket_from_headers(normalized, "7d")

    cond do
      is_nil(session) and is_nil(weekly) ->
        {:error, :empty_rate_limit_headers}

      true ->
        {:ok,
         %{"limit_id" => @limit_id}
         |> maybe_put("session", session)
         |> maybe_put("weekly", weekly)}
    end
  end

  defp bucket_from_headers(normalized, window) do
    status = Map.get(normalized, "anthropic-ratelimit-unified-#{window}-status")
    reset_raw = Map.get(normalized, "anthropic-ratelimit-unified-#{window}-reset")
    utilization_raw = Map.get(normalized, "anthropic-ratelimit-unified-#{window}-utilization")

    utilization = parse_float(utilization_raw)
    reset_at = parse_unix_timestamp(reset_raw)

    cond do
      is_nil(utilization) and is_nil(reset_at) and is_nil(status) ->
        nil

      true ->
        %{}
        |> put_if("period", period_for_window(window))
        |> put_if("status", status)
        |> put_if("usage_percent", utilization_to_percent(utilization))
        |> put_if("utilization", utilization)
        |> put_if("reset_at", reset_at)
        |> put_if("limit", if(utilization, do: 100, else: nil))
        |> put_if("remaining", utilization_to_remaining(utilization, status))
    end
  end

  defp period_for_window("5h"), do: "session"
  defp period_for_window("7d"), do: "weekly"

  defp utilization_to_percent(nil), do: nil
  defp utilization_to_percent(util) when is_float(util), do: Float.round(util * 100.0, 2)
  defp utilization_to_remaining(nil, _status), do: nil

  defp utilization_to_remaining(util, status) when is_float(util) do
    cond do
      status in ["rate_limited", "exhausted"] -> 0
      util >= 1.0 -> 0
      true -> max(1, round((1.0 - util) * 100))
    end
  end

  defp parse_float(nil), do: nil

  defp parse_float(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {float, _rest} -> float
      :error -> nil
    end
  end

  defp parse_float(value) when is_number(value), do: value * 1.0

  defp parse_unix_timestamp(nil), do: nil

  defp parse_unix_timestamp(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {seconds, _rest} -> unix_to_iso(seconds)
      :error -> nil
    end
  end

  defp parse_unix_timestamp(value) when is_integer(value), do: unix_to_iso(value)

  defp unix_to_iso(seconds) when is_integer(seconds) do
    case DateTime.from_unix(seconds) do
      {:ok, dt} -> DateTime.to_iso8601(dt)
      _error -> nil
    end
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_headers(headers) when is_list(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      Map.put(acc, String.downcase(to_string(key)), header_value_to_string(value))
    end)
  end

  defp normalize_headers(headers) when is_map(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      Map.put(acc, String.downcase(to_string(key)), header_value_to_string(value))
    end)
  end

  defp header_value_to_string(value) when is_binary(value), do: value
  defp header_value_to_string([first | _rest]) when is_binary(first), do: first
  defp header_value_to_string(value), do: to_string(value)

  defp probe_payload(model) do
    %{
      "model" => model,
      "max_tokens" => 1,
      "system" => @claude_code_system,
      "messages" => [%{"role" => "user", "content" => "."}]
    }
  end

  defp probe_headers(token) do
    [
      {"authorization", "Bearer " <> token},
      {"anthropic-version", @api_version},
      {"anthropic-beta", @oauth_beta},
      {"content-type", "application/json"}
    ]
  end

  defp default_request(payload, headers) do
    Req.post(@api_url,
      headers: headers,
      json: payload,
      receive_timeout: 15_000,
      connect_options: [timeout: 15_000]
    )
  end

  defp read_oauth_token(%{secret_file: path}) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} ->
        case String.trim(contents) do
          "" -> {:error, :missing_claude_oauth_token}
          token -> {:ok, token}
        end

      {:error, reason} ->
        {:error, {:claude_oauth_token_read, reason}}
    end
  end

  defp read_oauth_token(_account), do: {:error, :missing_claude_oauth_token}

  defp summarize_body(body) when is_binary(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 240)
  end

  defp summarize_body(body), do: inspect(body, limit: 20, printable_limit: 240)
end

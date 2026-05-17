defmodule SymphonyElixir.Tracker.Linear.GraphQL do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Kinds
  alias SymphonyElixir.Tracker.Linear.Errors

  @max_error_body_log_bytes 1_000
  @provider_kind Kinds.linear()

  @spec request(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def request(query, variables, opts)
      when is_binary(query) and is_map(variables) and is_list(opts) do
    payload = build_payload(query, variables, Keyword.get(opts, :operation_name))
    operation = Keyword.get(opts, :operation, :request)
    tracker = Keyword.fetch!(opts, :tracker)
    request_fun = Keyword.get(opts, :request_fun, fn payload, headers -> post_request(payload, headers, tracker) end)
    started_at_ms = System.monotonic_time(:millisecond)
    request_fields = request_fields(tracker, payload, variables)

    ObservabilityLogger.emit(:info, :tracker_request_started, request_fields)

    with {:ok, headers} <- headers(tracker),
         {:ok, %{status: 200, body: body}} <- request_fun.(payload, headers) do
      ObservabilityLogger.emit(
        :info,
        :tracker_request_succeeded,
        Map.merge(request_fields, %{duration_ms: elapsed_ms(started_at_ms), status: 200})
      )

      {:ok, body}
    else
      {:ok, response} ->
        status = Map.get(response, :status) || Map.get(response, "status")

        ObservabilityLogger.emit(
          :warning,
          :tracker_request_failed,
          Map.merge(request_fields, %{
            duration_ms: elapsed_ms(started_at_ms),
            status: status,
            error: summarize_error_body(Map.get(response, :body) || Map.get(response, "body"))
          })
        )

        {:error, Errors.normalize(operation, {:linear_api_status, status})}

      {:error, reason} ->
        ObservabilityLogger.emit(
          :warning,
          :tracker_request_failed,
          Map.merge(request_fields, %{duration_ms: elapsed_ms(started_at_ms), error: inspect(reason)})
        )

        {:error, Errors.normalize(operation, {:linear_api_request, reason})}
    end
  end

  defp build_payload(query, variables, operation_name) do
    %{
      "query" => query,
      "variables" => variables
    }
    |> maybe_put_operation_name(operation_name)
  end

  defp maybe_put_operation_name(payload, operation_name) when is_binary(operation_name) do
    trimmed = String.trim(operation_name)

    if trimmed == "" do
      payload
    else
      Map.put(payload, "operationName", trimmed)
    end
  end

  defp maybe_put_operation_name(payload, _operation_name), do: payload

  defp headers(tracker) do
    case TrackerConfig.api_key(tracker) do
      nil ->
        {:error, :missing_linear_api_token}

      token ->
        {:ok,
         [
           {"Authorization", token},
           {"Content-Type", "application/json"}
         ]}
    end
  end

  defp post_request(payload, headers, tracker) do
    Req.post(TrackerConfig.endpoint(tracker),
      headers: headers,
      json: payload,
      connect_options: [timeout: 30_000]
    )
  end

  defp request_fields(tracker, payload, variables) do
    %{
      component: "tracker.linear.client",
      tracker_kind: Map.get(tracker, :kind, @provider_kind),
      http_method: "POST",
      http_path: "/graphql",
      operation_name: Map.get(payload, "operationName"),
      payload_summary: Redaction.summarize(%{"operationName" => Map.get(payload, "operationName"), "variables" => variables})
    }
  end

  defp summarize_error_body(body) when is_binary(body) do
    body
    |> Redaction.redact_string()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> truncate_error_body()
    |> inspect()
  end

  defp summarize_error_body(body) do
    body
    |> Redaction.redact()
    |> inspect(limit: 20, printable_limit: @max_error_body_log_bytes)
    |> truncate_error_body()
  end

  defp elapsed_ms(started_at_ms) when is_integer(started_at_ms) do
    max(System.monotonic_time(:millisecond) - started_at_ms, 0)
  end

  defp truncate_error_body(body) when is_binary(body) do
    if byte_size(body) > @max_error_body_log_bytes do
      binary_part(body, 0, @max_error_body_log_bytes) <> "...<truncated>"
    else
      body
    end
  end
end

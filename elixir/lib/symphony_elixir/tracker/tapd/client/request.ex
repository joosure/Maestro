defmodule SymphonyElixir.Tracker.Tapd.Client.Request do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Kinds
  alias SymphonyElixir.Tracker.Tapd.Client.{Errors, Response}
  alias SymphonyElixir.Tracker.Tapd.CommentCodec

  @request_timeout_ms 30_000
  @provider_kind Kinds.tapd()
  @retryable_http_statuses [408, 429, 500, 502, 503, 504]
  @transient_retry_delays_ms [1_000, 2_000, 5_000]

  @spec request(String.t(), String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, term()}
  def request(method, path, params \\ %{}, opts \\ [])
      when is_binary(method) and is_binary(path) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)
    operation = Keyword.get(opts, :operation, :request)
    request_fun = Keyword.get(opts, :request_fun, &default_request/1)
    retry_delays_ms = Keyword.get(opts, :retry_delays_ms, @transient_retry_delays_ms)
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    normalized_params = normalize_params(params || %{})
    started_at_ms = System.monotonic_time(:millisecond)

    with :ok <- validate_workspace_param(normalized_params),
         :ok <- validate_flat_scalar_params(normalized_params),
         {:ok, workspace_id} <- workspace_id(tracker),
         {:ok, headers} <- request_headers(tracker),
         {:ok, method} <- normalize_method(method),
         normalized_params <- CommentCodec.normalize_request_params(method, path, normalized_params),
         request_fields <-
           tracker_request_fields(
             tracker,
             method,
             path,
             Map.put(normalized_params, "workspace_id", workspace_id)
           ),
         :ok <- emit_tracker_request_started(request_fields),
         {:ok, response, body} <-
           perform_request_with_retry(
             request_fun,
             tracker,
             method,
             path,
             Map.put(normalized_params, "workspace_id", workspace_id),
             headers,
             retry_delays_ms,
             sleep_fun,
             request_fields
           ) do
      ObservabilityLogger.emit(
        :info,
        :tracker_request_succeeded,
        Map.merge(request_fields, %{
          duration_ms: elapsed_ms(started_at_ms),
          status: Response.response_status(response)
        })
      )

      {:ok, CommentCodec.normalize_response_body(method, path, body)}
    else
      {:error, reason} ->
        normalized_error = Errors.normalize(operation, reason)

        ObservabilityLogger.emit(
          :warning,
          :tracker_request_failed,
          %{
            component: "tracker.tapd.client",
            tracker_kind: Map.get(tracker, :kind, @provider_kind),
            http_method: method,
            http_path: path,
            payload_summary: Redaction.summarize(normalized_params),
            duration_ms: elapsed_ms(started_at_ms),
            status: Response.error_status(normalized_error),
            error: inspect(normalized_error)
          }
        )

        {:error, normalized_error}
    end
  end

  defp perform_request(request_fun, tracker, method, path, params, headers) do
    request_fun.(%{
      method: method,
      url: endpoint(tracker) <> path,
      headers: headers,
      params: params,
      timeout_ms: @request_timeout_ms
    })
  rescue
    error -> {:error, error}
  end

  defp perform_request_with_retry(
         request_fun,
         tracker,
         method,
         path,
         params,
         headers,
         retry_delays_ms,
         sleep_fun,
         request_fields,
         attempt \\ 1
       ) do
    response = perform_request(request_fun, tracker, method, path, params, headers)

    case Response.handle_response(response) do
      {:ok, body} ->
        {:ok, response, body}

      {:error, reason} = error ->
        case pop_retry_delay(reason, retry_delays_ms) do
          {:ok, delay_ms, remaining_retry_delays_ms} ->
            emit_tracker_request_retry(request_fields, reason, attempt, delay_ms)
            sleep_fun.(delay_ms)

            perform_request_with_retry(
              request_fun,
              tracker,
              method,
              path,
              params,
              headers,
              remaining_retry_delays_ms,
              sleep_fun,
              request_fields,
              attempt + 1
            )

          :error ->
            error
        end
    end
  end

  defp endpoint(%{endpoint: endpoint}) when is_binary(endpoint) and endpoint != "", do: endpoint

  @spec default_request(map()) :: {:ok, Req.Response.t()} | {:error, term()}
  def default_request(%{
        method: "GET",
        url: url,
        headers: headers,
        params: params,
        timeout_ms: timeout_ms
      }) do
    Req.get(url,
      headers: headers,
      params: params,
      receive_timeout: timeout_ms,
      connect_options: [timeout: timeout_ms]
    )
  end

  def default_request(%{
        method: "POST",
        url: url,
        headers: headers,
        params: params,
        timeout_ms: timeout_ms
      }) do
    Req.post(url,
      headers: headers,
      form: params,
      receive_timeout: timeout_ms,
      connect_options: [timeout: timeout_ms]
    )
  end

  defp request_headers(tracker) do
    with api_key when is_binary(api_key) and api_key != "" <- TrackerConfig.api_key(tracker),
         api_secret when is_binary(api_secret) and api_secret != "" <- TrackerConfig.api_secret(tracker) do
      credentials = Base.encode64("#{api_key}:#{api_secret}")

      {:ok,
       [
         {"Authorization", "Basic " <> credentials},
         {"Accept", "application/json"}
       ]}
    else
      _credentials ->
        {:error, :missing_tapd_credentials}
    end
  end

  defp workspace_id(tracker) do
    case Tracker.project_id(tracker) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, :missing_tapd_workspace_id}
    end
  end

  defp validate_workspace_param(params) when is_map(params) do
    if Map.has_key?(params, "workspace_id") do
      {:error, :workspace_id_must_not_be_supplied}
    else
      :ok
    end
  end

  defp validate_flat_scalar_params(params) when is_map(params) do
    if Enum.all?(params, fn {_key, value} -> scalar_param?(value) end) do
      :ok
    else
      {:error, :invalid_tapd_params}
    end
  end

  defp normalize_method(method) do
    case String.upcase(String.trim(method)) do
      "GET" -> {:ok, "GET"}
      "POST" -> {:ok, "POST"}
      _method -> {:error, :unsupported_tapd_method}
    end
  end

  defp normalize_params(params) when is_map(params), do: normalize_keys_to_strings(params)
  defp normalize_params(_params), do: %{}

  defp tracker_request_fields(tracker, method, path, params) do
    %{
      component: "tracker.tapd.client",
      tracker_kind: Map.get(tracker, :kind, @provider_kind),
      http_method: method,
      http_path: path,
      issue_id: request_issue_id(params),
      payload_summary: Redaction.summarize(params)
    }
  end

  defp emit_tracker_request_started(fields) when is_map(fields) do
    ObservabilityLogger.emit(:info, :tracker_request_started, fields)
    :ok
  end

  defp emit_tracker_request_retry(fields, reason, attempt, delay_ms)
       when is_map(fields) and is_integer(attempt) and is_integer(delay_ms) do
    ObservabilityLogger.emit(
      :warning,
      :tracker_request_retry_scheduled,
      Map.merge(fields, %{
        retry_attempt: attempt,
        retry_in_ms: delay_ms,
        status: Response.error_status(reason),
        error: inspect(reason)
      })
    )
  end

  defp request_issue_id(params) when is_map(params) do
    Map.get(params, "id") ||
      Map.get(params, "story_id") ||
      Map.get(params, "entry_id") ||
      Map.get(params, "src_story_id") ||
      Map.get(params, "target_story_id")
  end

  defp pop_retry_delay({:tapd_http_status, status, _body}, [delay_ms | remaining_retry_delays_ms])
       when status in @retryable_http_statuses and is_integer(delay_ms) and delay_ms >= 0 do
    {:ok, delay_ms, remaining_retry_delays_ms}
  end

  defp pop_retry_delay(_reason, _retry_delays_ms), do: :error

  defp elapsed_ms(started_at_ms) when is_integer(started_at_ms) do
    max(System.monotonic_time(:millisecond) - started_at_ms, 0)
  end

  defp normalize_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp scalar_param?(value)
       when is_binary(value) or is_integer(value) or is_float(value) or is_boolean(value),
       do: true

  defp scalar_param?(nil), do: true
  defp scalar_param?(_value), do: false
end

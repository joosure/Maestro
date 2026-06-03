defmodule SymphonyElixir.AgentProvider.OpenCode.AppServer.HttpRequests do
  @moduledoc false

  require Logger

  alias SymphonyElixir.AgentProvider.OpenCode.AppServer.{Diagnostics, Paths}

  @poll_interval_ms 250

  @spec build_request(String.t(), pos_integer()) :: Req.Request.t()
  def build_request(base_url, read_timeout_ms) when is_binary(base_url) and is_integer(read_timeout_ms) do
    Req.new(
      base_url: base_url,
      retry: false,
      receive_timeout: read_timeout_ms,
      connect_options: [timeout: read_timeout_ms],
      headers: %{"accept" => "application/json"}
    )
  end

  @spec await_health(Req.Request.t(), map()) :: :ok | {:error, term()}
  def await_health(request, context) when is_map(context) do
    deadline = monotonic_ms() + Map.fetch!(context, :read_timeout_ms)
    await_health_until(request, deadline, context)
  end

  @spec create_session(Req.Request.t(), Path.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def create_session(request, workspace, context) when is_binary(workspace) and is_map(context) do
    case Req.post(request, url: Paths.session(), json: %{"title" => Path.basename(workspace)}) do
      {:ok, %{status: status, body: %{"id" => session_id}}} when status in 200..299 and is_binary(session_id) ->
        {:ok, session_id}

      {:ok, %{status: status, body: body}} ->
        {:error, request_http_error(:session_create_http_error, "POST", Paths.session(), status, body, context)}

      {:error, reason} ->
        {:error, request_transport_error(:session_create_transport_error, "POST", Paths.session(), reason, context)}
    end
  end

  @spec abort_session(map()) :: :ok
  def abort_session(session) when is_map(session) do
    case Req.post(session.request, url: Paths.session_abort(session.session_id), json: %{}) do
      {:ok, _response} -> :ok
      {:error, reason} -> Logger.debug("OpenCode abort failed: #{inspect(reason)}")
    end

    :ok
  end

  defp await_health_until(request, deadline_ms, context) do
    case Req.get(request, url: Paths.global_health()) do
      {:ok, %{status: 200, body: %{"healthy" => true}}} ->
        :ok

      {:ok, response} ->
        sleep_or_timeout(deadline_ms, fn -> {:error, healthcheck_response_error(context, response)} end, fn ->
          await_health_until(request, deadline_ms, context)
        end)

      {:error, reason} ->
        sleep_or_timeout(deadline_ms, fn -> {:error, healthcheck_transport_error(context, reason)} end, fn ->
          await_health_until(request, deadline_ms, context)
        end)
    end
  end

  defp healthcheck_response_error(context, %{status: status, body: body}) do
    {:healthcheck_timeout,
     Map.merge(context, %{
       method: "GET",
       path: Paths.global_health(),
       response_status: status,
       response_body: Diagnostics.preview_value(body),
       message: "OpenCode never reported healthy before read_timeout_ms elapsed"
     })}
  end

  defp healthcheck_transport_error(context, reason) do
    transport_reason = req_transport_reason(reason)

    kind =
      if transport_reason == :timeout,
        do: :healthcheck_timeout,
        else: :healthcheck_failed

    message =
      if transport_reason == :timeout,
        do: "OpenCode did not respond to GET /global/health before read_timeout_ms elapsed",
        else: "OpenCode healthcheck request failed"

    {kind,
     Map.merge(context, %{
       method: "GET",
       path: Paths.global_health(),
       transport_reason: transport_reason,
       cause: Diagnostics.preview_value(reason),
       message: message
     })}
  end

  defp request_http_error(kind, method, path, status, body, context) do
    {kind,
     Map.merge(context, %{
       method: method,
       path: path,
       response_status: status,
       response_body: Diagnostics.preview_value(body),
       message: "OpenCode returned HTTP #{status} for #{method} #{path}"
     })}
  end

  defp request_transport_error(kind, method, path, reason, context) do
    transport_reason = req_transport_reason(reason)

    timeout_label = "read_timeout_ms"

    message =
      if transport_reason == :timeout,
        do: "OpenCode did not respond to #{method} #{path} before #{timeout_label} elapsed",
        else: "OpenCode request failed for #{method} #{path}"

    {kind,
     Map.merge(context, %{
       method: method,
       path: path,
       transport_reason: transport_reason,
       cause: Diagnostics.preview_value(reason),
       message: message
     })}
  end

  defp req_transport_reason(%Req.TransportError{reason: reason}), do: reason
  defp req_transport_reason(_reason), do: nil

  defp sleep_or_timeout(deadline_ms, timeout_reason, next_fun) do
    if monotonic_ms() >= deadline_ms do
      timeout_reason.()
    else
      Process.sleep(@poll_interval_ms)
      next_fun.()
    end
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end

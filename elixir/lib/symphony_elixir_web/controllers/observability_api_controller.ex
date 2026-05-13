defmodule SymphonyElixirWeb.ObservabilityApiController do
  @moduledoc """
  JSON API for Symphony observability data.
  """

  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixirWeb.{Presenter, RuntimeConfig}

  @spec state(Conn.t(), map()) :: Conn.t()
  def state(conn, _params) do
    with_request_observability(conn, %{result_summary: "action=state"}, fn ->
      json(conn, Presenter.state_payload(orchestrator(), snapshot_timeout_ms()))
    end)
  end

  @spec issue(Conn.t(), map()) :: Conn.t()
  def issue(conn, %{"issue_identifier" => issue_identifier}) do
    with_request_observability(
      conn,
      %{issue_identifier: issue_identifier, result_summary: "action=issue"},
      fn ->
        case Presenter.issue_payload(issue_identifier, orchestrator(), snapshot_timeout_ms()) do
          {:ok, payload} ->
            json(conn, payload)

          {:error, :issue_not_found} ->
            error_response(conn, 404, "issue_not_found", "Issue not found")
        end
      end
    )
  end

  @spec refresh(Conn.t(), map()) :: Conn.t()
  def refresh(conn, _params) do
    with_request_observability(conn, %{result_summary: "action=refresh"}, fn ->
      case Presenter.refresh_payload(orchestrator()) do
        {:ok, payload} ->
          conn
          |> put_status(202)
          |> json(payload)

        {:error, :unavailable} ->
          error_response(conn, 503, "orchestrator_unavailable", "Orchestrator is unavailable")
      end
    end)
  end

  @spec method_not_allowed(Conn.t(), map()) :: Conn.t()
  def method_not_allowed(conn, _params) do
    with_request_observability(conn, %{result_summary: "action=method_not_allowed"}, fn ->
      error_response(conn, 405, "method_not_allowed", "Method not allowed")
    end)
  end

  @spec not_found(Conn.t(), map()) :: Conn.t()
  def not_found(conn, _params) do
    with_request_observability(conn, %{result_summary: "action=not_found"}, fn ->
      error_response(conn, 404, "not_found", "Route not found")
    end)
  end

  defp error_response(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end

  defp orchestrator do
    RuntimeConfig.orchestrator()
  end

  defp snapshot_timeout_ms do
    RuntimeConfig.snapshot_timeout_ms()
  end

  defp with_request_observability(conn, extra_fields, fun) when is_function(fun, 0) do
    started_at_ms = System.monotonic_time(:millisecond)

    try do
      response_conn = fun.()

      emit_request_event(
        :info,
        :observability_api_request_completed,
        response_conn,
        started_at_ms,
        extra_fields
      )

      response_conn
    rescue
      error ->
        emit_request_failure(conn, started_at_ms, error, extra_fields)
        reraise(error, __STACKTRACE__)
    catch
      kind, reason ->
        emit_request_failure(conn, started_at_ms, {kind, reason}, extra_fields)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp emit_request_event(level, event, conn, started_at_ms, extra_fields) do
    status = conn.status || 200
    duration_ms = elapsed_ms(started_at_ms)

    fields =
      %{
        component: "observability.api",
        http_method: conn.method,
        http_path: conn.request_path,
        status: status,
        duration_ms: duration_ms,
        message: request_message(event, conn.method, conn.request_path, status, duration_ms, extra_fields)
      }
      |> Map.merge(extra_fields)

    ObservabilityLogger.emit(level, event, fields)
  end

  defp emit_request_failure(conn, started_at_ms, error, extra_fields) do
    duration_ms = elapsed_ms(started_at_ms)
    formatted_error = format_error(error)

    ObservabilityLogger.emit(
      :error,
      :observability_api_request_failed,
      extra_fields
      |> Map.merge(%{
        component: "observability.api",
        http_method: conn.method,
        http_path: conn.request_path,
        duration_ms: duration_ms,
        error: formatted_error,
        message: request_failure_message(conn.method, conn.request_path, duration_ms, formatted_error, extra_fields)
      })
    )
  end

  defp request_message(event, method, path, status, duration_ms, extra_fields) do
    issue_suffix =
      case Map.get(extra_fields, :issue_identifier) do
        nil -> ""
        issue_identifier -> " issue_identifier=#{issue_identifier}"
      end

    "#{event} method=#{method} path=#{path} status=#{status} duration_ms=#{duration_ms}#{issue_suffix}"
  end

  defp request_failure_message(method, path, duration_ms, error, extra_fields) do
    issue_suffix =
      case Map.get(extra_fields, :issue_identifier) do
        nil -> ""
        issue_identifier -> " issue_identifier=#{issue_identifier}"
      end

    "observability_api_request_failed method=#{method} path=#{path} duration_ms=#{duration_ms}#{issue_suffix} error=#{error}"
  end

  defp elapsed_ms(started_at_ms) when is_integer(started_at_ms) do
    max(System.monotonic_time(:millisecond) - started_at_ms, 0)
  end

  defp format_error(error) when is_exception(error), do: Exception.format_banner(:error, error)
  defp format_error(error), do: inspect(error)
end

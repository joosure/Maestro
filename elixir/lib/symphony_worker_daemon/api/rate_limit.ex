defmodule SymphonyWorkerDaemon.Api.RateLimit do
  @moduledoc false

  import Plug.Conn, only: [halt: 1, put_resp_header: 3]

  alias SymphonyWorkerDaemon.Api.{Audit, Response}
  alias SymphonyWorkerDaemon.RateLimiter

  @default_rate_limit_window_ms 60_000
  @default_unauthenticated_rate_limit 120
  @default_api_rate_limit 600
  @default_session_create_rate_limit 60

  @spec reject_auth_failed(Plug.Conn.t()) :: Plug.Conn.t()
  def reject_auth_failed(conn) do
    case decision(conn, :auth_failed, remote_ip_key(conn), :unauthenticated_rate_limit) do
      :ok ->
        conn
        |> Response.json(401, Response.error_payload("auth_failed", "invalid bearer token", false))
        |> halt()

      {:error, {:rate_limited, _retry_after_ms, _limit, _window_ms} = reason} ->
        Audit.rate_limited(conn, principal(conn), :auth_failed, reason)

        conn
        |> rate_limited_response(reason)
        |> halt()
    end
  end

  @spec throttle_authenticated(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def throttle_authenticated(conn, opts) when is_list(opts) do
    conn
    |> apply_limit(:api_request, principal_rate_key(conn), :api_rate_limit)
    |> maybe_apply_session_create(opts)
  end

  @spec health(keyword()) :: map()
  def health(opts) when is_list(opts) do
    rate_limiter = Keyword.get(opts, :rate_limiter)

    opts
    |> policy()
    |> Map.merge(RateLimiter.status(rate_limiter))
  end

  @spec policy(keyword()) :: map()
  def policy(opts) when is_list(opts) do
    %{
      window_ms: positive_integer(opts, :rate_limit_window_ms, @default_rate_limit_window_ms),
      unauthenticated_rate_limit: positive_integer(opts, :unauthenticated_rate_limit, @default_unauthenticated_rate_limit),
      api_rate_limit: positive_integer(opts, :api_rate_limit, @default_api_rate_limit),
      session_create_rate_limit: positive_integer(opts, :session_create_rate_limit, @default_session_create_rate_limit)
    }
  end

  defp apply_limit(%Plug.Conn{halted: true} = conn, _scope, _key, _limit_key), do: conn

  defp apply_limit(conn, scope, key, limit_key) do
    case decision(conn, scope, key, limit_key) do
      :ok ->
        conn

      {:error, {:rate_limited, _retry_after_ms, _limit, _window_ms} = reason} ->
        Audit.rate_limited(conn, principal(conn), scope, reason)

        conn
        |> rate_limited_response(reason)
        |> halt()
    end
  end

  defp maybe_apply_session_create(%Plug.Conn{halted: true} = conn, _opts), do: conn

  defp maybe_apply_session_create(conn, opts) do
    session_create_path = Keyword.fetch!(opts, :session_create_path)

    if session_create_request?(conn, session_create_path) do
      apply_limit(conn, :session_create, principal_rate_key(conn), :session_create_rate_limit)
    else
      conn
    end
  end

  defp decision(conn, scope, key, limit_key) do
    opts = runtime_opts(conn)

    opts
    |> Keyword.get(:rate_limiter)
    |> RateLimiter.check(scope, key,
      limit: rate_limit_value(opts, limit_key),
      window_ms: positive_integer(opts, :rate_limit_window_ms, @default_rate_limit_window_ms)
    )
  end

  defp rate_limit_value(opts, key) when is_list(opts) do
    default =
      case key do
        :unauthenticated_rate_limit -> @default_unauthenticated_rate_limit
        :api_rate_limit -> @default_api_rate_limit
        :session_create_rate_limit -> @default_session_create_rate_limit
      end

    positive_integer(opts, key, default)
  end

  defp rate_limited_response(conn, {:rate_limited, retry_after_ms, limit, window_ms}) do
    conn
    |> put_resp_header("retry-after", retry_after_seconds(retry_after_ms))
    |> Response.json(
      429,
      Response.error_payload(
        "rate_limited",
        %{
          retry_after_ms: retry_after_ms,
          limit: limit,
          window_ms: window_ms
        },
        true
      )
    )
  end

  defp retry_after_seconds(retry_after_ms) when is_integer(retry_after_ms) do
    retry_after_ms
    |> Kernel.+(999)
    |> div(1_000)
    |> max(1)
    |> Integer.to_string()
  end

  defp session_create_request?(%Plug.Conn{method: "POST", request_path: path}, session_create_path), do: path == session_create_path
  defp session_create_request?(_conn, _session_create_path), do: false

  defp principal_rate_key(conn) do
    principal = principal(conn)

    %{
      owner: Map.get(principal, :owner),
      tenant_id: Map.get(principal, :tenant_id),
      auth_mode: Map.get(principal, :auth_mode)
    }
  end

  defp remote_ip_key(conn), do: Audit.remote_ip(conn.remote_ip) || "unknown"

  defp runtime_opts(conn), do: conn.assigns[:worker_daemon_opts] || []

  defp principal(conn), do: conn.assigns[:worker_daemon_principal] || %{owner: "symphony", roles: ["admin"]}

  defp positive_integer(opts, key, default) when is_list(opts) and is_integer(default) and default > 0 do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      _value -> default
    end
  end
end

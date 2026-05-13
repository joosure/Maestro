defmodule SymphonyElixir.HttpServer do
  @moduledoc """
  Starts the Phoenix observability endpoint when enabled.
  """

  alias SymphonyElixir.{Config, Orchestrator}
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  @endpoint Module.concat(["SymphonyElixirWeb", "Endpoint"])
  @secret_key_bytes 48

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start() | :ignore
  def start_link(opts \\ []) do
    host = Keyword.get(opts, :host, Config.settings!().server.host)
    snapshot_timeout_ms = Keyword.get(opts, :snapshot_timeout_ms, 15_000)

    case Keyword.get(opts, :port, Config.server_port()) do
      port when is_integer(port) and port >= 0 ->
        orchestrator = Keyword.get(opts, :orchestrator, Orchestrator)

        case parse_host(host) do
          {:ok, ip} ->
            endpoint_opts = [
              server: true,
              http: [ip: ip, port: port],
              url: [host: normalize_host(host)],
              orchestrator: orchestrator,
              snapshot_timeout_ms: snapshot_timeout_ms,
              secret_key_base: secret_key_base()
            ]

            endpoint_config =
              :symphony_elixir
              |> Application.get_env(@endpoint, [])
              |> Keyword.merge(endpoint_opts)

            Application.put_env(:symphony_elixir, @endpoint, endpoint_config)

            endpoint = @endpoint

            case endpoint.start_link() do
              {:ok, _pid} = result ->
                emit_http_server_event(
                  :info,
                  :http_server_started,
                  host,
                  port,
                  snapshot_timeout_ms,
                  %{result_summary: start_summary(host, port, snapshot_timeout_ms)}
                )

                result

              {:error, reason} = error ->
                emit_http_server_event(
                  :error,
                  :http_server_start_failed,
                  host,
                  port,
                  snapshot_timeout_ms,
                  %{error: inspect(reason)}
                )

                error
            end

          {:error, reason} = error ->
            emit_http_server_event(
              :error,
              :http_server_start_failed,
              host,
              port,
              snapshot_timeout_ms,
              %{error: inspect(reason)}
            )

            error
        end

      invalid_port ->
        emit_http_server_event(
          :info,
          :http_server_ignored,
          host,
          invalid_port,
          snapshot_timeout_ms,
          %{result_summary: "reason=invalid_port requested_port=#{inspect(invalid_port)}"}
        )

        :ignore
    end
  end

  @spec bound_port(term()) :: non_neg_integer() | nil
  def bound_port(_server \\ __MODULE__) do
    case Bandit.PhoenixAdapter.server_info(@endpoint, :http) do
      {:ok, {_ip, port}} when is_integer(port) -> port
      _ -> nil
    end
  rescue
    _error -> nil
  catch
    :exit, _reason -> nil
  end

  defp parse_host({_, _, _, _} = ip), do: {:ok, ip}
  defp parse_host({_, _, _, _, _, _, _, _} = ip), do: {:ok, ip}

  defp parse_host(host) when is_binary(host) do
    charhost = String.to_charlist(host)

    case :inet.parse_address(charhost) do
      {:ok, ip} ->
        {:ok, ip}

      {:error, _reason} ->
        case :inet.getaddr(charhost, :inet) do
          {:ok, ip} -> {:ok, ip}
          {:error, _reason} -> :inet.getaddr(charhost, :inet6)
        end
    end
  end

  defp normalize_host(host) when host in ["", nil], do: "127.0.0.1"
  defp normalize_host(host) when is_binary(host), do: host
  defp normalize_host(host), do: to_string(host)

  defp emit_http_server_event(level, event, host, port, snapshot_timeout_ms, extra_fields) do
    normalized_host = normalize_host(host)
    bound_port = bound_port()

    fields =
      %{
        component: "http_server",
        message: http_server_message(event, normalized_host, port, bound_port, snapshot_timeout_ms, extra_fields),
        result_summary: "host=#{normalized_host} requested_port=#{inspect(port)} bound_port=#{inspect(bound_port)} snapshot_timeout_ms=#{snapshot_timeout_ms}"
      }
      |> Map.merge(extra_fields)

    ObservabilityLogger.emit(level, event, fields)
  end

  defp http_server_message(event, host, port, bound_port, snapshot_timeout_ms, extra_fields) do
    summary =
      Map.get(
        extra_fields,
        :result_summary,
        "host=#{host} requested_port=#{inspect(port)} bound_port=#{inspect(bound_port)} snapshot_timeout_ms=#{snapshot_timeout_ms}"
      )

    error_suffix =
      case Map.get(extra_fields, :error) do
        nil -> ""
        error -> " error=#{error}"
      end

    "#{event} #{summary}#{error_suffix}"
  end

  defp start_summary(host, port, snapshot_timeout_ms) do
    normalized_host = normalize_host(host)
    "host=#{normalized_host} requested_port=#{inspect(port)} bound_port=#{inspect(bound_port() || port)} snapshot_timeout_ms=#{snapshot_timeout_ms}"
  end

  defp secret_key_base do
    Base.encode64(:crypto.strong_rand_bytes(@secret_key_bytes), padding: false)
  end
end

defmodule SymphonyWorkerDaemon.Api.RequestLimits do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2, halt: 1]

  import SymphonyWorkerDaemon.Api.Response, only: [error_payload: 3, json: 3]

  @default_max_header_bytes 16_384
  @default_max_request_body_bytes 1_048_576

  @spec default_max_request_body_bytes() :: pos_integer()
  def default_max_request_body_bytes, do: @default_max_request_body_bytes

  @spec parser_options() :: keyword()
  def parser_options do
    [
      parsers: [:json],
      pass: ["application/json"],
      json_decoder: Jason,
      length: default_max_request_body_bytes()
    ]
  end

  @spec reject_oversized_headers(Plug.Conn.t()) :: Plug.Conn.t()
  def reject_oversized_headers(conn) do
    max_bytes = conn |> runtime_opts() |> positive_integer(:max_header_bytes, @default_max_header_bytes)

    if header_bytes(conn.req_headers) > max_bytes do
      conn
      |> json(431, error_payload("headers_too_large", %{max_bytes: max_bytes}, false))
      |> halt()
    else
      conn
    end
  end

  @spec reject_oversized_content_length(Plug.Conn.t()) :: Plug.Conn.t()
  def reject_oversized_content_length(conn) do
    max_bytes = conn |> runtime_opts() |> positive_integer(:max_request_body_bytes, @default_max_request_body_bytes)

    case content_length(conn) do
      bytes when is_integer(bytes) and bytes > max_bytes ->
        conn
        |> json(413, error_payload("payload_too_large", %{field: "body", size: bytes, max_bytes: max_bytes}, false))
        |> halt()

      _bytes ->
        conn
    end
  end

  defp runtime_opts(conn), do: conn.assigns[:worker_daemon_opts] || []

  defp positive_integer(opts, key, default) when is_list(opts) and is_integer(default) and default > 0 do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      _value -> default
    end
  end

  defp header_bytes(headers) when is_list(headers) do
    Enum.reduce(headers, 0, fn {key, value}, acc -> acc + byte_size(to_string(key)) + byte_size(to_string(value)) + 4 end)
  end

  defp content_length(conn) do
    conn
    |> get_req_header("content-length")
    |> List.first()
    |> parse_non_negative_integer()
  end

  defp parse_non_negative_integer(nil), do: nil

  defp parse_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer >= 0 -> integer
      _invalid -> nil
    end
  end
end

defmodule SymphonyWorkerDaemon.BridgeProxy.RouterPlug do
  @moduledoc false

  use Plug.Router

  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Platform.DynamicToolBridgeContract
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @execute_path DynamicToolBridgeContract.execute_path()
  @execute_suffix DynamicToolBridgeContract.execute_suffix()
  @default_max_header_bytes 16_384
  @default_max_request_body_bytes 1_048_576

  plug(:match)
  plug(:reject_oversized_headers)
  plug(:reject_oversized_content_length)
  plug(:authenticate)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason, length: @default_max_request_body_bytes)
  plug(:dispatch)

  post @execute_path do
    opts = conn.assigns.bridge_proxy_opts
    upstream_url = Keyword.fetch!(opts, :upstream_base_url) <> @execute_suffix
    upstream_token = Keyword.fetch!(opts, :upstream_token)
    requester = Keyword.fetch!(opts, :requester)
    timeout_ms = Keyword.fetch!(opts, :timeout_ms)

    case requester.(:post, upstream_url, upstream_headers(upstream_token), body_params(conn), %{timeout_ms: timeout_ms}) do
      {:ok, status, payload} when status in 200..599 ->
        json(conn, status, payload || %{})

      {:error, reason} ->
        json(conn, 502, error_payload("dynamic_tool_bridge_proxy_failed", reason))
    end
  end

  match _ do
    json(conn, 404, error_payload("dynamic_tool_bridge_proxy_not_found", conn.request_path))
  end

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> Plug.Conn.assign(:bridge_proxy_opts, opts)
    |> super(opts)
  end

  @spec authenticate(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def authenticate(conn, _opts) do
    session_token = Keyword.fetch!(conn.assigns.bridge_proxy_opts, :session_token)

    if bearer_token(conn) == session_token do
      conn
    else
      conn
      |> json(401, error_payload("dynamic_tool_bridge_proxy_unauthorized", "invalid bearer token"))
      |> halt()
    end
  end

  @spec reject_oversized_headers(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def reject_oversized_headers(conn, _opts) do
    max_bytes = conn.assigns.bridge_proxy_opts |> Keyword.get(:max_header_bytes, @default_max_header_bytes) |> positive_integer(@default_max_header_bytes)

    if header_bytes(conn.req_headers) > max_bytes do
      conn
      |> json(431, error_payload("dynamic_tool_bridge_proxy_headers_too_large", "headers too large"))
      |> halt()
    else
      conn
    end
  end

  @spec reject_oversized_content_length(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def reject_oversized_content_length(conn, _opts) do
    max_bytes = conn.assigns.bridge_proxy_opts |> Keyword.get(:max_request_body_bytes, @default_max_request_body_bytes) |> positive_integer(@default_max_request_body_bytes)

    case content_length(conn) do
      bytes when is_integer(bytes) and bytes > max_bytes ->
        conn
        |> json(413, error_payload("dynamic_tool_bridge_proxy_payload_too_large", "payload too large"))
        |> halt()

      _bytes ->
        conn
    end
  end

  defp bearer_token(conn) do
    conn
    |> get_req_header("authorization")
    |> List.first()
    |> case do
      "Bearer " <> token -> String.trim(token)
      "bearer " <> token -> String.trim(token)
      _header -> nil
    end
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

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

  defp upstream_headers(token) do
    [
      {"authorization", "Bearer " <> token},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]
  end

  defp body_params(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}}), do: %{}
  defp body_params(%Plug.Conn{body_params: params}) when is_map(params), do: params
  defp body_params(_conn), do: %{}

  defp json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end

  defp error_payload(code, details) do
    Response.error(code, safe_details(details))
  end

  defp safe_details(details) when is_binary(details), do: Redaction.redact_string(details)
  defp safe_details(details) when is_atom(details), do: Atom.to_string(details)
  defp safe_details(details), do: Redaction.summarize(details, 512)
end

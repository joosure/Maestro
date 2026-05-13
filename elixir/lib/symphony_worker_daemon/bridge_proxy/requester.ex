defmodule SymphonyWorkerDaemon.BridgeProxy.Requester do
  @moduledoc false

  @spec request(atom(), String.t(), [{String.t(), String.t()}], map() | nil, map()) ::
          {:ok, pos_integer(), term()} | {:error, term()}
  def request(method, url, headers, body, request_opts) do
    case validate_url(url) do
      :ok ->
        request =
          [
            method: method,
            url: url,
            headers: headers,
            retry: false,
            redirect: false,
            max_redirects: 0
          ]
          |> maybe_put_json(body)
          |> maybe_put_timeout(request_opts)

        case Req.request(request) do
          {:ok, %Req.Response{status: status, body: payload}} -> {:ok, status, payload}
          {:error, reason} -> {:error, reason}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_url(url) when is_binary(url) do
    uri = URI.parse(url)
    scheme = normalize_url_part(uri.scheme)
    host = normalize_url_part(uri.host)

    cond do
      scheme not in ["http", "https"] ->
        {:error, {:dynamic_tool_bridge_request_url_invalid, :scheme}}

      not is_binary(host) or host == "" ->
        {:error, {:dynamic_tool_bridge_request_url_invalid, :host}}

      is_binary(uri.userinfo) ->
        {:error, {:dynamic_tool_bridge_request_url_invalid, :userinfo}}

      is_binary(uri.query) ->
        {:error, {:dynamic_tool_bridge_request_url_invalid, :query}}

      is_binary(uri.fragment) ->
        {:error, {:dynamic_tool_bridge_request_url_invalid, :fragment}}

      true ->
        :ok
    end
  end

  defp validate_url(_url), do: {:error, {:dynamic_tool_bridge_request_url_invalid, :shape}}

  defp normalize_url_part(value) when is_binary(value), do: String.downcase(value)
  defp normalize_url_part(_value), do: nil

  defp maybe_put_json(request, body) when is_map(body), do: Keyword.put(request, :json, body)
  defp maybe_put_json(request, _body), do: request

  defp maybe_put_timeout(request, %{timeout_ms: timeout_ms}) when is_integer(timeout_ms) and timeout_ms > 0 do
    Keyword.merge(request, receive_timeout: timeout_ms, connect_options: [timeout: timeout_ms])
  end

  defp maybe_put_timeout(request, _request_opts), do: request
end

defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.Transport do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.Endpoint
  alias SymphonyWorkerDaemon.Protocol

  @type requester ::
          (atom(), String.t(), [{String.t(), String.t()}], map() | nil, map() ->
             {:ok, pos_integer(), term()} | {:error, term()})

  @type request_result :: {:ok, term()} | {:error, term()}

  @spec request(atom(), String.t(), String.t(), String.t() | nil, map() | nil, keyword()) :: request_result()
  def request(method, endpoint, path, token, body, opts)
      when method in [:get, :post, :delete] and is_binary(endpoint) and is_binary(path) and is_list(opts) do
    requester = Keyword.get(opts, :worker_daemon_requester, &__MODULE__.default_requester/5)
    url = endpoint <> path
    headers = headers(token)
    request_opts = request_options(opts)

    case requester.(method, url, headers, body, request_opts) do
      {:ok, status, payload} when status in 200..299 ->
        {:ok, payload || %{}}

      {:ok, status, payload} ->
        {:error, Protocol.error_reason(method, status, payload)}

      {:error, reason} ->
        {:error, {:worker_daemon_request_failed, method, Endpoint.safe(url), reason}}
    end
  end

  @spec default_requester(atom(), String.t(), [{String.t(), String.t()}], map() | nil, map()) ::
          {:ok, pos_integer(), term()} | {:error, term()}
  def default_requester(method, url, headers, body, request_opts) do
    request =
      [
        method: method,
        url: url,
        headers: headers,
        retry: false
      ]
      |> maybe_put_json(body)
      |> maybe_put_timeout(request_opts)

    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: payload}} -> {:ok, status, payload}
      {:error, reason} -> {:error, reason}
    end
  end

  defp headers(nil) do
    [
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]
  end

  defp headers(token) when is_binary(token) do
    [{"authorization", "Bearer " <> token} | headers(nil)]
  end

  defp request_options(opts) do
    %{
      timeout_ms: positive_integer(opts, :worker_daemon_timeout_ms)
    }
  end

  defp maybe_put_json(request, body) when is_map(body), do: Keyword.put(request, :json, body)
  defp maybe_put_json(request, _body), do: request

  defp maybe_put_timeout(request, %{timeout_ms: timeout_ms})
       when is_integer(timeout_ms) and timeout_ms > 0 do
    Keyword.merge(request, receive_timeout: timeout_ms, connect_options: [timeout: timeout_ms])
  end

  defp maybe_put_timeout(request, _request_opts), do: request

  defp positive_integer(opts, key) when is_list(opts) do
    case Keyword.get(opts, key) do
      value when is_integer(value) and value > 0 -> value
      _value -> nil
    end
  end
end

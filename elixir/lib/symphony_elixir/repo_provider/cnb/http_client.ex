defmodule SymphonyElixir.RepoProvider.CNB.HttpClient do
  @moduledoc """
  HTTP infrastructure for the CNB repo-provider adapter.

  Encapsulates request construction, retry/backoff, authentication,
  URL building, and runtime configuration parsing. All functions are
  pure (no side-effects beyond the HTTP call itself) and designed to
  be called from `CNB.Adapter`.
  """

  @default_api_base_url "https://api.cnb.cool"
  @default_web_base_url "https://cnb.cool"
  @default_http_timeout_seconds 10
  @default_max_http_retries 3
  @default_retry_backoff_seconds 1
  @retryable_statuses [408, 425, 429, 500, 502, 503, 504]

  alias SymphonyElixir.RepoProvider.CNB.RuntimeEnv
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig

  @type repo_config :: map()
  @type request_result ::
          {:ok, pos_integer(), term()}
          | {:error, {:cnb_api_status, atom(), String.t(), pos_integer(), term()}}
          | {:error, {:cnb_api_request, atom(), String.t(), term()}}

  # ── Token & Requester ──────────────────────────────────────────

  @spec access_token(keyword()) :: {:ok, String.t()} | {:error, :missing_cnb_token}
  def access_token(opts) do
    case opts[:token] || RuntimeEnv.token() do
      token when is_binary(token) and token != "" -> {:ok, token}
      _other -> {:error, :missing_cnb_token}
    end
  end

  @spec requester(keyword()) :: function()
  def requester(opts), do: Keyword.get(opts, :requester, &default_requester/5)

  # ── Request execution ──────────────────────────────────────────

  @spec request_json(repo_config(), function(), atom(), String.t(), String.t(), map() | nil) ::
          request_result()
  def request_json(repo, requester_fn, method, url, token, body) do
    headers = [
      {"authorization", "Bearer " <> token},
      {"accept", "application/vnd.cnb.api+json"},
      {"content-type", "application/json"}
    ]

    request_opts = request_options(repo, method)

    case :erlang.fun_info(requester_fn, :arity) do
      {:arity, 5} ->
        requester_fn.(method, url, headers, body, request_opts)

      {:arity, 4} ->
        requester_fn.(method, url, headers, body)

      {:arity, arity} ->
        raise ArgumentError, "CNB requester must have arity 4 or 5, got: #{arity}"
    end
  end

  @spec get_json(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_json(repo, endpoint, token, opts) do
    requester_fn = requester(opts)
    url = "#{api_base_url(repo)}#{endpoint}"

    case request_json(repo, requester_fn, :get, url, token, nil) do
      {:ok, _status, payload} when is_map(payload) ->
        {:ok, payload}

      {:ok, _status, payload} ->
        {:error, {:cnb_unknown_payload, :get_json, payload}}

      {:error, _reason} = error ->
        error
    end
  end

  @spec fetch_repo_json(repo_config(), String.t(), String.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def fetch_repo_json(repo, repository, token, suffix, query, opts) do
    requester_fn = requester(opts)
    url = repo_url(repo, repository, suffix, query)

    case request_json(repo, requester_fn, :get, url, token, nil) do
      {:ok, _status, payload} when is_map(payload) ->
        {:ok, payload}

      {:ok, _status, payload} ->
        {:error, {:cnb_unknown_payload, suffix, payload}}

      {:error, _reason} = error ->
        error
    end
  end

  @spec request_repo_payload(
          repo_config(),
          String.t(),
          String.t(),
          atom(),
          String.t(),
          map(),
          map() | nil,
          keyword()
        ) :: {:ok, term()} | {:error, term()}
  def request_repo_payload(repo, repository, token, method, suffix, query, body, opts) do
    requester_fn = requester(opts)
    url = repo_url(repo, repository, suffix, query)

    case request_json(repo, requester_fn, method, url, token, body) do
      {:ok, _status, payload} ->
        {:ok, payload}

      {:error, _reason} = error ->
        error
    end
  end

  @spec request_api_payload(repo_config(), String.t(), atom(), String.t(), map(), map() | nil, keyword()) ::
          {:ok, term()} | {:error, term()}
  def request_api_payload(repo, token, method, endpoint, query, body, opts) do
    requester_fn = requester(opts)
    url = api_url(repo, endpoint, query)

    case request_json(repo, requester_fn, method, url, token, body) do
      {:ok, _status, payload} ->
        {:ok, payload}

      {:error, _reason} = error ->
        error
    end
  end

  # ── Default requester (Req-based) ──────────────────────────────

  @spec default_requester(atom(), String.t(), list(), map() | nil, map()) :: request_result()
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

    request_with_retry(method, url, request, Map.get(request_opts, :retry_delays_ms, []))
  end

  defp maybe_put_json(request, body) when is_map(body), do: Keyword.put(request, :json, body)
  defp maybe_put_json(request, _body), do: request

  defp maybe_put_timeout(request, %{timeout_ms: timeout_ms})
       when is_integer(timeout_ms) and timeout_ms > 0 do
    Keyword.merge(request, receive_timeout: timeout_ms, connect_options: [timeout: timeout_ms])
  end

  defp maybe_put_timeout(request, _request_opts), do: request

  defp request_with_retry(method, url, request, retry_delays_ms) do
    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, status, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        maybe_retry_status(method, url, request, retry_delays_ms, status, body)

      {:error, reason} ->
        maybe_retry_request(method, url, request, retry_delays_ms, reason)
    end
  end

  defp maybe_retry_status(:get, url, request, [delay_ms | remaining], status, _body)
       when status in @retryable_statuses do
    Process.sleep(delay_ms)
    request_with_retry(:get, url, request, remaining)
  end

  defp maybe_retry_status(method, url, _request, _retry_delays_ms, status, body) do
    {:error, {:cnb_api_status, method, url, status, body}}
  end

  defp maybe_retry_request(:get, url, request, [delay_ms | remaining], _reason) do
    Process.sleep(delay_ms)
    request_with_retry(:get, url, request, remaining)
  end

  defp maybe_retry_request(method, url, _request, _retry_delays_ms, reason) do
    {:error, {:cnb_api_request, method, url, reason}}
  end

  # ── Request options & runtime config ───────────────────────────

  @spec request_options(repo_config(), atom()) :: map()
  def request_options(repo, method) do
    %{
      timeout_ms:
        positive_runtime_seconds(repo, :http_timeout_seconds, @default_http_timeout_seconds) *
          1_000,
      retry_delays_ms: retry_delays_ms(repo, method)
    }
  end

  defp retry_delays_ms(_repo, method) when method != :get, do: []

  defp retry_delays_ms(repo, :get) do
    retry_count = non_negative_runtime_seconds(repo, :max_http_retries, @default_max_http_retries)

    backoff_ms =
      non_negative_runtime_seconds(repo, :retry_backoff_seconds, @default_retry_backoff_seconds) *
        1_000

    List.duplicate(backoff_ms, retry_count)
  end

  @spec positive_runtime_seconds(repo_config(), atom(), pos_integer()) :: pos_integer()
  defp positive_runtime_seconds(repo, key, default) do
    case runtime_integer(repo, key) do
      value when is_integer(value) and value > 0 -> value
      _other -> default
    end
  end

  @spec non_negative_runtime_seconds(repo_config(), atom(), non_neg_integer()) :: non_neg_integer()
  defp non_negative_runtime_seconds(repo, key, default) do
    case runtime_integer(repo, key) do
      value when is_integer(value) and value >= 0 -> value
      _other -> default
    end
  end

  defp runtime_integer(repo, key) when is_atom(key),
    do: repo |> RepoConfig.runtime_value(Atom.to_string(key)) |> parse_runtime_integer()

  defp parse_runtime_integer(value) when is_integer(value), do: value

  defp parse_runtime_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp parse_runtime_integer(_value), do: nil

  # ── URL builders ───────────────────────────────────────────────

  @spec api_base_url(repo_config()) :: String.t()
  def api_base_url(repo) do
    case RepoConfig.api_base_url(repo) do
      api_base_url when is_binary(api_base_url) and api_base_url != "" -> api_base_url
      _other -> @default_api_base_url
    end
  end

  @spec web_base_url(repo_config()) :: String.t()
  def web_base_url(repo) do
    case RepoConfig.web_base_url(repo) do
      web_base_url when is_binary(web_base_url) and web_base_url != "" -> web_base_url
      _other -> @default_web_base_url
    end
  end

  @spec pr_url(repo_config(), String.t(), term()) :: String.t()
  def pr_url(repo, repository, number) do
    "#{String.trim_trailing(web_base_url(repo), "/")}/#{repository}/-/pulls/#{number}"
  end

  @spec repo_url(repo_config(), String.t(), String.t(), map()) :: String.t()
  def repo_url(repo, repository, suffix, query) do
    base = "#{api_base_url(repo)}/#{URI.encode(repository, &URI.char_unreserved?/1)}#{suffix}"
    qs = query_string(query)

    if qs == "" do
      base
    else
      base <> "?" <> qs
    end
  end

  @spec api_url(repo_config(), String.t(), map()) :: String.t()
  def api_url(repo, endpoint, query) do
    base =
      cond do
        String.starts_with?(endpoint, ["http://", "https://"]) ->
          endpoint

        String.starts_with?(endpoint, "/") ->
          String.trim_trailing(api_base_url(repo), "/") <> endpoint

        true ->
          "#{String.trim_trailing(api_base_url(repo), "/")}/#{String.trim_leading(endpoint, "/")}"
      end

    qs = query_string(query)

    cond do
      qs == "" -> base
      String.contains?(base, "?") -> base <> "&" <> qs
      true -> base <> "?" <> qs
    end
  end

  @spec query_string(map() | term()) :: String.t()
  def query_string(query) when is_map(query) do
    query
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> URI.encode_query()
  end

  def query_string(_query), do: ""
end

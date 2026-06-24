defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox.Options do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox.Error

  @default_queue_limit 1_000
  @default_drain_limit 100

  @spec default_queue_limit() :: pos_integer()
  def default_queue_limit, do: @default_queue_limit

  @spec default_drain_limit() :: pos_integer()
  def default_drain_limit, do: @default_drain_limit

  @spec keyword_opts(term(), atom()) :: {:ok, keyword()} | {:error, map()}
  def keyword_opts(opts, _reason) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, Error.invalid_options(:options_not_keyword, opts)}
    end
  end

  def keyword_opts(opts, reason) when is_atom(reason), do: {:error, Error.invalid_options(reason, opts)}

  @spec start_opts(keyword()) :: {:ok, keyword()} | {:error, map()}
  def start_opts(opts) when is_list(opts) do
    with {:ok, queue_limit} <- positive_integer_opt(opts, :queue_limit, @default_queue_limit, :invalid_queue_limit),
         {:ok, opts} <- optional_non_negative_integer_opt(opts, :max_defer_count, :invalid_max_defer_count),
         {:ok, opts} <- optional_non_negative_integer_opt(opts, :max_defer_age_ms, :invalid_max_defer_age_ms) do
      {:ok, Keyword.put(opts, :queue_limit, queue_limit)}
    end
  end

  def start_opts(opts), do: {:error, Error.invalid_options(:options_not_keyword, opts)}

  @spec server(keyword(), module()) :: {:ok, pid() | atom()} | {:error, map()}
  def server(opts, default) when is_list(opts) and is_atom(default) do
    opts
    |> Keyword.get(:server, default)
    |> case do
      server when is_pid(server) or is_atom(server) -> {:ok, server}
      server -> {:error, Error.invalid_server(server)}
    end
  end

  @spec issue_ids(term()) :: {:ok, [String.t()], non_neg_integer()} | {:error, map()}
  def issue_ids(values) when is_list(values) do
    {issue_ids, invalid_count} =
      Enum.reduce(values, {[], 0}, fn
        value, {issue_ids, invalid_count} when is_binary(value) ->
          case String.trim(value) do
            "" -> {issue_ids, invalid_count + 1}
            trimmed -> {[trimmed | issue_ids], invalid_count}
          end

        _value, {issue_ids, invalid_count} ->
          {issue_ids, invalid_count + 1}
      end)

    {:ok, Enum.reverse(issue_ids), invalid_count}
  end

  def issue_ids(values), do: {:error, Error.invalid_issue_ids(values)}

  @spec queue_limit(keyword()) :: {:ok, pos_integer()} | {:error, map()}
  def queue_limit(opts) when is_list(opts) do
    positive_integer_opt(opts, :queue_limit, @default_queue_limit, :invalid_queue_limit)
  end

  @spec drain_limit(keyword()) :: {:ok, pos_integer()} | {:error, map()}
  def drain_limit(opts) when is_list(opts) do
    positive_integer_opt(opts, :limit, @default_drain_limit, :invalid_drain_limit)
  end

  @spec defer_policy(keyword()) :: {:ok, map()} | {:error, map()}
  def defer_policy(opts) when is_list(opts) do
    with {:ok, now_ms} <- integer_opt(opts, :now_ms, System.monotonic_time(:millisecond), :invalid_now_ms),
         {:ok, max_defer_count} <- optional_non_negative_integer_value(opts, :max_defer_count, :invalid_max_defer_count),
         {:ok, max_defer_age_ms} <- optional_non_negative_integer_value(opts, :max_defer_age_ms, :invalid_max_defer_age_ms) do
      policy =
        %{
          now_ms: now_ms,
          reason: Keyword.get(opts, :reason),
          route: Keyword.get(opts, :route)
        }
        |> maybe_put(:max_defer_count, max_defer_count)
        |> maybe_put(:max_defer_age_ms, max_defer_age_ms)

      {:ok, policy}
    end
  end

  defp positive_integer_opt(opts, key, default, reason) when is_list(opts) and is_atom(key) and is_integer(default) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_integer(value) and value > 0 ->
        {:ok, value}

      {:ok, value} ->
        {:error, Error.invalid_options(reason, value)}

      :error ->
        {:ok, default}
    end
  end

  defp integer_opt(opts, key, default, reason) when is_list(opts) and is_atom(key) and is_integer(default) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_integer(value) ->
        {:ok, value}

      {:ok, value} ->
        {:error, Error.invalid_options(reason, value)}

      :error ->
        {:ok, default}
    end
  end

  defp optional_non_negative_integer_opt(opts, key, reason) when is_list(opts) and is_atom(key) do
    case optional_non_negative_integer_value(opts, key, reason) do
      {:ok, :absent} -> {:ok, opts}
      {:ok, value} -> {:ok, Keyword.put(opts, key, value)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp optional_non_negative_integer_value(opts, key, reason) when is_list(opts) and is_atom(key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_integer(value) and value >= 0 ->
        {:ok, value}

      {:ok, value} ->
        {:error, Error.invalid_options(reason, value)}

      :error ->
        {:ok, :absent}
    end
  end

  defp maybe_put(map, _key, :absent), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

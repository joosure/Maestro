defmodule SymphonyElixir.Agent.Credential.Store.RateLimits do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Store.{Files, Normalization, Paths}

  @usage_period_csv_header [
    "logged_at",
    "agent_provider_kind",
    "account_id",
    "account_email",
    "limit_id",
    "bucket",
    "period",
    "period_started_at",
    "reset_at",
    "next_reset_at",
    "limit",
    "remaining",
    "used",
    "usage_percent",
    "weekly_usage_percent",
    "input_tokens",
    "output_tokens",
    "total_tokens"
  ]

  @spec apply_snapshot(map(), map(), map(), map()) :: {map(), [map()]}
  def apply_snapshot(state, rate_limits, account, settings)
      when is_map(state) and is_map(rate_limits) and is_map(account) do
    exhausted_until = exhausted_until_from_rate_limits(rate_limits, settings)
    {state, usage_period_rows} = rotate_rate_limit_periods(state, rate_limits, account)

    next_state =
      cond do
        is_binary(exhausted_until) -> "exhausted"
        limited_rate_limits?(rate_limits) -> "limited"
        true -> "healthy"
      end

    state =
      Map.merge(state, %{
        "state" => next_state,
        "latest_quota" => rate_limits,
        "exhausted_until" => exhausted_until,
        "failure_reason" => if(next_state == "exhausted", do: "quota exhausted", else: nil),
        "updated_at" => Normalization.now_iso()
      })

    {state, usage_period_rows}
  end

  @spec append_usage_period_rows(map(), [map()]) :: :ok | {:error, term()}
  def append_usage_period_rows(_account, []), do: :ok

  def append_usage_period_rows(account, rows) when is_map(account) and is_list(rows) do
    path = Paths.usage_periods_csv_path(account)
    write_header? = not File.regular?(path)
    csv = Enum.map_join(rows, "", &usage_period_csv_line/1)

    contents =
      if write_header?, do: Enum.join(@usage_period_csv_header, ",") <> "\n" <> csv, else: csv

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, contents, [:append]) do
      File.chmod(path, Files.secret_mode())
    end
  end

  @spec latest_reset_at(map()) :: String.t() | nil
  def latest_reset_at(%{latest_quota: %{} = rate_limits}),
    do: reset_at_from_rate_limits(rate_limits)

  def latest_reset_at(_account), do: nil

  @spec quota_error?(term()) :: boolean()
  def quota_error?(reason) do
    reason
    |> inspect(limit: 20, printable_limit: 1_000)
    |> String.downcase()
    |> String.contains?([
      "rate limit",
      "rate_limit",
      "quota",
      "credit",
      "429",
      "exhausted",
      "maxed"
    ])
  end

  @spec bucket_usage_pct(map() | nil) :: float()
  def bucket_usage_pct(nil), do: 0.0

  def bucket_usage_pct(bucket) when is_map(bucket) do
    limit = Normalization.integer_value(Map.get(bucket, "limit"))
    remaining = Normalization.integer_value(Map.get(bucket, "remaining"))
    if limit > 0, do: max(0, limit - remaining) / limit, else: 0.0
  end

  @spec bucket_total_tokens(map() | nil) :: non_neg_integer()
  def bucket_total_tokens(nil), do: 0

  def bucket_total_tokens(bucket) when is_map(bucket),
    do: Normalization.integer_value(Map.get(bucket, "total_tokens"))

  defp rotate_rate_limit_periods(state, rate_limits, account) do
    current_periods = Map.get(state, "rate_limit_periods", %{})
    now = Normalization.now_iso()
    limit_id = rate_limit_id(rate_limits)

    {next_periods, rows} =
      rate_limit_bucket_entries(rate_limits)
      |> Enum.reduce({current_periods, []}, fn {bucket_name, period_name, bucket}, {periods, rows} ->
        reset_at = bucket_absolute_reset_at(bucket)

        cond do
          is_nil(reset_at) ->
            {periods, rows}

          is_nil(Map.get(periods, bucket_name)) ->
            period =
              new_rate_limit_period(bucket_name, period_name, limit_id, bucket, reset_at, now)

            {Map.put(periods, bucket_name, period), rows}

          Map.get(periods, bucket_name, %{})["reset_at"] != reset_at ->
            row =
              usage_period_row(account, Map.fetch!(periods, bucket_name), bucket, reset_at, now)

            period =
              new_rate_limit_period(bucket_name, period_name, limit_id, bucket, reset_at, now)

            {Map.put(periods, bucket_name, period), [row | rows]}

          true ->
            period =
              refresh_rate_limit_period(Map.fetch!(periods, bucket_name), limit_id, bucket, now)

            {Map.put(periods, bucket_name, period), rows}
        end
      end)

    {Map.put(state, "rate_limit_periods", next_periods), Enum.reverse(rows)}
  end

  defp rate_limit_bucket_entries(rate_limits) when is_map(rate_limits) do
    session_bucket =
      Map.get(rate_limits, "session") || Map.get(rate_limits, :session) ||
        Map.get(rate_limits, "primary") || Map.get(rate_limits, :primary)

    weekly_bucket =
      Map.get(rate_limits, "weekly") || Map.get(rate_limits, :weekly) ||
        Map.get(rate_limits, "secondary") || Map.get(rate_limits, :secondary)

    [
      {"session", "session", session_bucket},
      {"weekly", "weekly", weekly_bucket}
    ]
    |> Enum.filter(fn {_bucket_name, _period_name, bucket} -> is_map(bucket) end)
    |> Enum.map(fn {bucket_name, default_period_name, bucket} ->
      {bucket_name, bucket_period_name(bucket, bucket_name, default_period_name), bucket}
    end)
  end

  defp new_rate_limit_period(bucket_name, period_name, limit_id, bucket, reset_at, now) do
    %{
      "bucket" => bucket_name,
      "period" => period_name,
      "limit_id" => limit_id,
      "started_at" => now,
      "reset_at" => reset_at,
      "last_seen_at" => now,
      "limit" => Normalization.maybe_integer_value(Map.get(bucket, "limit") || Map.get(bucket, :limit)),
      "remaining" => Normalization.maybe_integer_value(Map.get(bucket, "remaining") || Map.get(bucket, :remaining)),
      "input_tokens" => 0,
      "output_tokens" => 0,
      "total_tokens" => 0
    }
  end

  defp refresh_rate_limit_period(period, limit_id, bucket, now) do
    period
    |> Map.put("limit_id", limit_id || Map.get(period, "limit_id"))
    |> Map.put("last_seen_at", now)
    |> Map.put("limit", coalesce_bucket_value(bucket, "limit", Map.get(period, "limit")))
    |> Map.put(
      "remaining",
      coalesce_bucket_value(bucket, "remaining", Map.get(period, "remaining"))
    )
  end

  defp usage_period_row(account, period, next_bucket, next_reset_at, now) do
    limit = Normalization.integer_value(Map.get(period, "limit"))
    remaining = Normalization.integer_value(Map.get(period, "remaining"))
    used = if limit > 0, do: max(0, limit - remaining), else: 0
    usage_percent = usage_percent(used, limit)
    period_name = Map.get(period, "period")

    %{
      "logged_at" => now,
      "agent_provider_kind" => Map.get(account, :agent_provider_kind),
      "account_id" => Map.get(account, :id),
      "account_email" => Map.get(account, :email),
      "limit_id" => Map.get(period, "limit_id"),
      "bucket" => Map.get(period, "bucket"),
      "period" => period_name,
      "period_started_at" => Map.get(period, "started_at"),
      "reset_at" => Map.get(period, "reset_at"),
      "next_reset_at" => next_reset_at,
      "limit" => limit,
      "remaining" => remaining,
      "used" => used,
      "usage_percent" => usage_percent,
      "weekly_usage_percent" => if(period_name == "weekly", do: usage_percent),
      "input_tokens" => Normalization.integer_value(Map.get(period, "input_tokens")),
      "output_tokens" => Normalization.integer_value(Map.get(period, "output_tokens")),
      "total_tokens" => Normalization.integer_value(Map.get(period, "total_tokens")),
      "next_limit" => Normalization.integer_value(Map.get(next_bucket, "limit") || Map.get(next_bucket, :limit)),
      "next_remaining" => Normalization.integer_value(Map.get(next_bucket, "remaining") || Map.get(next_bucket, :remaining))
    }
  end

  defp usage_period_csv_line(row) do
    Enum.map_join(@usage_period_csv_header, ",", fn field -> csv_escape(Map.get(row, field)) end) <>
      "\n"
  end

  defp exhausted_until_from_rate_limits(rate_limits, settings) do
    if exhausted_rate_limits?(rate_limits) do
      reset_at_from_rate_limits(rate_limits) ||
        DateTime.utc_now()
        |> DateTime.add(settings.exhausted_cooldown_ms, :millisecond)
        |> DateTime.to_iso8601()
    end
  end

  defp exhausted_rate_limits?(rate_limits) when is_map(rate_limits) do
    buckets = quota_buckets(rate_limits)

    Enum.any?(
      buckets,
      &(zero_remaining?(&1) or exhausted_by_used_percent?(&1) or exhausted_status?(&1))
    ) or
      depleted_credits?(Map.get(rate_limits, "credits") || Map.get(rate_limits, :credits))
  end

  defp limited_rate_limits?(rate_limits) when is_map(rate_limits) do
    rate_limits
    |> quota_buckets()
    |> Enum.any?(&low_remaining?/1)
  end

  defp quota_buckets(rate_limits) do
    [
      Map.get(rate_limits, "session") || Map.get(rate_limits, :session),
      Map.get(rate_limits, "weekly") || Map.get(rate_limits, :weekly),
      Map.get(rate_limits, "primary") || Map.get(rate_limits, :primary),
      Map.get(rate_limits, "secondary") || Map.get(rate_limits, :secondary)
    ]
    |> Enum.filter(&is_map/1)
  end

  defp reset_at_from_rate_limits(rate_limits) do
    rate_limits
    |> quota_buckets()
    |> Enum.flat_map(&bucket_reset_candidates/1)
    |> Enum.sort()
    |> List.first()
  end

  defp bucket_reset_candidates(bucket) when is_map(bucket) do
    [absolute_reset(bucket), relative_reset(relative_reset_seconds(bucket))]
    |> Enum.reject(&is_nil/1)
  end

  defp absolute_reset(bucket) do
    bucket
    |> first_value([
      "reset_at",
      :reset_at,
      "resetAt",
      :resetAt,
      "resets_at",
      :resets_at,
      "resetsAt",
      :resetsAt
    ])
    |> Normalization.normalize_datetime_string()
  end

  defp relative_reset_seconds(bucket) do
    first_value(bucket, [
      "reset_in_seconds",
      :reset_in_seconds,
      "resets_in_seconds",
      :resets_in_seconds,
      "reset_after_seconds",
      :reset_after_seconds
    ])
  end

  defp relative_reset(value) do
    case Normalization.integer_value(value) do
      seconds when seconds > 0 ->
        DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.to_iso8601()

      _seconds ->
        nil
    end
  end

  defp bucket_absolute_reset_at(bucket) when is_map(bucket), do: absolute_reset(bucket)

  defp rate_limit_id(rate_limits) do
    rate_limits
    |> first_value([
      "limit_id",
      :limit_id,
      "limitId",
      :limitId,
      "limit_name",
      :limit_name,
      "limitName",
      :limitName
    ])
    |> Normalization.normalize_optional_string()
  end

  defp bucket_period_name(bucket, bucket_name, default_value) do
    bucket
    |> first_value(["period", :period, "window", :window, "name", :name])
    |> Kernel.||(default_value)
    |> to_string()
    |> String.downcase()
    |> condense_period_name(bucket_name, default_value)
  end

  defp condense_period_name(value, _bucket_name, default_value) when value in ["", "nil"], do: default_value

  defp condense_period_name(value, bucket_name, default_value) do
    cond do
      String.contains?(value, ["week", "weekly", "7d"]) -> "weekly"
      String.contains?(value, ["session", "5h", "five"]) -> "session"
      bucket_name in ["secondary", "weekly"] -> "weekly"
      bucket_name in ["primary", "session"] -> "session"
      true -> default_value
    end
  end

  defp zero_remaining?(bucket),
    do:
      Normalization.integer_value(Map.get(bucket, "remaining") || Map.get(bucket, :remaining)) ==
        0

  defp exhausted_status?(bucket),
    do: (Map.get(bucket, "status") || Map.get(bucket, :status)) in ["rate_limited", "exhausted"]

  defp exhausted_by_used_percent?(bucket) when is_map(bucket) do
    case Map.get(bucket, "usedPercent") || Map.get(bucket, :usedPercent) do
      nil -> false
      percent -> Normalization.integer_value(percent) >= 100
    end
  end

  defp low_remaining?(bucket) when is_map(bucket) do
    remaining_raw = Map.get(bucket, "remaining") || Map.get(bucket, :remaining)
    limit_raw = Map.get(bucket, "limit") || Map.get(bucket, :limit)

    if is_nil(remaining_raw) or is_nil(limit_raw) do
      false
    else
      remaining = Normalization.integer_value(remaining_raw)
      limit = Normalization.integer_value(limit_raw)
      limit > 0 and remaining > 0 and remaining / limit < 0.1
    end
  end

  defp depleted_credits?(nil), do: false

  defp depleted_credits?(credits) when is_map(credits) do
    unlimited = Map.get(credits, "unlimited") || Map.get(credits, :unlimited)
    has_credits = Map.get(credits, "has_credits") || Map.get(credits, :has_credits)
    balance = Map.get(credits, "balance") || Map.get(credits, :balance)

    cond do
      unlimited == true -> false
      has_credits == false -> true
      is_number(balance) -> balance <= 0
      is_binary(balance) -> Decimal.compare(Decimal.new(balance), Decimal.new(0)) in [:lt, :eq]
      true -> false
    end
  rescue
    _error -> false
  end

  defp first_value(map, keys) do
    Enum.find_value(keys, &Map.get(map, &1))
  end

  defp csv_escape(nil), do: ""
  defp csv_escape(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)

  defp csv_escape(value) do
    value = to_string(value)

    if String.contains?(value, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(value, "\"", "\"\"") <> "\"",
      else: value
  end

  defp usage_percent(_used, limit) when limit <= 0, do: nil
  defp usage_percent(used, limit), do: Float.round(used * 100 / limit, 2)

  defp coalesce_bucket_value(bucket, key, default_value) do
    case Map.get(bucket, key) || Map.get(bucket, String.to_existing_atom(key)) do
      nil -> default_value
      value -> Normalization.integer_value(value)
    end
  rescue
    ArgumentError -> default_value
  end
end

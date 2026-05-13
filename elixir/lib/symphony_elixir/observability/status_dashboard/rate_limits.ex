defmodule SymphonyElixir.Observability.StatusDashboard.RateLimits do
  @moduledoc false

  @type format_opts :: %{
          colorize: (String.t(), String.t() -> String.t()),
          truncate: (String.t(), pos_integer() -> String.t()),
          format_count: (integer() | term() -> String.t()),
          ansi_gray: String.t(),
          ansi_yellow: String.t(),
          ansi_cyan: String.t(),
          ansi_green: String.t()
        }

  @spec format(term(), format_opts()) :: String.t()
  def format(nil, %{ansi_gray: ansi_gray} = opts), do: colorize("unavailable", ansi_gray, opts)

  def format(rate_limits, opts) when is_map(rate_limits) do
    limit_id =
      map_value(rate_limits, [
        "limit_id",
        :limit_id,
        "limitId",
        :limitId,
        "limit_name",
        :limit_name,
        "limitName",
        :limitName
      ]) ||
        "unknown"

    primary = format_bucket(map_value(rate_limits, ["primary", :primary]), opts)
    secondary = format_bucket(map_value(rate_limits, ["secondary", :secondary]), opts)
    credits = format_credits(map_value(rate_limits, ["credits", :credits]), opts)

    colorize(to_string(limit_id), opts.ansi_yellow, opts) <>
      colorize(" | ", opts.ansi_gray, opts) <>
      colorize("primary #{primary}", opts.ansi_cyan, opts) <>
      colorize(" | ", opts.ansi_gray, opts) <>
      colorize("secondary #{secondary}", opts.ansi_cyan, opts) <>
      colorize(" | ", opts.ansi_gray, opts) <>
      colorize(credits, opts.ansi_green, opts)
  end

  def format(other, %{ansi_gray: ansi_gray} = opts) do
    other
    |> inspect(limit: 10)
    |> truncate(80, opts)
    |> colorize(ansi_gray, opts)
  end

  defp format_bucket(nil, _opts), do: "n/a"

  defp format_bucket(bucket, opts) when is_map(bucket) do
    remaining = map_value(bucket, ["remaining", :remaining])
    limit = map_value(bucket, ["limit", :limit])

    reset_value =
      map_value(bucket, [
        "reset_in_seconds",
        :reset_in_seconds,
        "resetInSeconds",
        :resetInSeconds,
        "reset_at",
        :reset_at,
        "resetAt",
        :resetAt,
        "resets_at",
        :resets_at,
        "resetsAt",
        :resetsAt
      ])

    base =
      cond do
        integer_like?(remaining) and integer_like?(limit) ->
          "#{format_count(remaining, opts)}/#{format_count(limit, opts)}"

        integer_like?(remaining) ->
          "remaining #{format_count(remaining, opts)}"

        integer_like?(limit) ->
          "limit #{format_count(limit, opts)}"

        map_size(bucket) == 0 ->
          "n/a"

        true ->
          bucket |> inspect(limit: 6) |> truncate(40, opts)
      end

    if is_nil(reset_value) do
      base
    else
      "#{base} reset #{format_reset_value(reset_value, opts)}"
    end
  end

  defp format_bucket(other, _opts), do: to_string(other)

  defp format_credits(nil, _opts), do: "credits n/a"

  defp format_credits(credits, opts) when is_map(credits) do
    unlimited = map_value(credits, ["unlimited", :unlimited]) == true
    has_credits = map_value(credits, ["has_credits", :has_credits, "hasCredits", :hasCredits]) == true
    balance = map_value(credits, ["balance", :balance])

    cond do
      unlimited ->
        "credits unlimited"

      has_credits and is_number(balance) ->
        "credits #{format_number(balance, opts)}"

      has_credits ->
        "credits available"

      true ->
        "credits none"
    end
  end

  defp format_credits(other, _opts), do: "credits #{to_string(other)}"

  defp format_reset_value(value, opts) when is_integer(value), do: "#{format_count(value, opts)}s"
  defp format_reset_value(value, _opts) when is_binary(value), do: value
  defp format_reset_value(value, _opts), do: to_string(value)

  defp format_number(value, opts) when is_integer(value), do: format_count(value, opts)

  defp format_number(value, _opts) when is_float(value) do
    value
    |> Float.round(2)
    |> :erlang.float_to_binary(decimals: 2)
  end

  defp format_count(value, %{format_count: format_count}) when is_function(format_count, 1),
    do: format_count.(value)

  defp truncate(value, max, %{truncate: truncate}) when is_function(truncate, 2),
    do: truncate.(value, max)

  defp colorize(value, code, %{colorize: colorize}) when is_function(colorize, 2),
    do: colorize.(value, code)

  defp map_value(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, &Map.get(map, &1))
  end

  defp map_value(_map, _keys), do: nil

  defp integer_like?(value) when is_integer(value), do: true
  defp integer_like?(_value), do: false
end

defmodule SymphonyElixir.RepoProvider.LandWatch.Reviews do
  @moduledoc false

  defstruct agent_review_bots: MapSet.new(),
            request_token: "@agent review",
            reply_prefix: "[agent]",
            review_heading: "## Agent Review"

  @type settings :: %__MODULE__{
          agent_review_bots: MapSet.t(String.t()),
          request_token: String.t(),
          reply_prefix: String.t(),
          review_heading: String.t()
        }

  @control_chars ~r/[\x00-\x08\x0b-\x1f\x7f-\x9f]/

  @spec settings_from_env(map() | [{String.t(), String.t()}]) :: settings()
  def settings_from_env(env) when is_list(env), do: env |> Map.new() |> settings_from_env()

  def settings_from_env(env) when is_map(env) do
    %__MODULE__{
      agent_review_bots:
        env
        |> Map.get("SYMPHONY_AGENT_REVIEW_BOTS", "")
        |> to_string()
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> MapSet.new(),
      request_token: env_value(env, "SYMPHONY_AGENT_REVIEW_REQUEST_TOKEN", "@agent review"),
      reply_prefix: env_value(env, "SYMPHONY_AGENT_REPLY_PREFIX", "[agent]"),
      review_heading: env_value(env, "SYMPHONY_AGENT_REVIEW_HEADING", "## Agent Review")
    }
  end

  @spec evaluate([map()], [map()], [map()], settings()) ::
          :ok | {:blocked, non_neg_integer(), iodata()}
  def evaluate(issue_comments, review_comments, reviews, %__MODULE__{} = settings) do
    review_request_at = latest_agent_review_request_at(issue_comments, settings)

    bot_comments =
      filter_agent_review_comments(issue_comments, review_request_at, settings) ++
        filter_agent_review_comments(review_comments, review_request_at, settings)

    cond do
      blocking_comments?(issue_comments, review_comments, settings) ->
        {:blocked, 2,
         [
           "Review comments detected. Address before merge.\n",
           "Reminder: decide whether feedback stays in scope; defer if needed and note in your root-level update.\n"
         ]}

      filter_blocking_reviews(reviews, review_request_at, settings) != [] ->
        {:blocked, 2,
         [
           "Review states/comments detected. Address before merge.\n",
           "Reminder: keep PR title/description aligned with the full scope when changes expand.\n"
         ]}

      bot_comments != [] ->
        latest = Enum.max_by(bot_comments, &comment_sort_time/1, &later_or_equal?/2)
        body = latest |> field_value("body") |> to_string() |> sanitize_terminal_output() |> String.trim()

        if body == "" do
          :ok
        else
          {:blocked, 2, ["Agent review comments detected. Address feedback before merge.\n", body, "\n"]}
        end

      true ->
        :ok
    end
  end

  @spec latest_agent_review_request_at([map()], settings()) :: DateTime.t() | nil
  def latest_agent_review_request_at(comments, %__MODULE__{} = settings) when is_list(comments) do
    comments
    |> Enum.reject(&agent_review_bot_user?(field_value(&1, "user") || %{}, settings))
    |> Enum.filter(fn comment ->
      body = field_value(comment, "body") || ""
      String.contains?(body, settings.request_token)
    end)
    |> latest_comment_time()
  end

  @spec filter_agent_review_comments([map()], DateTime.t() | nil, settings()) :: [map()]
  def filter_agent_review_comments(comments, review_requested_at, %__MODULE__{} = settings)
      when is_list(comments) do
    latest_agent_reply = latest_agent_reply_by_thread(comments, settings)
    latest_issue_ack = latest_agent_issue_reply_time(comments, settings)

    Enum.filter(comments, fn comment ->
      created_time = comment_time(comment)

      cond do
        not agent_review_bot_user?(field_value(comment, "user") || %{}, settings) ->
          false

        is_nil(created_time) ->
          false

        not is_nil(review_requested_at) and not after_time?(created_time, review_requested_at) ->
          false

        threaded_comment?(comment) ->
          thread_root = thread_root_id(comment)
          last_reply = if is_nil(thread_root), do: nil, else: Map.get(latest_agent_reply, thread_root)
          is_nil(last_reply) or after_time?(created_time, last_reply) or DateTime.compare(created_time, last_reply) == :eq

        not is_nil(latest_issue_ack) ->
          after_time?(created_time, latest_issue_ack)

        true ->
          true
      end
    end)
  end

  @spec filter_human_issue_comments([map()], settings()) :: [map()]
  def filter_human_issue_comments(comments, %__MODULE__{} = settings) when is_list(comments) do
    latest_ack = latest_agent_issue_reply_time(comments, settings)

    Enum.filter(comments, fn comment ->
      user = field_value(comment, "user") || %{}
      body = comment |> field_value("body") |> to_string() |> String.trim()
      created_time = comment_time(comment)

      cond do
        bot_user?(user, settings) -> false
        agent_reply_body?(body, settings) -> false
        agent_review_body?(body, settings) -> false
        String.contains?(body, settings.request_token) -> false
        not is_nil(latest_ack) and not is_nil(created_time) and not after_time?(created_time, latest_ack) -> false
        true -> true
      end
    end)
  end

  @spec filter_agent_review_issue_comments([map()], settings()) :: [map()]
  def filter_agent_review_issue_comments(comments, %__MODULE__{} = settings) when is_list(comments) do
    latest_ack = latest_agent_issue_reply_time(comments, settings)

    Enum.filter(comments, fn comment ->
      body = comment |> field_value("body") |> to_string() |> String.trim()
      created_time = comment_time(comment)

      cond do
        not agent_review_body?(body, settings) ->
          false

        not is_nil(latest_ack) and not is_nil(created_time) and not after_time?(created_time, latest_ack) ->
          false

        true ->
          true
      end
    end)
  end

  @spec filter_human_review_comments([map()], settings()) :: [map()]
  def filter_human_review_comments(comments, %__MODULE__{} = settings) when is_list(comments) do
    latest_agent_reply = latest_agent_reply_by_thread(comments, settings)

    Enum.filter(comments, fn comment ->
      user = field_value(comment, "user") || %{}
      body = comment |> field_value("body") |> to_string() |> String.trim()
      thread_root = thread_root_id(comment)
      created_time = comment_time(comment)
      last_agent_reply = if is_nil(thread_root), do: nil, else: Map.get(latest_agent_reply, thread_root)

      cond do
        bot_user?(user, settings) -> false
        agent_reply_body?(body, settings) -> false
        not is_nil(last_agent_reply) and not is_nil(created_time) and not after_time?(created_time, last_agent_reply) -> false
        true -> true
      end
    end)
  end

  @spec filter_blocking_reviews([map()], DateTime.t() | nil, settings()) :: [map()]
  def filter_blocking_reviews(reviews, review_requested_at, %__MODULE__{} = settings)
      when is_list(reviews) do
    reviews
    |> dedupe_reviews()
    |> Enum.filter(&blocking_review?(&1, review_requested_at, settings))
  end

  @spec sanitize_terminal_output(String.t()) :: String.t()
  def sanitize_terminal_output(value) when is_binary(value), do: Regex.replace(@control_chars, value, "")

  defp blocking_comments?(issue_comments, review_comments, settings) do
    filter_human_issue_comments(issue_comments, settings) != [] or
      filter_agent_review_issue_comments(issue_comments, settings) != [] or
      filter_human_review_comments(review_comments, settings) != []
  end

  defp latest_agent_issue_reply_time(comments, settings) do
    comments
    |> Enum.filter(fn comment ->
      comment
      |> field_value("body")
      |> to_string()
      |> String.trim()
      |> agent_reply_body?(settings)
    end)
    |> latest_comment_time()
  end

  defp latest_agent_reply_by_thread(comments, settings) do
    Enum.reduce(comments, %{}, fn comment, latest ->
      body = comment |> field_value("body") |> to_string() |> String.trim()
      thread_root = thread_root_id(comment)
      created_time = comment_time(comment)

      if agent_reply_body?(body, settings) and not is_nil(thread_root) and not is_nil(created_time) do
        Map.update(latest, thread_root, created_time, fn existing ->
          if after_time?(created_time, existing), do: created_time, else: existing
        end)
      else
        latest
      end
    end)
  end

  defp latest_comment_time(comments) do
    comments
    |> Enum.map(&comment_time/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      times -> Enum.max_by(times, & &1, &later_or_equal?/2)
    end
  end

  defp blocking_review?(review, review_requested_at, settings) do
    created_time = review_timestamp(review)
    user_login = review |> field_value("user") |> user_login()

    cond do
      is_nil(created_time) ->
        false

      MapSet.member?(settings.agent_review_bots, user_login) and not is_nil(review_requested_at) and
          not after_time?(created_time, review_requested_at) ->
        false

      MapSet.member?(settings.agent_review_bots, user_login) ->
        field_value(review, "state") == "CHANGES_REQUESTED"

      true ->
        body = review |> field_value("body") |> to_string() |> String.trim()
        state = field_value(review, "state")

        cond do
          agent_reply_body?(body, settings) or state in ["APPROVED", "DISMISSED"] -> false
          body != "" or state == "CHANGES_REQUESTED" -> true
          state == "COMMENTED" -> false
          is_binary(state) -> state not in ["APPROVED", "DISMISSED"]
          true -> false
        end
    end
  end

  defp dedupe_reviews(reviews) do
    reviews
    |> Enum.reduce(%{}, fn review, latest_by_user ->
      user_login = review |> field_value("user") |> user_login()
      timestamp = review_timestamp(review)
      existing = Map.get(latest_by_user, user_login)

      cond do
        user_login == "" ->
          latest_by_user

        is_nil(existing) ->
          Map.put(latest_by_user, user_login, review)

        is_nil(timestamp) ->
          latest_by_user

        after_time?(timestamp, review_timestamp(existing)) ->
          Map.put(latest_by_user, user_login, review)

        true ->
          latest_by_user
      end
    end)
    |> Map.values()
  end

  defp review_timestamp(review) do
    case field_value(review, "submitted_at") || field_value(review, "created_at") do
      value when is_binary(value) -> parse_time(value)
      _other -> nil
    end
  end

  defp comment_sort_time(comment) do
    comment_time(comment) || ~U[1970-01-01 00:00:00Z]
  end

  defp comment_time(comment) do
    case field_value(comment, "updated_at") || field_value(comment, "created_at") do
      value when is_binary(value) -> parse_time(value)
      _other -> nil
    end
  end

  defp parse_time(value) when is_binary(value) do
    value
    |> String.replace_suffix("Z", "+00:00")
    |> DateTime.from_iso8601()
    |> case do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp after_time?(_left, nil), do: true
  defp after_time?(nil, _right), do: false
  defp after_time?(left, right), do: DateTime.compare(left, right) == :gt
  defp later_or_equal?(left, right), do: DateTime.compare(left, right) != :lt

  defp threaded_comment?(comment) do
    present?(field_value(comment, "in_reply_to_id")) or present?(field_value(comment, "pull_request_review_id"))
  end

  defp thread_root_id(comment), do: field_value(comment, "in_reply_to_id") || field_value(comment, "id")

  defp agent_review_bot_user?(user, settings) do
    MapSet.member?(settings.agent_review_bots, user_login(user))
  end

  defp bot_user?(user, settings) do
    login = user_login(user)

    agent_review_bot_user?(user, settings) or
      field_value(user, "type") == "Bot" or
      String.ends_with?(login, "[bot]")
  end

  defp user_login(user), do: (field_value(user || %{}, "login") || "") |> to_string()

  defp agent_reply_body?(body, settings), do: String.starts_with?(body, settings.reply_prefix)
  defp agent_review_body?(body, settings), do: String.starts_with?(body, settings.review_heading)

  defp present?(value), do: value not in [nil, ""]

  defp env_value(env, key, default) do
    case Map.get(env, key) do
      value when is_binary(value) and value != "" -> value
      _other -> default
    end
  end

  defp field_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp field_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end
end

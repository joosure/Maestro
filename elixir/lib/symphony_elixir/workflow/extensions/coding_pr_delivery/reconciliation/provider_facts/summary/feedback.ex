defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Summary.Feedback do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Payload
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Summary.Settings

  @bot_user_type "Bot"
  @bot_login_suffix "[bot]"

  @spec unresolved_actionable_feedback?([map()], [map()], map() | list()) :: boolean()
  def unresolved_actionable_feedback?(issue_comments, review_comments, env)
      when is_list(issue_comments) and is_list(review_comments) do
    settings = Settings.from_env(env)

    filter_human_issue_comments(issue_comments, settings) != [] or
      filter_agent_review_issue_comments(issue_comments, settings) != [] or
      filter_human_review_comments(review_comments, settings) != []
  end

  defp filter_human_issue_comments(comments, %Settings{} = settings) when is_list(comments) do
    latest_ack = latest_agent_issue_reply_time(comments, settings)

    Enum.filter(comments, fn comment ->
      user = Payload.field_value(comment, Contract.payload_key(:user)) || %{}
      body = comment |> Payload.field_value(Contract.payload_key(:body)) |> to_string() |> String.trim()
      created_time = comment_time(comment)

      cond do
        bot_user?(user, settings) ->
          false

        agent_reply_body?(body, settings) ->
          false

        agent_review_body?(body, settings) ->
          false

        String.contains?(body, settings.request_token) ->
          false

        not is_nil(latest_ack) and not is_nil(created_time) and not after_time?(created_time, latest_ack) ->
          false

        true ->
          true
      end
    end)
  end

  defp filter_agent_review_issue_comments(comments, %Settings{} = settings) when is_list(comments) do
    latest_ack = latest_agent_issue_reply_time(comments, settings)

    Enum.filter(comments, fn comment ->
      body = comment |> Payload.field_value(Contract.payload_key(:body)) |> to_string() |> String.trim()
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

  defp filter_human_review_comments(comments, %Settings{} = settings) when is_list(comments) do
    latest_agent_reply = latest_agent_reply_by_thread(comments, settings)

    Enum.filter(comments, fn comment ->
      user = Payload.field_value(comment, Contract.payload_key(:user)) || %{}
      body = comment |> Payload.field_value(Contract.payload_key(:body)) |> to_string() |> String.trim()
      thread_root = thread_root_id(comment)
      created_time = comment_time(comment)

      last_agent_reply =
        if is_nil(thread_root), do: nil, else: Map.get(latest_agent_reply, thread_root)

      cond do
        bot_user?(user, settings) ->
          false

        agent_reply_body?(body, settings) ->
          false

        not is_nil(last_agent_reply) and not is_nil(created_time) and not after_time?(created_time, last_agent_reply) ->
          false

        true ->
          true
      end
    end)
  end

  defp latest_agent_issue_reply_time(comments, %Settings{} = settings) when is_list(comments) do
    comments
    |> Enum.filter(fn comment ->
      comment
      |> Payload.field_value(Contract.payload_key(:body))
      |> to_string()
      |> String.trim()
      |> agent_reply_body?(settings)
    end)
    |> latest_comment_time()
  end

  defp latest_agent_reply_by_thread(comments, %Settings{} = settings) when is_list(comments) do
    Enum.reduce(comments, %{}, fn comment, latest ->
      body = comment |> Payload.field_value(Contract.payload_key(:body)) |> to_string() |> String.trim()
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

  defp latest_comment_time(comments) when is_list(comments) do
    comments
    |> Enum.map(&comment_time/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      times -> Enum.max_by(times, & &1, &later_or_equal?/2)
    end
  end

  defp comment_time(comment) when is_map(comment) do
    case Payload.field_value(comment, Contract.payload_key(:updated_at)) ||
           Payload.field_value(comment, Contract.payload_key(:created_at)) do
      value when is_binary(value) -> parse_time(value)
      _other -> nil
    end
  end

  defp thread_root_id(comment) when is_map(comment) do
    Payload.field_value(comment, Contract.payload_key(:in_reply_to_id)) ||
      Payload.field_value(comment, Contract.payload_key(:id))
  end

  defp bot_user?(user, %Settings{} = settings) when is_map(user) do
    login = user_login(user)

    MapSet.member?(settings.agent_review_bots, login) or
      Payload.field_value(user, Contract.payload_key(:type)) == @bot_user_type or
      String.ends_with?(login, @bot_login_suffix)
  end

  defp bot_user?(_user, %Settings{}), do: false

  defp agent_reply_body?(body, %Settings{} = settings) when is_binary(body), do: String.starts_with?(body, settings.reply_prefix)
  defp agent_review_body?(body, %Settings{} = settings) when is_binary(body), do: String.starts_with?(body, settings.review_heading)

  defp parse_time(value) when is_binary(value) do
    value
    |> String.replace_suffix(Contract.utc_suffix(), Contract.utc_offset())
    |> DateTime.from_iso8601()
    |> case do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp user_login(user) when is_map(user) do
    user
    |> Payload.field_value(Contract.payload_key(:login))
    |> to_string()
  end

  defp after_time?(_left, nil), do: true
  defp after_time?(nil, _right), do: false
  defp after_time?(left, right), do: DateTime.compare(left, right) == :gt
  defp later_or_equal?(left, right), do: DateTime.compare(left, right) != :lt
end

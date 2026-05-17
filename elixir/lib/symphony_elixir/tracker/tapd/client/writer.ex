defmodule SymphonyElixir.Tracker.Tapd.Client.Writer do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Kinds
  alias SymphonyElixir.Tracker.Tapd.Client.{Errors, Fields, Paths, Request}

  @provider_kind Kinds.tapd()

  @spec create_story_comment(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_story_comment(story_id, description, opts \\ [])
      when is_binary(story_id) and is_binary(description) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)
    request_opts = Keyword.put(opts, :tracker, tracker)
    platform = platform(tracker)
    started_at_ms = System.monotonic_time(:millisecond)

    fields = %{
      component: "tracker.tapd.client",
      tracker_kind: Map.get(tracker, :kind, @provider_kind),
      issue_id: story_id,
      payload_summary: Redaction.summarize(%{"description" => description})
    }

    ObservabilityLogger.emit(:info, :tracker_comment_create_started, fields)

    params =
      %{
        "entry_id" => story_id,
        "description" => description,
        "entry_type" => "stories"
      }
      |> maybe_put_comment_author(Map.get(platform, "comment_author"))

    result =
      case Request.request("POST", Paths.comments(), params, request_opts) do
        {:ok, _body} -> :ok
        {:error, reason} -> {:error, reason}
      end

    emit_tracker_write_result(result, started_at_ms, :tracker_comment_create_succeeded, :tracker_comment_create_failed, fields)
    result
  end

  @spec update_story_status(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_story_status(story_id, status, opts \\ [])
      when is_binary(story_id) and is_binary(status) and is_list(opts) do
    tracker = Keyword.fetch!(opts, :tracker)
    request_opts = Keyword.put(opts, :tracker, tracker)
    started_at_ms = System.monotonic_time(:millisecond)

    fields = %{
      component: "tracker.tapd.client",
      tracker_kind: Map.get(tracker, :kind, @provider_kind),
      issue_id: story_id,
      target_state: status
    }

    ObservabilityLogger.emit(:info, :tracker_state_update_started, fields)

    result =
      case Request.request("POST", Paths.stories(), %{"id" => story_id, "status" => status}, request_opts) do
        {:ok, _body} -> :ok
        {:error, reason} -> {:error, Errors.classify_story_update_error(reason, story_id, status)}
      end

    emit_tracker_write_result(result, started_at_ms, :tracker_state_update_succeeded, :tracker_state_update_failed, fields)
    result
  end

  defp emit_tracker_write_result(:ok, started_at_ms, success_event, _failure_event, fields) do
    ObservabilityLogger.emit(:info, success_event, Map.put(fields, :duration_ms, elapsed_ms(started_at_ms)))
  end

  defp emit_tracker_write_result({:error, reason}, started_at_ms, _success_event, failure_event, fields) do
    ObservabilityLogger.emit(
      :warning,
      failure_event,
      Map.merge(fields, %{duration_ms: elapsed_ms(started_at_ms), error: inspect(reason)})
    )
  end

  defp elapsed_ms(started_at_ms) when is_integer(started_at_ms) do
    max(System.monotonic_time(:millisecond) - started_at_ms, 0)
  end

  defp maybe_put_comment_author(params, comment_author) do
    case Fields.normalize_string(comment_author) do
      nil -> params
      value -> Map.put(params, "author", value)
    end
  end

  defp platform(tracker) when is_map(tracker) do
    tracker
    |> TrackerConfig.provider()
    |> Fields.string_field("platform")
    |> case do
      value when is_map(value) -> value
      _ -> %{}
    end
  end
end

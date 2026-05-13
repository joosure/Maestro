defmodule SymphonyElixirWeb.ObservabilityPubSub do
  @moduledoc """
  PubSub helpers for observability dashboard updates.
  """

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  @pubsub SymphonyElixir.PubSub
  @topic "observability:dashboard"
  @update_message :observability_updated
  @component "observability.pubsub"

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    case Process.whereis(@pubsub) do
      pid when is_pid(pid) ->
        case safe_subscribe() do
          :ok ->
            emit_pubsub_event(
              :info,
              :dashboard_pubsub_subscribed,
              %{result_summary: "topic=#{@topic}"}
            )

            :ok

          {:error, reason} = error ->
            emit_pubsub_event(
              :warning,
              :dashboard_pubsub_subscribe_failed,
              %{error: format_pubsub_error(reason), result_summary: "topic=#{@topic}"}
            )

            error
        end

      _ ->
        emit_pubsub_event(
          :warning,
          :dashboard_pubsub_subscribe_failed,
          %{error: "pubsub_unavailable", result_summary: "topic=#{@topic}"}
        )

        {:error, :unavailable}
    end
  end

  @spec broadcast_update() :: :ok
  def broadcast_update do
    case Process.whereis(@pubsub) do
      pid when is_pid(pid) ->
        case safe_broadcast() do
          :ok ->
            :ok

          {:error, reason} ->
            emit_pubsub_event(
              :warning,
              :dashboard_pubsub_broadcast_failed,
              %{error: format_pubsub_error(reason), result_summary: "topic=#{@topic}"}
            )

            :ok
        end

      _ ->
        emit_pubsub_event(
          :info,
          :dashboard_pubsub_broadcast_skipped,
          %{result_summary: "topic=#{@topic} reason=pubsub_unavailable"}
        )

        :ok
    end
  end

  defp safe_subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  rescue
    error ->
      {:error, error}
  catch
    kind, reason ->
      {:error, {kind, reason}}
  end

  defp safe_broadcast do
    case Phoenix.PubSub.broadcast(@pubsub, @topic, @update_message) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      {:error, error}
  catch
    kind, reason ->
      {:error, {kind, reason}}
  end

  defp emit_pubsub_event(level, event, extra_fields) when is_map(extra_fields) do
    summary = Map.get(extra_fields, :result_summary, "topic=#{@topic}")

    message =
      case Map.get(extra_fields, :error) do
        nil -> "#{event} #{summary}"
        error -> "#{event} #{summary} error=#{error}"
      end

    ObservabilityLogger.emit(
      level,
      event,
      extra_fields
      |> Map.put(:component, @component)
      |> Map.put_new(:message, message)
    )
  end

  defp format_pubsub_error(%_{} = error), do: Exception.format_banner(:error, error)
  defp format_pubsub_error({kind, reason}), do: Exception.format_banner(kind, reason)
  defp format_pubsub_error(reason), do: inspect(reason)
end

defmodule SymphonyElixir.Observability.EventStore.Config do
  @moduledoc false

  @default %{
    global_event_limit: 1_000,
    issue_event_limit: 50,
    run_event_limit: 200,
    session_event_limit: 200,
    index_key_limit: 500,
    pending_event_queue_limit: 5_000
  }

  @type t :: %{
          required(:global_event_limit) => pos_integer(),
          required(:issue_event_limit) => pos_integer(),
          required(:run_event_limit) => pos_integer(),
          required(:session_event_limit) => pos_integer(),
          required(:index_key_limit) => pos_integer(),
          required(:pending_event_queue_limit) => pos_integer()
        }

  @spec default() :: t()
  def default, do: @default

  @spec normalize(map() | struct() | term()) :: t()
  def normalize(%_{} = observability) do
    observability
    |> Map.from_struct()
    |> normalize()
  end

  def normalize(observability) when is_map(observability) do
    %{
      global_event_limit: normalize_positive_integer(fetch_value(observability, :global_event_limit), @default.global_event_limit),
      issue_event_limit: normalize_positive_integer(fetch_value(observability, :issue_event_limit), @default.issue_event_limit),
      run_event_limit: normalize_positive_integer(fetch_value(observability, :run_event_limit), @default.run_event_limit),
      session_event_limit: normalize_positive_integer(fetch_value(observability, :session_event_limit), @default.session_event_limit),
      index_key_limit: normalize_positive_integer(fetch_value(observability, :index_key_limit), @default.index_key_limit),
      pending_event_queue_limit:
        normalize_positive_integer(
          fetch_value(observability, :pending_event_queue_limit),
          @default.pending_event_queue_limit
        )
    }
  end

  def normalize(_observability), do: @default

  defp fetch_value(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_positive_integer(_value, default), do: default
end

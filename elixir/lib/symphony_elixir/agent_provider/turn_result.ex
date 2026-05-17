defmodule SymphonyElixir.AgentProvider.TurnResult do
  @moduledoc """
  Provider-neutral result for one completed agent turn.
  """

  alias SymphonyElixir.AgentProvider.TurnStatus
  alias SymphonyElixir.AgentProvider.Usage

  @type status :: TurnStatus.status()

  @type t :: %__MODULE__{
          status: status(),
          session_id: String.t() | nil,
          thread_id: String.t() | nil,
          turn_id: String.t() | nil,
          usage: Usage.t(),
          metadata: map()
        }

  defstruct status: :completed,
            session_id: nil,
            thread_id: nil,
            turn_id: nil,
            usage: %{},
            metadata: %{}

  @spec new(term()) :: t()
  def new(%__MODULE__{} = result), do: result
  def new(result) when is_list(result), do: result |> Map.new() |> new()

  def new(%{} = result) do
    %__MODULE__{
      status: normalize_status(Map.get(result, :status) || Map.get(result, "status")),
      session_id: Map.get(result, :session_id) || Map.get(result, "session_id"),
      thread_id: Map.get(result, :thread_id) || Map.get(result, "thread_id"),
      turn_id: Map.get(result, :turn_id) || Map.get(result, "turn_id"),
      usage: normalize_map(Map.get(result, :usage) || Map.get(result, "usage")),
      metadata: metadata(result)
    }
  end

  def new(_result), do: %__MODULE__{}

  defp normalize_status(status), do: TurnStatus.normalize_atom(status, default: :completed, unknown: :failed)

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp metadata(result) do
    Map.drop(result, [
      :status,
      "status",
      :session_id,
      "session_id",
      :thread_id,
      "thread_id",
      :turn_id,
      "turn_id",
      :usage,
      "usage"
    ])
  end
end

defmodule SymphonyElixir.Config.Schema.StateLimits do
  @moduledoc false

  import Ecto.Changeset, only: [validate_change: 3]

  alias SymphonyElixir.Workflow.Lifecycle

  @spec normalize(nil | map()) :: map()
  def normalize(nil), do: %{}

  def normalize(limits) when is_map(limits) do
    Enum.reduce(limits, %{}, fn {state_name, limit}, acc ->
      Map.put(acc, Lifecycle.normalize_tracker_state(to_string(state_name)), limit)
    end)
  end

  @spec validate(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate(changeset, field) do
    validate_change(changeset, field, fn ^field, limits ->
      Enum.flat_map(limits, fn {state_name, limit} ->
        cond do
          to_string(state_name) == "" ->
            [{field, "state names must not be blank"}]

          not is_integer(limit) or limit <= 0 ->
            [{field, "limits must be positive integers"}]

          true ->
            []
        end
      end)
    end)
  end
end

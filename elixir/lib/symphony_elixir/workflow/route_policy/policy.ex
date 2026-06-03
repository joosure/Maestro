defmodule SymphonyElixir.Workflow.RoutePolicy.Policy do
  @moduledoc """
  Resolved route policy for a single profile route key.
  """

  @enforce_keys [:action]
  defstruct [:action, :transition_target, :execution_profile]

  alias SymphonyElixir.Workflow.RoutePolicy

  @type t :: %__MODULE__{
          action: atom(),
          transition_target: atom() | nil,
          execution_profile: String.t() | nil
        }

  @spec new!(map() | t()) :: t()
  def new!(%__MODULE__{} = policy), do: policy

  def new!(entry) when is_map(entry) do
    action = required_field(entry, :action)

    unless RoutePolicy.valid_action?(action) do
      raise ArgumentError, "invalid resolved route policy action: #{inspect(action)}"
    end

    struct!(__MODULE__, %{
      action: action,
      transition_target: optional_field(entry, :transition_target),
      execution_profile: optional_field(entry, :execution_profile)
    })
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = policy) do
    %{action: policy.action}
    |> maybe_put(:transition_target, policy.transition_target)
    |> maybe_put(:execution_profile, policy.execution_profile)
  end

  @spec fetch(t(), atom()) :: {:ok, term()} | :error
  def fetch(%__MODULE__{} = policy, key) when is_atom(key) do
    policy
    |> Map.from_struct()
    |> Map.fetch(key)
  end

  def fetch(%__MODULE__{}, _key), do: :error

  defp required_field(map, key) when is_map(map) and is_atom(key) do
    case fetch_field(map, key) do
      {:ok, value} ->
        value

      :error ->
        raise KeyError, key: key, term: map
    end
  end

  defp optional_field(map, key) when is_map(map) and is_atom(key) do
    case fetch_field(map, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp fetch_field(map, key) when is_map(map) and is_atom(key) do
    Map.fetch(map, key)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

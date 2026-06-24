defmodule SymphonyElixir.Agent.DynamicTool.Usage.ProviderCapabilityUnavailable do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Metadata

  @capability_key Metadata.Contract.capability()
  @description_key Metadata.Contract.description()
  @reason_key Metadata.Contract.reason()
  @provider_capability_unavailable_reason Metadata.Contract.provider_capability_unavailable_reason()

  defstruct capability: nil,
            description: nil,
            reason: @provider_capability_unavailable_reason

  @type t :: %__MODULE__{
          capability: String.t() | nil,
          description: String.t() | nil,
          reason: String.t()
        }

  @spec count(term()) :: non_neg_integer()
  def count(%{} = payload) do
    Enum.reduce(payload, 0, fn
      {_key, @provider_capability_unavailable_reason}, total ->
        total + 1

      {_key, value}, total ->
        total + count(value)
    end)
  end

  def count(values) when is_list(values) do
    Enum.reduce(values, 0, fn value, total -> total + count(value) end)
  end

  def count(@provider_capability_unavailable_reason), do: 1
  def count(_value), do: 0

  @spec collect(term()) :: [t()]
  def collect(payload) do
    payload
    |> do_collect([])
    |> Enum.reverse()
  end

  @spec to_maps([t()]) :: [map()]
  def to_maps(details) when is_list(details), do: Enum.map(details, &to_map/1)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = detail) do
    %{
      @capability_key => detail.capability,
      @description_key => detail.description,
      @reason_key => detail.reason
    }
    |> drop_nil_values()
  end

  defp do_collect(%{} = payload, acc) do
    acc =
      if unavailable?(payload) do
        [from_payload(payload) | acc]
      else
        acc
      end

    Enum.reduce(payload, acc, fn {_key, value}, details ->
      do_collect(value, details)
    end)
  end

  defp do_collect(values, acc) when is_list(values) do
    Enum.reduce(values, acc, &do_collect/2)
  end

  defp do_collect(_value, acc), do: acc

  defp unavailable?(payload) when is_map(payload), do: string_field(payload, @reason_key) == @provider_capability_unavailable_reason

  defp from_payload(payload) when is_map(payload) do
    %__MODULE__{
      capability: string_field(payload, @capability_key),
      description: string_field(payload, @description_key),
      reason: @provider_capability_unavailable_reason
    }
  end

  defp string_field(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)
  defp string_field(_map, _key), do: nil

  defp drop_nil_values(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end

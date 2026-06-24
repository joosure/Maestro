defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Payload do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference, as: KnownTargetReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Contract

  @spec provider_target_opts(map()) :: keyword()
  def provider_target_opts(target) when is_map(target) do
    case target_value(target, :number) || target_value(target, :url) || target_value(target, :branch) do
      value when is_binary(value) -> [number: value]
      value when is_integer(value) -> [number: Integer.to_string(value)]
      _value -> []
    end
  end

  @spec provider_target_opts(map(), map()) :: keyword()
  def provider_target_opts(pr_payload, target) when is_map(pr_payload) and is_map(target) do
    provider_target_opts(%{
      number: present_string(field_value(pr_payload, Contract.payload_key(:number))) || target_value(target, :number),
      url: target_value(target, :url),
      branch: target_value(target, :branch)
    })
  end

  @spec target_value(map(), atom()) :: term()
  def target_value(%KnownTargetReference{} = target, :number), do: target.number
  def target_value(%KnownTargetReference{} = target, :url), do: target.url
  def target_value(%KnownTargetReference{} = target, :branch), do: target.branch
  def target_value(map, key) when is_map(map) and is_atom(key), do: Map.get(map, key)
  def target_value(_map, _key), do: nil

  @spec field_value(map(), String.t()) :: term()
  def field_value(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)
  def field_value(_map, _key), do: nil

  @spec normalize_token(term()) :: String.t()
  def normalize_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  def normalize_token(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_token()
  def normalize_token(_value), do: ""

  @spec present_string(term()) :: String.t() | nil
  def present_string(value) when is_integer(value), do: Integer.to_string(value)

  def present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def present_string(_value), do: nil

  @spec present?(term()) :: boolean()
  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(value), do: not is_nil(value)
end

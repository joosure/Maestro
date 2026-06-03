defmodule SymphonyElixir.Agent.DynamicTool.EvidencePayload do
  @moduledoc """
  Canonical evidence emitted by typed tool executors.

  Provider executors should translate provider-native responses into this
  contract before returning. Consumers such as readiness recorders can then
  depend on this stable shape instead of knowing each provider's response
  envelope.
  """

  @key "evidence"
  @schema "symphony.typed_tool.evidence.v1"

  @spec key() :: String.t()
  def key, do: @key

  @spec schema() :: String.t()
  def schema, do: @schema

  @spec attach(map(), map() | nil) :: map()
  def attach(payload, evidence) when is_map(payload) and is_map(evidence), do: Map.put(payload, @key, evidence)
  def attach(payload, _evidence) when is_map(payload), do: payload

  @spec fetch(map()) :: map() | nil
  def fetch(%{@key => %{"schema" => @schema} = evidence}), do: evidence
  def fetch(_payload), do: nil

  @spec workpad(map()) :: map()
  def workpad(comment) when is_map(comment) do
    %{
      "schema" => @schema,
      "kind" => "workpad",
      "workpad" =>
        compact(%{
          "status" => write_status(comment),
          "id" => string_value(comment, "id"),
          "provider_ref" => Map.get(comment, "provider_ref"),
          "url" => string_value(comment, "url")
        })
    }
  end

  @spec tracker_change_proposal(map(), map()) :: map()
  def tracker_change_proposal(attachment, attrs \\ %{})

  def tracker_change_proposal(attachment, attrs) when is_map(attachment) and is_map(attrs) do
    %{
      "schema" => @schema,
      "kind" => "tracker_change_proposal",
      "change_proposal" =>
        compact(%{
          "id" => string_value(attrs, "change_proposal_id") || string_value(attachment, "id"),
          "url" => string_value(attachment, "url") || string_value(attrs, "url"),
          "provider_kind" => string_value(attrs, "repo_provider_kind"),
          "repository" => string_value(attrs, "repository"),
          "linked_to_tracker" => true
        })
    }
  end

  def tracker_change_proposal(_attachment, _attrs), do: nil

  defp write_status(%{"created" => true}), do: "created"
  defp write_status(%{"updated" => true}), do: "updated"
  defp write_status(_comment), do: "updated"

  defp string_value(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) || map_get_existing_atom(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      value when is_integer(value) ->
        Integer.to_string(value)

      value when is_atom(value) and not is_nil(value) ->
        value |> Atom.to_string() |> string_value_from_string()

      _value ->
        nil
    end
  end

  defp string_value(_map, _key), do: nil

  defp string_value_from_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp compact(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) or value == [] end)
  end
end

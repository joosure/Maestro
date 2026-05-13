defmodule SymphonyElixir.Agent.DynamicTool.Usage do
  @moduledoc """
  Classifies Dynamic Tool calls for production audit and usage metrics.

  The `fallback` usage kind is reserved for explicitly configured operator
  migration fallback while a missing typed capability is being replaced. Normal
  workflow sessions should use `typed`; unsupported or retired passthrough tool
  attempts remain `raw` and must be rejected before source execution.
  """

  alias SymphonyElixir.Agent.DynamicTool.Context

  @type classification :: %{
          required(:usage_kind) => String.t(),
          required(:tool_name) => String.t() | nil,
          optional(:workflow_capability) => String.t(),
          optional(:side_effect) => String.t(),
          optional(:source_kind) => String.t(),
          optional(:schema_version) => String.t(),
          optional(:deprecated?) => boolean(),
          optional(:operator_only?) => boolean(),
          optional(:exposure) => String.t(),
          optional(:fallback_reason) => String.t(),
          optional(:fallback_ambiguous?) => boolean()
        }

  @spec classify(map(), String.t() | nil, keyword()) :: classification()
  def classify(tool_context, tool, opts \\ [])

  def classify(tool_context, tool, opts)
      when is_map(tool_context) and is_binary(tool) and is_list(opts) do
    metadata = metadata_for(tool_context, tool)
    fallback = fallback_for_tool(tool, opts)

    base = %{
      usage_kind: usage_kind(metadata, fallback),
      tool_name: tool,
      side_effect: string_field(metadata, "sideEffect"),
      source_kind: string_field(metadata, "sourceKind") || Context.source_kind(tool_context),
      schema_version: string_field(metadata, "schemaVersion"),
      deprecated?: Map.get(metadata, "deprecated", false) == true,
      operator_only?: Map.get(metadata, "operatorOnly", false) == true
    }

    base
    |> put_optional(
      :workflow_capability,
      string_field(metadata, "workflowCapability") || fallback_capability(fallback)
    )
    |> put_optional(:exposure, exposure(tool_context))
    |> put_optional(:fallback_reason, fallback_reason(fallback))
    |> put_optional(:fallback_ambiguous?, fallback_ambiguous?(fallback))
  end

  def classify(tool_context, tool, _opts) do
    %{
      usage_kind: "raw",
      tool_name: tool
    }
    |> put_optional(:exposure, exposure(tool_context))
  end

  @spec audit_fields(map(), String.t() | nil, keyword()) :: map()
  def audit_fields(tool_context, tool, opts \\ []) do
    classification = classify(tool_context, tool, opts)

    %{
      dynamic_tool_usage_kind: classification.usage_kind,
      dynamic_tool_workflow_capability: Map.get(classification, :workflow_capability),
      dynamic_tool_side_effect: Map.get(classification, :side_effect),
      dynamic_tool_source_kind: Map.get(classification, :source_kind),
      dynamic_tool_schema_version: Map.get(classification, :schema_version),
      dynamic_tool_deprecated: Map.get(classification, :deprecated?),
      dynamic_tool_operator_only: Map.get(classification, :operator_only?),
      dynamic_tool_exposure: Map.get(classification, :exposure),
      dynamic_tool_fallback_reason: Map.get(classification, :fallback_reason),
      dynamic_tool_fallback_ambiguous: Map.get(classification, :fallback_ambiguous?)
    }
    |> drop_nil_values()
  end

  @spec failure_reason(term()) :: String.t() | nil
  def failure_reason(%{"success" => true}), do: nil
  def failure_reason(%{success: true}), do: nil

  def failure_reason(%{"payload" => payload}), do: error_reason(payload)
  def failure_reason(%{payload: payload}), do: error_reason(payload)

  def failure_reason(%{"output" => output}) when is_binary(output) do
    case Jason.decode(output) do
      {:ok, payload} -> error_reason(payload)
      {:error, _reason} -> nil
    end
  end

  def failure_reason(%{output: output}) when is_binary(output),
    do: failure_reason(%{"output" => output})

  def failure_reason(payload), do: error_reason(payload)

  @spec provider_capability_unavailable_count(term()) :: non_neg_integer()
  def provider_capability_unavailable_count(payload) do
    count_provider_capability_unavailable(payload)
  end

  @spec provider_capability_unavailable_details(term()) :: [map()]
  def provider_capability_unavailable_details(payload) do
    payload
    |> collect_provider_capability_unavailable([])
    |> Enum.reverse()
  end

  defp usage_kind(%{"workflowCapability" => capability}, _fallback) when is_binary(capability),
    do: "typed"

  defp usage_kind(_metadata, %{tool: tool}) when is_binary(tool), do: "fallback"
  defp usage_kind(_metadata, _fallback), do: "raw"

  defp metadata_for(tool_context, tool) do
    metadata =
      Map.get(tool_context, :tool_metadata) || Map.get(tool_context, "tool_metadata") || %{}

    Map.get(metadata, tool, %{})
  end

  defp fallback_for_tool(tool, opts) do
    opts
    |> fallback_policy()
    |> Enum.filter(fn {_capability, fallback} -> Map.get(fallback, :tool) == tool end)
    |> Enum.sort_by(fn {capability, _fallback} -> capability end)
    |> case do
      [] ->
        nil

      [{capability, fallback}] ->
        Map.put(fallback, :capability, capability)

      matches ->
        {capability, fallback} = hd(matches)

        fallback
        |> Map.put(:capability, capability)
        |> Map.put(:ambiguous?, true)
    end
  end

  defp fallback_policy(opts) do
    opts
    |> Keyword.get_lazy(:typed_workflow_tool_fallback_policy, fn ->
      Keyword.get_lazy(opts, :fallback_policy, fn ->
        Application.get_env(:symphony_elixir, :typed_workflow_tool_fallback_policy, %{})
      end)
    end)
    |> normalize_fallback_policy()
  end

  defp normalize_fallback_policy(policy) when is_map(policy) do
    policy
    |> Enum.flat_map(fn {capability, fallback} ->
      with {:ok, capability} <- normalize_string(capability),
           {:ok, fallback} <- normalize_fallback(fallback) do
        [{capability, fallback}]
      else
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp normalize_fallback_policy(_policy), do: %{}

  defp normalize_fallback(tool) when is_binary(tool) do
    with {:ok, tool} <- normalize_string(tool) do
      {:ok, %{tool: tool}}
    end
  end

  defp normalize_fallback(fallback) when is_map(fallback) do
    with {:ok, tool} <- fallback |> string_field("tool") |> normalize_string() do
      reason =
        fallback
        |> string_field("reason")
        |> normalize_string()
        |> case do
          {:ok, value} -> value
          :error -> nil
        end

      {:ok, %{tool: tool, reason: reason}}
    end
  end

  defp normalize_fallback(_fallback), do: :error

  defp fallback_capability(%{capability: capability}) when is_binary(capability), do: capability
  defp fallback_capability(_fallback), do: nil

  defp fallback_reason(%{reason: reason}) when is_binary(reason), do: reason
  defp fallback_reason(_fallback), do: nil

  defp fallback_ambiguous?(%{ambiguous?: true}), do: true
  defp fallback_ambiguous?(_fallback), do: nil

  defp exposure(%{tool_plan: %{exposure: exposure}}) when is_binary(exposure), do: exposure
  defp exposure(%{"tool_plan" => %{"exposure" => exposure}}) when is_binary(exposure), do: exposure
  defp exposure(_tool_context), do: nil

  defp error_reason(%{"error" => %{"code" => code}}) when is_binary(code) and code != "", do: code

  defp error_reason(%{"error" => %{"message" => message}})
       when is_binary(message) and message != "", do: message

  defp error_reason(%{error: error}), do: error_reason(%{"error" => error})
  defp error_reason(_payload), do: nil

  defp count_provider_capability_unavailable(%{} = payload) do
    Enum.reduce(payload, 0, fn
      {_key, "provider_capability_not_available"}, total ->
        total + 1

      {_key, value}, total ->
        total + count_provider_capability_unavailable(value)
    end)
  end

  defp count_provider_capability_unavailable(values) when is_list(values) do
    Enum.reduce(values, 0, fn value, total ->
      total + count_provider_capability_unavailable(value)
    end)
  end

  defp count_provider_capability_unavailable("provider_capability_not_available"), do: 1
  defp count_provider_capability_unavailable(_value), do: 0

  defp collect_provider_capability_unavailable(%{} = payload, acc) do
    acc =
      if provider_capability_unavailable?(payload) do
        [provider_capability_detail(payload) | acc]
      else
        acc
      end

    Enum.reduce(payload, acc, fn {_key, value}, details ->
      collect_provider_capability_unavailable(value, details)
    end)
  end

  defp collect_provider_capability_unavailable(values, acc) when is_list(values) do
    Enum.reduce(values, acc, &collect_provider_capability_unavailable/2)
  end

  defp collect_provider_capability_unavailable(_value, acc), do: acc

  defp provider_capability_unavailable?(payload) when is_map(payload) do
    string_field(payload, "reason") == "provider_capability_not_available"
  end

  defp provider_capability_detail(payload) when is_map(payload) do
    %{
      "workflowCapability" => string_field(payload, "workflowCapability"),
      "description" => string_field(payload, "description"),
      "reason" => "provider_capability_not_available"
    }
    |> drop_nil_values()
  end

  defp string_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, snake_key(key)) || Map.get(map, atom_key(key))
  end

  defp string_field(_map, _key), do: nil

  defp snake_key("workflowCapability"), do: "workflow_capability"
  defp snake_key("sideEffect"), do: "side_effect"
  defp snake_key("sourceKind"), do: "source_kind"
  defp snake_key("schemaVersion"), do: "schema_version"
  defp snake_key(key), do: key

  defp atom_key("workflowCapability"), do: :workflowCapability
  defp atom_key("sideEffect"), do: :sideEffect
  defp atom_key("sourceKind"), do: :sourceKind
  defp atom_key("schemaVersion"), do: :schemaVersion
  defp atom_key("tool"), do: :tool
  defp atom_key("reason"), do: :reason

  defp atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :error
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_string()

  defp normalize_string(_value), do: :error

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, _key, ""), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end

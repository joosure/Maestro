defmodule SymphonyElixir.Agent.DynamicTool.Usage do
  @moduledoc """
  Classifies Dynamic Tool calls for production audit and usage metrics.

  Normal sessions should use `typed`; unsupported passthrough tool attempts
  remain `raw` and must be rejected before source execution.
  """

  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.Usage.{Classification, FailureReason, ProviderCapabilityUnavailable}

  @type classification :: Classification.t()

  @spec classify(Context.t(), String.t() | nil, keyword()) :: classification()
  def classify(tool_context, tool, opts \\ [])

  def classify(%Context{} = tool_context, tool, _opts) when is_binary(tool) do
    metadata = Context.metadata_for(tool_context, tool)

    Classification.from_metadata(
      tool,
      metadata,
      Context.source_kind(tool_context),
      Context.tool_plan_exposure(tool_context)
    )
  end

  def classify(%Context{} = tool_context, tool, _opts) do
    Classification.raw(tool, Context.tool_plan_exposure(tool_context))
  end

  @spec audit_fields(Context.t(), String.t() | nil, keyword()) :: map()
  def audit_fields(%Context{} = tool_context, tool, opts \\ []) do
    tool_context
    |> classify(tool, opts)
    |> Classification.to_audit_fields()
  end

  @spec failure_reason(term()) :: String.t() | nil
  def failure_reason(response), do: FailureReason.from_response(response)

  @spec provider_capability_unavailable_count(term()) :: non_neg_integer()
  def provider_capability_unavailable_count(payload) do
    ProviderCapabilityUnavailable.count(payload)
  end

  @spec provider_capability_unavailable_details(term()) :: [map()]
  def provider_capability_unavailable_details(payload) do
    payload
    |> ProviderCapabilityUnavailable.collect()
    |> ProviderCapabilityUnavailable.to_maps()
  end
end

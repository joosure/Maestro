defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.Config do
  @moduledoc false

  @default_threshold 3

  @spec defaults() :: keyword()
  def defaults do
    [
      threshold: threshold(),
      retry_policies: retry_policies(),
      resource_identity: resource_identity(),
      audit_fields: audit_fields()
    ]
  end

  @spec threshold() :: pos_integer()
  def threshold do
    case Application.get_env(:symphony_elixir, :typed_tool_failure_retry_threshold, @default_threshold) do
      threshold when is_integer(threshold) and threshold > 0 -> threshold
      _threshold -> @default_threshold
    end
  end

  @spec retry_policies() :: map()
  def retry_policies do
    Application.get_env(:symphony_elixir, :typed_tool_failure_retry_policies, %{})
  end

  @spec resource_identity() :: function() | nil
  def resource_identity do
    Application.get_env(:symphony_elixir, :typed_tool_failure_resource_identity)
  end

  @spec audit_fields() :: function() | nil
  def audit_fields do
    Application.get_env(:symphony_elixir, :typed_tool_failure_audit_fields)
  end
end

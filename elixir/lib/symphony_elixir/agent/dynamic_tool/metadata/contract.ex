defmodule SymphonyElixir.Agent.DynamicTool.Metadata.Contract do
  @moduledoc """
  Stable metadata keys and values for Dynamic Tool inventory and observability.
  """

  @capability "capability"
  @side_effect "sideEffect"
  @source_kind "sourceKind"
  @schema_version "schemaVersion"
  @risk_flags "riskFlags"
  @operator_only "operatorOnly"
  @tool_alias_of "toolAliasOf"
  @description "description"
  @reason "reason"
  @tool "tool"

  @read_only_side_effect "read_only"
  @write_side_effect "write"
  @destructive_side_effect "destructive"
  @default_side_effect @destructive_side_effect
  @default_schema_version "1"
  @side_effect_classes [@read_only_side_effect, @write_side_effect, @destructive_side_effect]

  @typed_usage_kind "typed"
  @raw_usage_kind "raw"
  @provider_capability_unavailable_reason "provider_capability_not_available"

  @spec capability() :: String.t()
  def capability, do: @capability

  @spec side_effect() :: String.t()
  def side_effect, do: @side_effect

  @spec source_kind() :: String.t()
  def source_kind, do: @source_kind

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec risk_flags() :: String.t()
  def risk_flags, do: @risk_flags

  @spec operator_only() :: String.t()
  def operator_only, do: @operator_only

  @spec tool_alias_of() :: String.t()
  def tool_alias_of, do: @tool_alias_of

  @spec description() :: String.t()
  def description, do: @description

  @spec reason() :: String.t()
  def reason, do: @reason

  @spec tool() :: String.t()
  def tool, do: @tool

  @spec side_effect_classes() :: [String.t()]
  def side_effect_classes, do: @side_effect_classes

  @spec read_only_side_effect() :: String.t()
  def read_only_side_effect, do: @read_only_side_effect

  @spec write_side_effect() :: String.t()
  def write_side_effect, do: @write_side_effect

  @spec default_side_effect() :: String.t()
  def default_side_effect, do: @default_side_effect

  @spec default_schema_version() :: String.t()
  def default_schema_version, do: @default_schema_version

  @spec typed_usage_kind() :: String.t()
  def typed_usage_kind, do: @typed_usage_kind

  @spec raw_usage_kind() :: String.t()
  def raw_usage_kind, do: @raw_usage_kind

  @spec usage_kinds() :: [String.t()]
  def usage_kinds, do: [@typed_usage_kind, @raw_usage_kind]

  @spec provider_capability_unavailable_reason() :: String.t()
  def provider_capability_unavailable_reason, do: @provider_capability_unavailable_reason
end

defmodule SymphonyElixir.Agent.DynamicTool.MetadataContract do
  @moduledoc """
  Stable metadata keys and values for Dynamic Tool inventory and observability.
  """

  @workflow_capability "workflowCapability"
  @workflow_capability_snake "workflow_capability"
  @side_effect "sideEffect"
  @side_effect_snake "side_effect"
  @side_effect_class "sideEffectClass"
  @side_effect_class_snake "side_effect_class"
  @source_kind "sourceKind"
  @source_kind_snake "source_kind"
  @schema_version "schemaVersion"
  @schema_version_snake "schema_version"
  @risk_flags "riskFlags"
  @risk_flags_snake "risk_flags"
  @deprecated_field "deprecated"
  @operator_only "operatorOnly"
  @operator_only_snake "operator_only"
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
  @fallback_usage_kind "fallback"
  @provider_capability_unavailable_reason "provider_capability_not_available"

  @spec workflow_capability() :: String.t()
  def workflow_capability, do: @workflow_capability

  @spec workflow_capability_keys() :: [String.t()]
  def workflow_capability_keys, do: [@workflow_capability, @workflow_capability_snake]

  @spec side_effect() :: String.t()
  def side_effect, do: @side_effect

  @spec side_effect_class() :: String.t()
  def side_effect_class, do: @side_effect_class

  @spec side_effect_keys() :: [String.t()]
  def side_effect_keys, do: [@side_effect, @side_effect_snake, @side_effect_class, @side_effect_class_snake]

  @spec source_kind() :: String.t()
  def source_kind, do: @source_kind

  @spec source_kind_keys() :: [String.t()]
  def source_kind_keys, do: [@source_kind, @source_kind_snake]

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec schema_version_keys() :: [String.t()]
  def schema_version_keys, do: [@schema_version, @schema_version_snake]

  @spec risk_flags() :: String.t()
  def risk_flags, do: @risk_flags

  @spec risk_flags_keys() :: [String.t()]
  def risk_flags_keys, do: [@risk_flags, @risk_flags_snake]

  @spec deprecated() :: String.t()
  def deprecated, do: @deprecated_field

  @spec operator_only() :: String.t()
  def operator_only, do: @operator_only

  @spec operator_only_keys() :: [String.t()]
  def operator_only_keys, do: [@operator_only, @operator_only_snake]

  @spec description() :: String.t()
  def description, do: @description

  @spec reason() :: String.t()
  def reason, do: @reason

  @spec tool() :: String.t()
  def tool, do: @tool

  @spec side_effect_classes() :: [String.t()]
  def side_effect_classes, do: @side_effect_classes

  @spec default_side_effect() :: String.t()
  def default_side_effect, do: @default_side_effect

  @spec default_schema_version() :: String.t()
  def default_schema_version, do: @default_schema_version

  @spec typed_usage_kind() :: String.t()
  def typed_usage_kind, do: @typed_usage_kind

  @spec raw_usage_kind() :: String.t()
  def raw_usage_kind, do: @raw_usage_kind

  @spec fallback_usage_kind() :: String.t()
  def fallback_usage_kind, do: @fallback_usage_kind

  @spec usage_kinds() :: [String.t()]
  def usage_kinds, do: [@typed_usage_kind, @raw_usage_kind, @fallback_usage_kind]

  @spec provider_capability_unavailable_reason() :: String.t()
  def provider_capability_unavailable_reason, do: @provider_capability_unavailable_reason

  @spec field_value(map(), String.t()) :: term()
  def field_value(map, field) when is_map(map) and is_binary(field) do
    field
    |> field_aliases()
    |> Enum.find_value(fn key ->
      cond do
        Map.has_key?(map, key) -> Map.get(map, key)
        Map.has_key?(map, atom_field(key)) -> Map.get(map, atom_field(key))
        true -> nil
      end
    end)
  end

  def field_value(_map, _field), do: nil

  @spec field_aliases(String.t()) :: [String.t()]
  def field_aliases(@workflow_capability), do: workflow_capability_keys()
  def field_aliases(@side_effect), do: side_effect_keys()
  def field_aliases(@side_effect_class), do: side_effect_keys()
  def field_aliases(@source_kind), do: source_kind_keys()
  def field_aliases(@schema_version), do: schema_version_keys()
  def field_aliases(@risk_flags), do: risk_flags_keys()
  def field_aliases(@operator_only), do: operator_only_keys()
  def field_aliases(field) when is_binary(field), do: [field]

  @spec atom_field(String.t()) :: atom() | nil
  def atom_field(@workflow_capability), do: :workflowCapability
  def atom_field(@workflow_capability_snake), do: :workflow_capability
  def atom_field(@side_effect), do: :sideEffect
  def atom_field(@side_effect_snake), do: :side_effect
  def atom_field(@side_effect_class), do: :sideEffectClass
  def atom_field(@side_effect_class_snake), do: :side_effect_class
  def atom_field(@source_kind), do: :sourceKind
  def atom_field(@source_kind_snake), do: :source_kind
  def atom_field(@schema_version), do: :schemaVersion
  def atom_field(@schema_version_snake), do: :schema_version
  def atom_field(@risk_flags), do: :riskFlags
  def atom_field(@risk_flags_snake), do: :risk_flags
  def atom_field(@deprecated_field), do: :deprecated
  def atom_field(@operator_only), do: :operatorOnly
  def atom_field(@operator_only_snake), do: :operator_only
  def atom_field(@description), do: :description
  def atom_field(@reason), do: :reason
  def atom_field(@tool), do: :tool
  def atom_field(_field), do: nil
end

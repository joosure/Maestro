defmodule SymphonyElixir.Agent.DynamicTool.Usage.Classification do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Metadata

  @typed_usage_kind Metadata.Contract.typed_usage_kind()
  @raw_usage_kind Metadata.Contract.raw_usage_kind()

  defstruct usage_kind: @raw_usage_kind,
            tool_name: nil,
            capability: nil,
            side_effect: nil,
            source_kind: nil,
            schema_version: nil,
            operator_only?: nil,
            exposure: nil

  @type t :: %__MODULE__{
          usage_kind: String.t(),
          tool_name: String.t() | nil,
          capability: String.t() | nil,
          side_effect: String.t() | nil,
          source_kind: String.t() | nil,
          schema_version: String.t() | nil,
          operator_only?: boolean() | nil,
          exposure: String.t() | nil
        }

  @spec typed(keyword()) :: t()
  def typed(attrs) when is_list(attrs) do
    struct!(__MODULE__, Keyword.put(attrs, :usage_kind, @typed_usage_kind))
  end

  @spec raw(String.t() | nil, String.t() | nil) :: t()
  def raw(tool_name, exposure) do
    %__MODULE__{
      usage_kind: @raw_usage_kind,
      tool_name: normalize_tool_name(tool_name),
      exposure: normalize_string(exposure)
    }
  end

  @spec from_metadata(String.t(), Metadata.t(), String.t() | nil, String.t() | nil) :: t()
  def from_metadata(tool_name, %Metadata{} = metadata, source_kind, exposure) when is_binary(tool_name) do
    usage_kind = if is_binary(metadata.capability), do: @typed_usage_kind, else: @raw_usage_kind

    %__MODULE__{
      usage_kind: usage_kind,
      tool_name: tool_name,
      capability: normalize_string(metadata.capability),
      side_effect: normalize_string(metadata.side_effect),
      source_kind: normalize_string(metadata.source_kind) || normalize_string(source_kind),
      schema_version: normalize_string(metadata.schema_version),
      operator_only?: metadata.operator_only? == true,
      exposure: normalize_string(exposure)
    }
  end

  @spec to_audit_fields(t()) :: map()
  def to_audit_fields(%__MODULE__{} = classification) do
    %{
      dynamic_tool_usage_kind: classification.usage_kind,
      dynamic_tool_capability: classification.capability,
      dynamic_tool_side_effect: classification.side_effect,
      dynamic_tool_source_kind: classification.source_kind,
      dynamic_tool_schema_version: classification.schema_version,
      dynamic_tool_operator_only: classification.operator_only?,
      dynamic_tool_exposure: classification.exposure
    }
    |> drop_nil_values()
  end

  defp normalize_tool_name(tool_name) when is_binary(tool_name) do
    case String.trim(tool_name) do
      "" -> nil
      tool_name -> tool_name
    end
  end

  defp normalize_tool_name(_tool_name), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_string(_value), do: nil

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end

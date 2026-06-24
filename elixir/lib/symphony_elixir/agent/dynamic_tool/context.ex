defmodule SymphonyElixir.Agent.DynamicTool.Context do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.CompositeSource
  alias SymphonyElixir.Agent.DynamicTool.CompositeSource.Context, as: CompositeSourceContext
  alias SymphonyElixir.Agent.DynamicTool.Context.RuntimeMetadata
  alias SymphonyElixir.Agent.DynamicTool.Context.ToolPlan
  alias SymphonyElixir.Agent.DynamicTool.{Metadata, Source, ToolSpec}

  @empty_source Source.composite_source()

  defstruct source: @empty_source,
            source_context: CompositeSourceContext.empty(),
            source_kind: CompositeSource.kind(),
            tool_specs: [],
            tool_metadata: %{},
            tool_environment: %{},
            runtime_metadata: RuntimeMetadata.empty(),
            adoption_settings: %{},
            tool_plan: nil

  @type t :: %__MODULE__{
          source: module(),
          source_context: term(),
          source_kind: String.t() | nil,
          tool_specs: [ToolSpec.t()],
          tool_metadata: %{String.t() => Metadata.t()},
          tool_environment: map(),
          runtime_metadata: RuntimeMetadata.t(),
          adoption_settings: map(),
          tool_plan: ToolPlan.t() | nil
        }

  @spec empty() :: t()
  def empty do
    %__MODULE__{}
  end

  @spec capture(keyword()) :: t()
  defdelegate capture(opts \\ []), to: __MODULE__.Capture

  @spec capture_strict(keyword()) :: {:ok, t()} | :error
  defdelegate capture_strict(opts \\ []), to: __MODULE__.Capture

  @spec from_opts(keyword()) :: t()
  defdelegate from_opts(opts), to: __MODULE__.Normalizer

  @spec from_opts_strict(keyword()) :: {:ok, t()} | :error
  defdelegate from_opts_strict(opts), to: __MODULE__.Normalizer

  @spec normalize(term()) :: t()
  defdelegate normalize(context), to: __MODULE__.Normalizer

  @spec normalize_strict(term()) :: {:ok, t()} | :error
  defdelegate normalize_strict(context), to: __MODULE__.Normalizer

  @spec source(t()) :: module()
  defdelegate source(context), to: __MODULE__.Query

  @spec source_context(t()) :: term()
  defdelegate source_context(context), to: __MODULE__.Query

  @spec source_kind(t()) :: String.t() | nil
  defdelegate source_kind(context), to: __MODULE__.Query

  @spec tool_specs(t()) :: [map()]
  defdelegate tool_specs(context), to: __MODULE__.Query

  @spec tool_spec(t(), String.t()) :: map() | nil
  defdelegate tool_spec(context, name), to: __MODULE__.Query

  @spec tool_spec_record(t(), String.t()) :: ToolSpec.t() | nil
  defdelegate tool_spec_record(context, name), to: __MODULE__.Query

  @spec tool_enabled?(t(), String.t()) :: boolean()
  defdelegate tool_enabled?(context, name), to: __MODULE__.Query

  @spec tool_metadata(t()) :: map()
  defdelegate tool_metadata(context), to: __MODULE__.Query

  @spec metadata_for(t(), String.t()) :: Metadata.t()
  defdelegate metadata_for(context, tool), to: __MODULE__.Query

  @spec tool_plan_exposure(t()) :: String.t() | nil
  defdelegate tool_plan_exposure(context), to: __MODULE__.Query

  @spec runtime_metadata(t()) :: RuntimeMetadata.t()
  defdelegate runtime_metadata(context), to: __MODULE__.Query

  @spec runtime_metadata_value(t(), atom() | String.t()) :: term()
  defdelegate runtime_metadata_value(context, field), to: __MODULE__.Query

  @spec restrict_tools(t(), [String.t()]) :: t()
  defdelegate restrict_tools(context, tool_names), to: __MODULE__.Restrictor
end

defmodule SymphonyElixir.Agent.DynamicTool.Context.Normalizer do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.CompositeSource.Context, as: CompositeSourceContext
  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.Context.Fields
  alias SymphonyElixir.Agent.DynamicTool.Context.RuntimeMetadata
  alias SymphonyElixir.Agent.DynamicTool.Context.ToolPlan
  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Agent.DynamicTool.Source
  alias SymphonyElixir.Agent.DynamicTool.Source.{Environment, Kind}
  alias SymphonyElixir.Agent.DynamicTool.ToolSpec

  @empty_source Source.composite_source()

  @spec normalize(term()) :: Context.t()
  def normalize(context) do
    case normalize_strict(context) do
      {:ok, normalized} -> normalized
      :error -> Context.empty()
    end
  end

  @spec normalize_strict(term()) :: {:ok, Context.t()} | :error
  def normalize_strict(%Context{} = context), do: normalize_context(context, [])
  def normalize_strict(context) when is_map(context), do: normalize_context(context, [])
  def normalize_strict(_context), do: :error

  @spec from_opts(keyword()) :: Context.t()
  def from_opts(opts) when is_list(opts) do
    case from_opts_strict(opts) do
      {:ok, context} -> context
      :error -> Context.empty()
    end
  end

  @spec from_opts_strict(keyword()) :: {:ok, Context.t()} | :error
  def from_opts_strict(opts) when is_list(opts) do
    case Keyword.get(opts, :tool_context) do
      %Context{} = context ->
        normalize_context(context, opts)

      context when is_map(context) ->
        normalize_context(context, opts)

      nil ->
        Context.Capture.capture_strict(opts)

      _context ->
        :error
    end
  end

  def from_opts_strict(_opts), do: :error

  @spec normalize_context(map(), keyword()) :: {:ok, Context.t()} | :error
  def normalize_context(context, opts) when is_map(context) and is_list(opts) do
    with {:ok, raw_tool_specs} <- field_list(context, Fields.tool_specs(), []),
         {:ok, source} <- context_source(context, opts),
         {:ok, source_context} <- context_source_context(context, source, opts),
         {:ok, source_kind} <- context_source_kind(context, source, source_context),
         {:ok, tool_specs} <- normalize_tool_specs(raw_tool_specs),
         {:ok, tool_metadata} <- context_metadata(context, raw_tool_specs, tool_specs),
         {:ok, tool_environment} <- context_environment(context),
         {:ok, runtime_metadata} <- context_runtime_metadata(context),
         {:ok, adoption_settings} <- field_map(context, Fields.adoption_settings(), %{}),
         {:ok, tool_plan} <- context_tool_plan(context) do
      context =
        %Context{
          source: source,
          source_context: normalize_source_context(source, source_context),
          source_kind: source_kind,
          tool_specs: tool_specs,
          tool_metadata: tool_metadata,
          tool_environment: tool_environment,
          runtime_metadata: runtime_metadata,
          adoption_settings: adoption_settings,
          tool_plan: tool_plan
        }
        |> put_adoption_settings(opts)

      {:ok, context}
    end
  end

  @spec put_adoption_settings(Context.t(), keyword()) :: Context.t()
  def put_adoption_settings(%Context{} = context, opts) when is_list(opts) do
    existing = Fields.value(context, Fields.adoption_settings())

    adoption_settings =
      if non_empty_map?(existing) do
        existing
      else
        Keyword.get(opts, :adoption_settings)
      end

    case normalize_map(adoption_settings) do
      adoption_settings when map_size(adoption_settings) > 0 ->
        Map.put(context, :adoption_settings, adoption_settings)

      _adoption_settings ->
        context
    end
  end

  @spec normalize_source(term(), keyword()) :: module()
  def normalize_source(source, opts) when is_atom(source) and not is_nil(source) and is_list(opts) do
    if Source.valid?(source), do: source, else: @empty_source
  end

  def normalize_source(_source, opts) when is_list(opts), do: Source.from_opts(opts)

  @spec normalize_source_context(module(), term()) :: term()
  def normalize_source_context(source, source_context) when source == @empty_source,
    do: CompositeSourceContext.normalize(source_context)

  def normalize_source_context(_source, source_context), do: source_context

  @spec normalize_metadata(term(), [term()], [ToolSpec.t()]) :: %{String.t() => Metadata.t()}
  def normalize_metadata(metadata, raw_tool_specs, tool_specs) when is_list(raw_tool_specs) and is_list(tool_specs) do
    raw_tool_specs
    |> Metadata.from_tool_specs()
    |> Map.merge(explicit_metadata(metadata))
    |> Map.take(tool_names(tool_specs))
  end

  defp context_source(context, opts) do
    case Fields.fetch(context, Fields.source()) do
      {:ok, source} when is_atom(source) and not is_nil(source) ->
        if Source.valid?(source), do: {:ok, source}, else: :error

      {:ok, nil} ->
        :error

      {:ok, _source} ->
        :error

      :error ->
        capture_source(opts)
    end
  end

  defp capture_source(opts) do
    {:ok, Source.from_opts(opts)}
  rescue
    ArgumentError -> :error
  end

  defp context_source_context(context, source, opts) do
    case Fields.fetch(context, Fields.source_context()) do
      {:ok, source_context} -> {:ok, source_context}
      :error -> source_default_context(source, opts)
    end
  end

  defp source_default_context(source, opts) do
    {:ok, Source.default_context(source, opts)}
  rescue
    ArgumentError -> :error
  end

  defp context_source_kind(context, source, source_context) do
    case Fields.fetch(context, Fields.source_kind()) do
      {:ok, source_kind} -> strict_source_kind(source_kind)
      :error -> source_kind(source, source_context)
    end
  end

  defp strict_source_kind(source_kind) when is_binary(source_kind) or is_nil(source_kind),
    do: {:ok, Kind.normalize(source_kind)}

  defp strict_source_kind(_source_kind), do: :error

  defp source_kind(source, source_context) do
    {:ok, Source.kind(source, source_context)}
  rescue
    ArgumentError -> :error
  end

  defp normalize_tool_specs(raw_tool_specs) do
    case ToolSpec.normalize_many_strict(raw_tool_specs) do
      {:ok, tool_specs} -> {:ok, tool_specs}
      {:error, _errors} -> :error
    end
  end

  defp context_metadata(context, raw_tool_specs, tool_specs) do
    case Fields.fetch(context, Fields.tool_metadata()) do
      {:ok, metadata} when is_map(metadata) -> {:ok, normalize_metadata(metadata, raw_tool_specs, tool_specs)}
      {:ok, nil} -> {:ok, normalize_metadata(nil, raw_tool_specs, tool_specs)}
      {:ok, _metadata} -> :error
      :error -> {:ok, normalize_metadata(nil, raw_tool_specs, tool_specs)}
    end
  end

  defp context_environment(context) do
    case Fields.fetch(context, Fields.tool_environment()) do
      {:ok, environment} -> Environment.normalize(environment)
      :error -> {:ok, %{}}
    end
  end

  defp context_tool_plan(context) do
    case Fields.fetch(context, Fields.tool_plan()) do
      {:ok, plan} -> ToolPlan.normalize(plan)
      :error -> {:ok, nil}
    end
  end

  defp context_runtime_metadata(context) do
    with {:ok, runtime_metadata} <- field_map(context, Fields.runtime_metadata(), RuntimeMetadata.empty()) do
      RuntimeMetadata.normalize(runtime_metadata)
    end
  end

  defp field_list(context, field, default) do
    case Fields.fetch(context, field) do
      {:ok, value} when is_list(value) -> {:ok, value}
      {:ok, nil} -> :error
      {:ok, _value} -> :error
      :error -> {:ok, default}
    end
  end

  defp field_map(context, field, default) do
    case Fields.fetch(context, field) do
      {:ok, value} when is_map(value) -> {:ok, value}
      {:ok, nil} -> :error
      {:ok, _value} -> :error
      :error -> {:ok, default}
    end
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_map), do: %{}

  defp non_empty_map?(value) when is_map(value), do: map_size(value) > 0
  defp non_empty_map?(_value), do: false

  defp explicit_metadata(metadata) when is_map(metadata), do: Metadata.from_metadata_map(metadata)
  defp explicit_metadata(_metadata), do: %{}

  defp tool_names(tool_specs) when is_list(tool_specs) do
    Enum.flat_map(tool_specs, fn
      %ToolSpec{name: name} when is_binary(name) -> [name]
      _tool_spec -> []
    end)
  end
end

defmodule SymphonyElixir.Agent.DynamicTool.Context.Capture do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.Context.Normalizer
  alias SymphonyElixir.Agent.DynamicTool.{Source, ToolSpec}

  @spec capture(keyword()) :: Context.t()
  def capture(opts \\ []) when is_list(opts) do
    case capture_strict(opts) do
      {:ok, context} -> context
      :error -> Context.empty()
    end
  end

  @spec capture_strict(keyword()) :: {:ok, Context.t()} | :error
  def capture_strict(opts \\ []) when is_list(opts) do
    source = Source.from_opts(opts)
    source_context = Keyword.get_lazy(opts, :dynamic_tool_source_context, fn -> Source.default_context(source, opts) end)
    raw_tool_specs = Source.tools(source, source_context, opts)

    case ToolSpec.normalize_many_strict(raw_tool_specs) do
      {:ok, tool_specs} ->
        context =
          %Context{
            source: source,
            source_context: Normalizer.normalize_source_context(source, source_context),
            source_kind: Source.kind(source, source_context),
            tool_specs: tool_specs,
            tool_metadata: Normalizer.normalize_metadata(nil, raw_tool_specs, tool_specs),
            tool_environment: Source.environment(source, source_context, opts)
          }
          |> Normalizer.put_adoption_settings(opts)

        {:ok, context}

      {:error, _errors} ->
        :error
    end
  rescue
    ArgumentError -> :error
  end
end

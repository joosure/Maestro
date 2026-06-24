defmodule SymphonyElixir.Agent.DynamicTool.Source.Config.SourceSpec do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Source

  @enforce_keys [:source]
  defstruct source: nil,
            source_context: nil,
            has_source_context?: false,
            source_kind: nil,
            tool_specs: nil

  @type t :: %__MODULE__{
          source: module(),
          source_context: term(),
          has_source_context?: boolean(),
          source_kind: String.t() | nil,
          tool_specs: [map()] | nil
        }

  @spec normalize!(module() | {module(), term()}, atom()) :: t()
  def normalize!(source, _config_key) when is_atom(source) and not is_nil(source) do
    %__MODULE__{source: Source.validate!(source)}
  end

  def normalize!({source, source_context}, _config_key) when is_atom(source) and not is_nil(source) do
    %__MODULE__{
      source: Source.validate!(source),
      source_context: source_context,
      has_source_context?: true
    }
  end

  def normalize!(source_spec, config_key) do
    raise ArgumentError,
          "invalid #{inspect(config_key)} entry: expected a source module or {source, context}, got #{inspect(source_spec)}"
  end

  @spec source_context(t(), keyword()) :: term()
  def source_context(%__MODULE__{has_source_context?: true, source_context: source_context}, _opts), do: source_context

  def source_context(%__MODULE__{source: source}, opts) when is_list(opts),
    do: Source.default_context(source, opts)

  @spec source_kind(t(), term()) :: String.t() | nil
  def source_kind(%__MODULE__{source_kind: source_kind}, _source_context) when is_binary(source_kind),
    do: source_kind

  def source_kind(%__MODULE__{source: source}, source_context), do: Source.kind(source, source_context)

  @spec tool_specs(t(), term(), keyword()) :: [map()]
  def tool_specs(%__MODULE__{tool_specs: tool_specs}, _source_context, _opts) when is_list(tool_specs),
    do: tool_specs

  def tool_specs(%__MODULE__{source: source}, source_context, opts) when is_list(opts),
    do: Source.tools(source, source_context, opts)
end

defmodule SymphonyElixir.Agent.DynamicTool.Bridge.Request do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.{Context, Policy, Source}

  defstruct provider_tool: nil,
            canonical_tool: nil,
            arguments: nil,
            opts: [],
            tool_context: nil,
            source: nil,
            source_context: nil,
            started_at_ms: nil,
            audit_fields: %{}

  @type t :: %__MODULE__{
          provider_tool: String.t() | nil,
          canonical_tool: String.t() | nil,
          arguments: term(),
          opts: keyword(),
          tool_context: Context.t() | nil,
          source: module() | nil,
          source_context: term(),
          started_at_ms: integer(),
          audit_fields: map()
        }

  @spec new(String.t() | nil, term(), keyword()) :: t()
  def new(tool, arguments, opts) when is_list(opts) do
    tool_context = Context.from_opts(opts)
    source = Context.source(tool_context)
    source_context = Context.source_context(tool_context)

    %__MODULE__{
      provider_tool: tool,
      canonical_tool: Source.canonical_tool(source, source_context, tool),
      arguments: arguments,
      opts: opts,
      tool_context: tool_context,
      source: source,
      source_context: source_context,
      started_at_ms: System.monotonic_time(:millisecond)
    }
  end

  @spec put_audit_fields(t(), map()) :: t()
  def put_audit_fields(%__MODULE__{} = request, fields) when is_map(fields) do
    %{request | audit_fields: fields}
  end

  @spec source_opts(t()) :: keyword()
  def source_opts(%__MODULE__{} = request) do
    request.opts
    |> Keyword.put(:tool_context, request.tool_context)
    |> Keyword.put(:provider_tool_name, request.provider_tool)
    |> Keyword.put(:canonical_tool_name, request.canonical_tool)
  end

  @spec policy_config(t()) :: {:ok, Policy.Config.t()} | {:error, Policy.Error.t()}
  def policy_config(%__MODULE__{opts: opts}), do: Policy.Config.from_opts(opts)

  @spec failure_policy_opts(t()) :: keyword()
  def failure_policy_opts(%__MODULE__{opts: opts}), do: opts
end

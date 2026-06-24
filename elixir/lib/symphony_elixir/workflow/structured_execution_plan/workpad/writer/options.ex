defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Options do
  @moduledoc """
  Runtime options for structured-plan Workpad writing.

  This module is the boundary for caller-provided writer options. Downstream
  writer modules consume this normalized struct instead of reading keyword opts
  directly.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract, as: RenderingContract

  @enforce_keys [:gates, :store_opts, :render_opts, :tracker_opts, :tracker_executor, :tracker_tool]
  defstruct [:gates, :store_opts, :render_opts, :tracker_opts, :tracker_executor, :tracker_tool]

  @type tracker_executor :: (String.t(), map(), keyword() -> {:success, term()} | {:failure, term()} | {:error, term()})

  @type t :: %__MODULE__{
          gates: map(),
          store_opts: keyword(),
          render_opts: keyword(),
          tracker_opts: keyword(),
          tracker_executor: tracker_executor() | nil,
          tracker_tool: String.t() | nil
        }

  @spec parse(keyword()) :: t()
  def parse(opts) when is_list(opts) do
    %__MODULE__{
      gates: Keyword.get(opts, :gates, Contract.gate_defaults()),
      store_opts: store_opts(opts),
      render_opts: render_opts(opts),
      tracker_opts: Keyword.get(opts, :tracker_opts, []),
      tracker_executor: Keyword.get(opts, :tracker_executor),
      tracker_tool: Keyword.get(opts, :tracker_tool)
    }
  end

  defp store_opts(opts) do
    case Keyword.get(opts, :server) || Keyword.get(opts, :structured_execution_plan_store) do
      nil -> []
      server -> [server: server]
    end
  end

  defp render_opts(opts) do
    [mode: RenderingContract.write_mode()]
    |> maybe_put_keyword(:heading, Keyword.get(opts, :heading))
    |> maybe_put_keyword(:max_items, Keyword.get(opts, :max_items))
  end

  defp maybe_put_keyword(opts, _key, nil), do: opts
  defp maybe_put_keyword(opts, key, value), do: Keyword.put(opts, key, value)
end

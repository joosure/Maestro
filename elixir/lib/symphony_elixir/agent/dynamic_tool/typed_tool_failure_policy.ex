defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy do
  @moduledoc """
  Public facade for typed-tool repeated-failure escalation.

  Domain-specific retry codes, resource identity extraction, and audit field
  enrichment are injected by adoption layers. The Agent Dynamic Tool core only
  owns counting, thresholding, and response normalization.
  """

  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.{Engine, ResourceIdentity, RetryPolicy, Server}

  @type result :: Engine.result()
  @type retry_policy :: RetryPolicy.t()
  @type resource_identity :: ResourceIdentity.t()

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: Server.start_link(opts)

  @spec apply(result(), Context.t(), String.t() | nil, term(), keyword()) :: result()
  def apply(result, tool_context, tool, arguments, opts) do
    Engine.apply(result, tool_context, tool, arguments, opts)
  end

  @spec reset() :: :ok
  def reset, do: Server.reset()
end

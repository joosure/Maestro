defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.State do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox

  @default_interval_ms 60_000
  @default_target_limit 100
  @default_enqueue_unchanged_after_ms 300_000

  defstruct enabled?: false,
            interval_ms: nil,
            target_limit: nil,
            enqueue_unchanged_after_ms: nil,
            registry_module: nil,
            registry: nil,
            inbox: Inbox,
            command_handler: nil,
            timer_ref: nil

  @type t :: %__MODULE__{}

  @spec from_opts(keyword()) :: t()
  def from_opts(opts) do
    registry_module = registry_module(opts)

    %__MODULE__{
      enabled?: Keyword.get(opts, :enabled?, Keyword.get(opts, :enabled, false)) == true,
      interval_ms: positive_integer(Keyword.get(opts, :interval_ms), @default_interval_ms),
      target_limit: positive_integer(Keyword.get(opts, :target_limit), @default_target_limit),
      enqueue_unchanged_after_ms:
        non_negative_integer(
          Keyword.get(opts, :enqueue_unchanged_after_ms),
          @default_enqueue_unchanged_after_ms
        ),
      registry_module: registry_module,
      registry: registry_server(opts, registry_module),
      inbox: Keyword.get(opts, :inbox, Inbox),
      command_handler: Keyword.get(opts, :command_handler)
    }
  end

  @spec to_opts(t()) :: keyword()
  def to_opts(%__MODULE__{} = state) do
    [
      registry: state.registry,
      registry_module: state.registry_module,
      inbox: state.inbox,
      command_handler: state.command_handler,
      target_limit: state.target_limit,
      enqueue_unchanged_after_ms: state.enqueue_unchanged_after_ms
    ]
  end

  @spec schedule_if_enabled(t()) :: t()
  def schedule_if_enabled(%__MODULE__{enabled?: false} = state), do: state

  def schedule_if_enabled(%__MODULE__{enabled?: true, interval_ms: interval_ms} = state) do
    timer_ref = Process.send_after(self(), :poll, interval_ms)
    %{state | timer_ref: timer_ref}
  end

  @spec registry_module(keyword()) :: module()
  def registry_module(opts) do
    case Keyword.get(opts, :registry_module) do
      module when is_atom(module) and not is_nil(module) -> module
      _module -> default_registry_module()
    end
  end

  @spec registry_server(keyword(), module()) :: GenServer.server()
  def registry_server(opts, registry_module) do
    case Keyword.get(opts, :registry) do
      nil -> registry_module
      server -> server
    end
  end

  @spec default_target_limit() :: pos_integer()
  def default_target_limit, do: @default_target_limit

  @spec default_enqueue_unchanged_after_ms() :: non_neg_integer()
  def default_enqueue_unchanged_after_ms, do: @default_enqueue_unchanged_after_ms

  defp default_registry_module, do: Module.safe_concat(KnownTarget, "Registry")

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default
end

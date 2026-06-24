defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.Registration do
  @moduledoc """
  Registers known change-proposal targets and schedules reconciliation work.

  This use case belongs to reconciliation because registration is more than a
  KnownTarget mutation: it also enqueues runtime candidates, emits producer
  diagnostics, and releases platform blocked-resource commands. The KnownTarget
  subdomain owns the entity/index/storage concerns only.
  """

  alias SymphonyElixir.Workflow.Extension.Runtime.Command, as: RuntimeCommand
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Clock, as: KnownTargetClock
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.Registration.{
    Commands,
    Events,
    Options
  }

  @type target :: KnownTarget.t()

  @type result :: %{
          required(:target) => target(),
          required(:enqueue) => Inbox.enqueue_result(),
          required(:commands) => [RuntimeCommand.t()]
        }

  @spec register(map(), keyword()) :: {:ok, result()} | {:error, term()}
  def register(attrs, opts \\ [])

  def register(attrs, opts) when is_map(attrs) do
    with {:ok, options} <- Options.normalize(opts),
         {:ok, now_ms} <- KnownTargetClock.now_ms(options.opts),
         registry_opts = Options.registry_opts(options, now_ms),
         inbox_opts = Options.inbox_opts(options),
         {:ok, target} <- KnownTarget.Registry.register(attrs, registry_opts),
         {:ok, enqueue_result} <- Inbox.enqueue_issue_ids([target.issue_id], inbox_opts),
         :ok <- Events.candidate_enqueue_dropped(target, enqueue_result, options),
         {:ok, target} <- maybe_mark_enqueued(target, enqueue_result, registry_opts),
         commands = Commands.release_blocked_issue_commands(target.issue_id, :known_target_updated),
         :ok <- Commands.execute(commands, options) do
      {:ok, %{target: target, enqueue: enqueue_result, commands: commands}}
    end
  end

  def register(attrs, _opts), do: {:error, Options.invalid_attrs(attrs)}

  @spec targets(keyword()) :: [KnownTarget.t()] | {:error, term()}
  def targets(opts \\ []) do
    KnownTarget.Registry.list_targets(opts)
  end

  defp maybe_mark_enqueued(target, enqueue_result, registry_opts) when is_map(enqueue_result) do
    accepted = Map.get(enqueue_result, :accepted_count, 0)
    duplicate = Map.get(enqueue_result, :duplicate_count, 0)

    if accepted + duplicate > 0 do
      KnownTarget.Registry.mark_enqueued(target.issue_id, registry_opts)
    else
      {:ok, target}
    end
  end
end

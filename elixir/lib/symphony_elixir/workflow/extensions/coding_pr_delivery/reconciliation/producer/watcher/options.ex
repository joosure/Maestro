defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.Options do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProducerDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Clock, as: KnownTargetClock
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config, as: ReconciliationConfig
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Config, as: ProducerConfig
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.State

  @spec merge_application_opts(term()) :: {:ok, keyword()} | {:error, map()}
  def merge_application_opts(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, app_opts} <- ProducerConfig.app_opts(ProducerConfig.known_target_watcher_key()) do
      {:ok, Keyword.merge(app_opts, opts)}
    else
      false -> {:error, Diagnostics.invalid_options(opts)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec context(keyword()) :: {:ok, map()} | {:error, map()} | :skip
  def context(opts) do
    case runtime_targeted_settings(opts) do
      {:ok, settings} ->
        registry_module = State.registry_module(opts)
        registry = State.registry_server(opts, registry_module)
        deps = deps(opts, settings)

        with :ok <- validate_fun(deps.command_handler, :command_handler, 1),
             :ok <- validate_fun(deps.enqueue_fn, :enqueue_issue_ids_fn, 2),
             :ok <- validate_fun(deps.facts_fn, :change_proposal_facts_fn, 3),
             :ok <- validate_fun(deps.emit_event_fn, :emit_event_fn, 3) do
          {:ok,
           Map.merge(deps, %{
             registry_module: registry_module,
             registry: registry,
             inbox: Keyword.get(opts, :inbox, Inbox),
             repo: Keyword.get(opts, :repo, settings.repo),
             provider_facts_opts: Keyword.get(opts, :provider_facts_opts, []),
             now_ms: Keyword.get_lazy(opts, :now_ms, &KnownTargetClock.system_time_ms/0),
             enqueue_unchanged_after_ms:
               non_negative_integer(
                 Keyword.get(opts, :enqueue_unchanged_after_ms),
                 State.default_enqueue_unchanged_after_ms()
               ),
             target_limit: positive_integer(Keyword.get(opts, :target_limit), State.default_target_limit())
           })}
        end

      :skip ->
        :skip
    end
  end

  defp deps(opts, _settings) do
    %{
      command_handler: Keyword.get(opts, :command_handler),
      enqueue_fn: Keyword.get(opts, :enqueue_issue_ids_fn, &Defaults.enqueue_issue_ids/2),
      facts_fn: Keyword.get(opts, :change_proposal_facts_fn, &Defaults.provider_facts/3),
      emit_event_fn: Keyword.get(opts, :emit_event_fn, &Defaults.emit_event/3)
    }
  end

  defp runtime_targeted_settings(opts) do
    with {:ok, settings} <- settings(opts),
         {:ok, %ReconciliationConfig{enabled?: true, candidate_discovery: :runtime_targeted}} <-
           ReconciliationConfig.from_settings(settings) do
      {:ok, settings}
    else
      _other -> :skip
    end
  end

  defp settings(opts) do
    case Keyword.fetch(opts, :settings) do
      {:ok, settings} when is_map(settings) -> {:ok, settings}
      _other -> Defaults.settings()
    end
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default

  defp validate_fun(fun, _name, arity) when is_function(fun, arity), do: :ok
  defp validate_fun(value, name, arity), do: {:error, Diagnostics.invalid_dependency(name, value, arity)}
end

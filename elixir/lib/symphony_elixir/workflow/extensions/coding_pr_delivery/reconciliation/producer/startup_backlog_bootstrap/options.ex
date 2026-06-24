defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.StartupBacklogBootstrap.Options do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProducerDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config, as: ReconciliationConfig
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Config, as: ProducerConfig
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics

  @spec merge_application_opts(term()) :: {:ok, keyword()} | {:error, map()}
  def merge_application_opts(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, app_opts} <- ProducerConfig.app_opts(ProducerConfig.startup_backlog_bootstrap_key()) do
      {:ok, Keyword.merge(app_opts, opts)}
    else
      false -> {:error, Diagnostics.invalid_options(opts)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts), do: Keyword.get(opts, :enabled?, Keyword.get(opts, :enabled, true)) == true

  @spec deps(keyword()) :: {:ok, map()} | {:error, map()}
  def deps(opts) do
    deps = %{
      settings_fn: Keyword.get(opts, :settings_fn, &Defaults.settings/0),
      config_fn: Keyword.get(opts, :config_fn, &ReconciliationConfig.from_settings/1),
      fetch_issues_fn: Keyword.get(opts, :fetch_issues_by_states_fn, &Defaults.fetch_issues_by_states/2),
      enqueue_fn: Keyword.get(opts, :enqueue_issue_ids_fn, &Defaults.enqueue_issue_ids/2),
      emit_event_fn: Keyword.get(opts, :emit_event_fn, &Defaults.emit_event/3),
      inbox: Keyword.get(opts, :inbox, Inbox)
    }

    with :ok <- validate_fun(deps.settings_fn, :settings_fn, 0),
         :ok <- validate_fun(deps.config_fn, :config_fn, 1),
         :ok <- validate_fun(deps.fetch_issues_fn, :fetch_issues_by_states_fn, 2),
         :ok <- validate_fun(deps.enqueue_fn, :enqueue_issue_ids_fn, 2),
         :ok <- validate_fun(deps.emit_event_fn, :emit_event_fn, 3) do
      {:ok, deps}
    end
  end

  defp validate_fun(fun, _name, arity) when is_function(fun, arity), do: :ok
  defp validate_fun(value, name, arity), do: {:error, Diagnostics.invalid_dependency(name, value, arity)}
end

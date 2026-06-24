defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Config do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics

  @known_target_watcher_key :coding_pr_delivery_known_target_watcher
  @startup_backlog_bootstrap_key :coding_pr_delivery_startup_backlog_bootstrap

  @spec known_target_watcher_key() :: atom()
  def known_target_watcher_key, do: @known_target_watcher_key

  @spec startup_backlog_bootstrap_key() :: atom()
  def startup_backlog_bootstrap_key, do: @startup_backlog_bootstrap_key

  @spec app_opts(atom()) :: {:ok, keyword()} | {:error, map()}
  def app_opts(key) when key in [@known_target_watcher_key, @startup_backlog_bootstrap_key] do
    value = Application.get_env(:symphony_elixir, key, [])

    if Keyword.keyword?(value) do
      {:ok, value}
    else
      {:error, Diagnostics.invalid_app_config(key, value)}
    end
  end
end

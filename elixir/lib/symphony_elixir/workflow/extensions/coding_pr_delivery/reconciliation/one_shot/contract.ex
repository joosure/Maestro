defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract do
  @moduledoc false

  @probe_fetch_before "fetch-before"
  @probe_fetch_after "fetch-after"
  @probe_config_validation "config-validation"
  @probe_known_target_registry "known-target-registry"
  @probe_options "options"
  @probe_targeted_reconcile "targeted-reconcile"
  @probe_workflow "workflow"

  @mode_dry_run "dry_run"
  @mode_invalid "invalid"
  @mode_state_write "state_write"

  @spec probe_id(
          :config_validation
          | :fetch_after
          | :fetch_before
          | :known_target_registry
          | :options
          | :targeted_reconcile
          | :workflow
        ) :: String.t()
  def probe_id(:fetch_before), do: @probe_fetch_before
  def probe_id(:fetch_after), do: @probe_fetch_after
  def probe_id(:config_validation), do: @probe_config_validation
  def probe_id(:known_target_registry), do: @probe_known_target_registry
  def probe_id(:options), do: @probe_options
  def probe_id(:targeted_reconcile), do: @probe_targeted_reconcile
  def probe_id(:workflow), do: @probe_workflow

  @spec mode(:dry_run | :invalid | :state_write) :: String.t()
  def mode(:dry_run), do: @mode_dry_run
  def mode(:invalid), do: @mode_invalid
  def mode(:state_write), do: @mode_state_write

  @spec mode_from_options(keyword()) :: String.t()
  def mode_from_options(opts) when is_list(opts) do
    if Keyword.get(opts, :confirm_state_write, false), do: @mode_state_write, else: @mode_dry_run
  end
end

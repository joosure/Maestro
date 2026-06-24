defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot do
  @moduledoc """
  Operator one-shot entrypoint for targeted change-proposal reconciliation.

  The runner never discovers candidates by scanning a source route. It processes
  only the explicit issue id supplied by the operator and uses dry-run mode
  unless tracker writes are explicitly confirmed.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.OneShotHostDeps, as: HostDeps
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Deps
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Report
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Runner

  @type deps :: Deps.t()
  @type probe_result :: Report.probe_result()
  @type report :: Report.t()

  @spec run(term(), term()) :: report()
  def run(opts, deps \\ runtime_deps()), do: Runner.run(opts, deps)

  @spec format_text(report()) :: String.t()
  defdelegate format_text(report), to: Report

  @spec to_map(report()) :: map()
  defdelegate to_map(report), to: Report

  @spec runtime_deps() :: deps()
  defdelegate runtime_deps(), to: HostDeps, as: :runtime
end

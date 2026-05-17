defmodule SymphonyElixir.Smoke.ResultStatus do
  @moduledoc """
  Shared status labels for smoke probes and machine-readable reports.
  """

  @passed "passed"
  @failed "failed"
  @ok "ok"
  @fail "fail"
  @pass_upper "PASS"
  @fail_upper "FAIL"
  @unknown "unknown"
  @none "none"

  @spec passed() :: String.t()
  def passed, do: @passed

  @spec failed() :: String.t()
  def failed, do: @failed

  @spec unknown() :: String.t()
  def unknown, do: @unknown

  @spec none() :: String.t()
  def none, do: @none

  @spec report_status(boolean()) :: String.t()
  def report_status(true), do: @passed
  def report_status(false), do: @failed

  @spec line_status(boolean()) :: String.t()
  def line_status(true), do: @ok
  def line_status(false), do: @fail

  @spec upper_probe_status(boolean()) :: String.t()
  def upper_probe_status(true), do: @pass_upper
  def upper_probe_status(false), do: @fail_upper
end

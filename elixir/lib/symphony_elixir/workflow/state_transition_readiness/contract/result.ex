defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Result do
  @moduledoc """
  Stable keys used in state-transition readiness result payloads.
  """

  @target_state_key "target_state"
  @capability_gaps_key "capability_gaps"
  @downgrades_key "downgrades"
  @error_code_key "error_code"
  @reason_code_key "reason_code"
  @reason_codes_key "reason_codes"
  @code_key "code"
  @detail_key "detail"

  @spec target_state_key() :: String.t()
  def target_state_key, do: @target_state_key

  @spec capability_gaps_key() :: String.t()
  def capability_gaps_key, do: @capability_gaps_key

  @spec downgrades_key() :: String.t()
  def downgrades_key, do: @downgrades_key

  @spec error_code_key() :: String.t()
  def error_code_key, do: @error_code_key

  @spec reason_code_key() :: String.t()
  def reason_code_key, do: @reason_code_key

  @spec reason_codes_key() :: String.t()
  def reason_codes_key, do: @reason_codes_key

  @spec code_key() :: String.t()
  def code_key, do: @code_key

  @spec detail_key() :: String.t()
  def detail_key, do: @detail_key
end

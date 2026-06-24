defmodule SymphonyElixir.Agent.DynamicTool.ErrorProjector.Contract do
  @moduledoc false

  @provider_key "provider"
  @operation_key "operation"
  @retryable_key "retryable"
  @details_key "details"
  @status_key "status"
  @path_key "path"
  @exit_code_key "exitCode"
  @value_key "value"

  @public_detail_keys [
    "actual",
    "allowedValues",
    "aliasOf",
    "baseBranch",
    "branch",
    "capability",
    "changeProposalId",
    "changeProposalUrl",
    "code",
    "expected",
    "field",
    "headBranch",
    "id",
    "kind",
    "message",
    "name",
    "operation",
    "option",
    "path",
    "provider",
    "remote",
    "retryable",
    "sourceKind",
    "state",
    "stateName",
    "status",
    "tool",
    "url",
    "value"
  ]

  @spec provider_key() :: String.t()
  def provider_key, do: @provider_key

  @spec operation_key() :: String.t()
  def operation_key, do: @operation_key

  @spec retryable_key() :: String.t()
  def retryable_key, do: @retryable_key

  @spec details_key() :: String.t()
  def details_key, do: @details_key

  @spec status_key() :: String.t()
  def status_key, do: @status_key

  @spec path_key() :: String.t()
  def path_key, do: @path_key

  @spec exit_code_key() :: String.t()
  def exit_code_key, do: @exit_code_key

  @spec value_key() :: String.t()
  def value_key, do: @value_key

  @spec public_detail_keys() :: [String.t()]
  def public_detail_keys, do: @public_detail_keys
end

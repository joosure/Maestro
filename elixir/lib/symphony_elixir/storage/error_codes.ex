defmodule SymphonyElixir.Storage.ErrorCodes do
  @moduledoc """
  Platform storage machine-code contract.

  Subsystem storage backends may add domain-specific context to messages, but
  shared physical-storage failure codes belong at the platform storage boundary.
  """

  @storage_error "storage_error"
  @unsupported_backend "unsupported_backend"
  @repo_unavailable "repo_unavailable"
  @migration_failed "migration_failed"
  @catalog_invalid "catalog_invalid"
  @backup_unavailable "backup_unavailable"
  @backup_failed "backup_failed"
  @retention_failed "retention_failed"
  @redaction_failed "redaction_failed"

  @spec storage_error() :: String.t()
  def storage_error, do: @storage_error

  @spec unsupported_backend() :: String.t()
  def unsupported_backend, do: @unsupported_backend

  @spec repo_unavailable() :: String.t()
  def repo_unavailable, do: @repo_unavailable

  @spec migration_failed() :: String.t()
  def migration_failed, do: @migration_failed

  @spec catalog_invalid() :: String.t()
  def catalog_invalid, do: @catalog_invalid

  @spec backup_unavailable() :: String.t()
  def backup_unavailable, do: @backup_unavailable

  @spec backup_failed() :: String.t()
  def backup_failed, do: @backup_failed

  @spec retention_failed() :: String.t()
  def retention_failed, do: @retention_failed

  @spec redaction_failed() :: String.t()
  def redaction_failed, do: @redaction_failed
end

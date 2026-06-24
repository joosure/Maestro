defmodule SymphonyElixir.Storage.ErrorCodeBoundaryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Storage.ErrorCodes

  @runtime_files [
    "lib/symphony_elixir/agent/execution_plan/storage/sqlite_backend.ex",
    "lib/symphony_elixir/workflow/structured_execution_plan/storage/sqlite_backend.ex"
  ]

  test "storage runtime modules read machine codes through platform storage contract" do
    offenders =
      for file <- @runtime_files,
          source = File.read!(file),
          direct_code_literal?(source, ErrorCodes.storage_error()) do
        file
      end

    assert offenders == [],
           "storage runtime modules must use Storage.ErrorCodes for machine codes; offenders:\n#{format_offenders(offenders)}"
  end

  test "storage error code contract is stable" do
    assert ErrorCodes.storage_error() == "storage_error"
    assert ErrorCodes.unsupported_backend() == "unsupported_backend"
    assert ErrorCodes.repo_unavailable() == "repo_unavailable"
    assert ErrorCodes.migration_failed() == "migration_failed"
    assert ErrorCodes.catalog_invalid() == "catalog_invalid"
    assert ErrorCodes.backup_unavailable() == "backup_unavailable"
    assert ErrorCodes.backup_failed() == "backup_failed"
    assert ErrorCodes.retention_failed() == "retention_failed"
    assert ErrorCodes.redaction_failed() == "redaction_failed"
  end

  defp direct_code_literal?(source, code) do
    Regex.match?(~r/"#{Regex.escape(code)}"/, source)
  end

  defp format_offenders([]), do: "(none)"

  defp format_offenders(offenders) do
    offenders
    |> Enum.map_join("\n", &"- #{&1}")
  end
end

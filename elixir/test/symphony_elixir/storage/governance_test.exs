defmodule SymphonyElixir.Storage.GovernanceTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Storage.{Backup, ErrorCodes, Redaction, Retention}

  test "backup boundary fails closed when no backend is configured" do
    assert {:error,
            %{
              code: code,
              reason: :backup_backend_not_configured
            }} = Backup.create()

    assert code == ErrorCodes.backup_unavailable()
  end

  test "retention boundary defaults to a no-op policy result" do
    assert {:ok, %{deleted_count: 0, policies: []}} = Retention.prune()
  end

  test "redaction boundary recursively removes common secrets" do
    payload = %{
      "token" => "tok-123",
      password: "pw-123",
      nested: [
        %{"api_key" => "key-123", "safe" => "value"},
        {:authorization, "Bearer secret"}
      ]
    }

    assert Redaction.redact(payload) == %{
             "token" => "[REDACTED]",
             password: "[REDACTED]",
             nested: [
               %{"api_key" => "[REDACTED]", "safe" => "value"},
               {:authorization, "[REDACTED]"}
             ]
           }
  end

  test "redaction boundary scrubs secret-like strings in non-secret fields" do
    payload = %{
      note: "Authorization: Bearer bearer-secret token=ghp_secret123",
      nested: %{
        "message" => "LINEAR_API_KEY=lin-secret safe=value"
      }
    }

    redacted = Redaction.redact(payload)

    assert redacted.note =~ "Authorization: [REDACTED]"
    assert redacted.note =~ "token=[REDACTED]"
    assert redacted.nested["message"] =~ "LINEAR_API_KEY=[REDACTED]"
    refute inspect(redacted) =~ "bearer-secret"
    refute inspect(redacted) =~ "ghp_secret123"
    refute inspect(redacted) =~ "lin-secret"
  end

  test "redaction boundary preserves structs" do
    payload = %URI{scheme: "https", host: "example.test", query: "token=visible"}

    assert %URI{} = redacted = Redaction.redact(payload)
    assert redacted.scheme == "https"
    assert redacted.query == "token=[REDACTED]"
  end

  test "governance boundaries can delegate to explicit backends" do
    assert {:ok, %{backend: :test_backup}} = Backup.create(backend: __MODULE__.BackupBackend)
    assert {:ok, %{deleted_count: 2}} = Retention.prune(backend: __MODULE__.RetentionBackend)
    assert Redaction.redact(%{value: "plain"}, backend: __MODULE__.RedactionBackend) == :redacted_by_test
  end

  test "governance boundaries reject invalid backends with stable errors" do
    assert {:error, %{code: code, reason: :backend_not_loaded}} = Backup.create(backend: Missing.BackupBackend)
    assert code == ErrorCodes.unsupported_backend()

    assert {:error, %{code: ^code, reason: :backend_behaviour_missing}} =
             Retention.prune(backend: __MODULE__.MissingBehaviourBackend)

    assert {:error, %{code: ^code, reason: :backend_callback_missing}} =
             Redaction.redact(%{}, backend: __MODULE__.MissingCallbackBackend)
  end

  defmodule BackupBackend do
    @moduledoc false

    @behaviour Backup

    @impl true
    def create(_opts), do: {:ok, %{backend: :test_backup}}
  end

  defmodule RetentionBackend do
    @moduledoc false

    @behaviour Retention

    @impl true
    def prune(_opts), do: {:ok, %{deleted_count: 2}}
  end

  defmodule RedactionBackend do
    @moduledoc false

    @behaviour Redaction

    @impl true
    def redact(_value, _opts), do: :redacted_by_test
  end

  defmodule MissingBehaviourBackend do
    @moduledoc false

    def prune(_opts), do: {:ok, %{}}
  end

  defmodule MissingCallbackBackend do
    @moduledoc false
  end
end

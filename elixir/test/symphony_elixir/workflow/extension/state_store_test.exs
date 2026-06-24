defmodule SymphonyElixir.Workflow.Extension.StateStoreTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Workflow.Extension.Canonical
  alias SymphonyElixir.Workflow.Extension.{ErrorCodes, StateStore}
  alias SymphonyElixir.Workflow.Extension.StateStore.MemoryBackend
  alias SymphonyElixir.Workflow.Extension.StateStore.Record, as: StateStoreRecord

  setup do
    :ok = MemoryBackend.reset([])
    previous_config = Application.get_env(:symphony_elixir, :workflow_extension_state_store, :unset)

    on_exit(fn ->
      case previous_config do
        :unset -> Application.delete_env(:symphony_elixir, :workflow_extension_state_store)
        config -> Application.put_env(:symphony_elixir, :workflow_extension_state_store, config)
      end
    end)

    :ok
  end

  test "state records normalize identity without exposing storage details" do
    attrs = state_attrs("issue-1")

    assert {:ok, record} = StateStoreRecord.new(attrs)
    assert record.extension_id == "symphony.workflow.extension.coding_pr_delivery"
    assert record.state_type == "change_proposal.known_target.v1"
    assert record.state_key == "issue-1"
    assert record.payload == %{"url" => "https://example.test/pull/1"}

    assert {:ok, scope_key} = StateStoreRecord.scope_key(%{profile_kind: "coding_pr_delivery", route_key: "developing"})

    assert {:ok, ^scope_key} =
             StateStoreRecord.scope_key(%{"profile_kind" => "coding_pr_delivery", "route_key" => "developing"})

    assert {:ok, record_scope_key} = StateStoreRecord.scope_key(record.workflow_scope)
    assert {:ok, ^record_scope_key} = Canonical.state_store_scope_key(record.workflow_scope)
  end

  test "state records normalize supported external field names from the field contract" do
    attrs = Map.put(state_attrs("issue-fields"), :expires_at_ms, 123)
    %StateStoreRecord{} = record = StateStoreRecord.new!(attrs)
    inserted_at = DateTime.utc_now()
    updated_at = DateTime.add(inserted_at, 1, :second)

    external_attrs = %{
      "id" => record.id,
      "extension_id" => record.extension_id,
      "extension_version" => record.extension_version,
      "workflow_scope" => record.workflow_scope,
      "workflow_scope_key" => record.workflow_scope_key,
      "state_type" => record.state_type,
      "state_key" => record.state_key,
      "payload_schema" => record.payload_schema,
      "payload_json" => record.payload,
      "expires_at_ms" => record.expires_at_ms,
      "inserted_at" => inserted_at,
      "updated_at" => updated_at
    }

    assert StateStoreRecord.external_field_names() == Enum.map(StateStoreRecord.input_keys(), &Atom.to_string/1)

    assert {:ok, normalized_record} = StateStoreRecord.new(external_attrs)
    assert normalized_record == %StateStoreRecord{record | inserted_at: inserted_at, updated_at: updated_at}
    refute :payload_json in StateStoreRecord.record_fields()
  end

  test "memory backend stores, lists, and deletes opaque extension payloads" do
    attrs = state_attrs("issue-2")

    assert {:ok, record} = StateStore.put(attrs, backend: MemoryBackend)

    assert {:ok, ^record} =
             StateStore.get(
               record.extension_id,
               record.workflow_scope,
               record.state_type,
               record.state_key,
               backend: MemoryBackend
             )

    assert {:ok, [^record]} =
             StateStore.list(record.extension_id, record.workflow_scope, record.state_type, backend: MemoryBackend)

    assert :ok =
             StateStore.delete(record.extension_id, record.workflow_scope, record.state_type, record.state_key, backend: MemoryBackend)

    assert {:ok, nil} =
             StateStore.get(record.extension_id, record.workflow_scope, record.state_type, record.state_key, backend: MemoryBackend)
  end

  test "expired records are hidden unless explicitly requested" do
    attrs = Map.put(state_attrs("issue-expired"), :expires_at_ms, 100)

    assert {:ok, record} = StateStore.put(attrs, backend: MemoryBackend)

    assert {:ok, nil} =
             StateStore.get(record.extension_id, record.workflow_scope, record.state_type, record.state_key,
               backend: MemoryBackend,
               now_ms: 100
             )

    assert {:ok, ^record} =
             StateStore.get(record.extension_id, record.workflow_scope, record.state_type, record.state_key,
               backend: MemoryBackend,
               now_ms: 100,
               include_expired?: true
             )
  end

  test "state store facade fails closed on invalid opts shape" do
    assert {:error, %{code: code, reason: :opts_not_keyword, value_type: :map}} =
             StateStore.put(state_attrs("issue-invalid-opts"), %{backend: MemoryBackend})

    assert code == ErrorCodes.state_store_error()

    assert {:error, %{code: ^code, reason: :opts_not_keyword, value_type: :list}} =
             StateStore.list(
               "symphony.workflow.extension.coding_pr_delivery",
               %{},
               "change_proposal.known_target.v1",
               [{"backend", MemoryBackend}]
             )
  end

  test "state store app config fails closed on invalid shape" do
    Application.put_env(:symphony_elixir, :workflow_extension_state_store, %{backend: MemoryBackend})

    assert {:error, %{code: code, reason: :configured_state_store_not_keyword, value_type: :map}} =
             StateStore.put(state_attrs("issue-invalid-config"))

    assert code == ErrorCodes.state_store_error()

    Application.put_env(:symphony_elixir, :workflow_extension_state_store, backend: MemoryBackend, unknown: true)

    assert {:error, %{code: ^code, reason: {:unsupported_config_keys, [:unknown]}, value_type: :list}} =
             StateStore.put(state_attrs("issue-unknown-config"))
  end

  test "record validation fails closed on unsupported fields" do
    assert {:error, %{code: code, reason: :unknown_fields}} =
             StateStoreRecord.new(Map.put(state_attrs("issue-bad"), :sql_fragment, "select 1"))

    assert code == ErrorCodes.invalid_state_record()

    assert {:error, %{code: ^code, reason: :unknown_fields}} =
             StateStoreRecord.new(Map.put(state_attrs("issue-bad-string"), "sql_fragment", "select 1"))
  end

  test "record validation rejects non JSON-compatible payloads" do
    assert {:error, %{code: code, reason: {:invalid_json_value, :payload}} = payload_error} =
             StateStoreRecord.new(put_in(state_attrs("issue-tuple")[:payload]["tuple"], {:not, "json"}))

    assert code == ErrorCodes.invalid_state_record()
    assert payload_error.value_type == :map
    refute Map.has_key?(payload_error, :value)

    assert {:error, %{reason: {:invalid_json_value, :payload}, value_type: :map} = atom_key_error} =
             StateStoreRecord.new(%{state_attrs("issue-atom-key") | payload: %{url: "https://example.test/pull/1"}})

    refute Map.has_key?(atom_key_error, :value)

    assert {:error, %{reason: {:invalid_json_value, :workflow_scope}, value_type: :map} = scope_error} =
             StateStoreRecord.new(put_in(state_attrs("issue-scope")[:workflow_scope][:bad], {:not, "json"}))

    refute Map.has_key?(scope_error, :value)
  end

  defp state_attrs(issue_id) do
    %{
      extension_id: "symphony.workflow.extension.coding_pr_delivery",
      extension_version: "builtin",
      workflow_scope: %{
        profile_kind: "coding_pr_delivery",
        profile_version: 1,
        route_key: "developing"
      },
      state_type: "change_proposal.known_target.v1",
      state_key: issue_id,
      payload_schema: "change_proposal.known_target.v1",
      payload: %{"url" => "https://example.test/pull/1"}
    }
  end
end

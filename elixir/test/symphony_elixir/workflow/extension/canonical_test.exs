defmodule SymphonyElixir.Workflow.Extension.CanonicalTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extension.Canonical
  alias SymphonyElixir.Workflow.Extension.ErrorCodes

  test "runtime config hash is versioned and deterministic for identity-compatible config" do
    assert Canonical.runtime_config_hash_codec() == "workflow.extension.runtime_config_hash.v1"

    config = %{
      profile: %{kind: "coding_pr_delivery", version: 1},
      policy_by_route_key: %{merging: %{action: :dispatch, execution_profile: "land"}}
    }

    assert {:ok, hash} = Canonical.runtime_config_hash(config)
    assert {:ok, ^hash} = Canonical.runtime_config_hash(config)
    assert byte_size(hash) == 64
  end

  test "runtime config hash rejects runtime-only terms" do
    code = ErrorCodes.invalid_canonical_identity()

    assert {:error,
            %{
              code: ^code,
              codec: "workflow.extension.runtime_config_hash.v1",
              reason: :unsupported_runtime_config_value,
              value_type: :pid
            }} = Canonical.runtime_config_hash(%{runtime_pid: self()})

    assert {:error, %{reason: :unsupported_runtime_config_value, value_type: :function}} =
             Canonical.runtime_config_hash(%{callback: fn -> :ok end})

    assert {:error, %{reason: :unsupported_runtime_config_value, value_type: :tuple}} =
             Canonical.runtime_config_hash(%{tuple: {:not, "durable"}})
  end

  test "state-store scope key is versioned and normalizes atom and string keys" do
    assert Canonical.state_store_scope_key_codec() == "workflow.extension.state_store_scope_key.v1"

    assert {:ok, scope_key} =
             Canonical.state_store_scope_key(%{profile_kind: "coding_pr_delivery", profile_version: 1})

    assert {:ok, ^scope_key} =
             Canonical.state_store_scope_key(%{"profile_kind" => "coding_pr_delivery", "profile_version" => 1})

    assert byte_size(scope_key) == 64
  end

  test "state-store scope key rejects non-json scope values and keys" do
    assert {:error,
            %{
              codec: "workflow.extension.state_store_scope_key.v1",
              reason: :unsupported_state_store_scope_value,
              value_type: :atom
            }} = Canonical.state_store_scope_key(%{"profile_kind" => :coding_pr_delivery})

    assert {:error,
            %{
              codec: "workflow.extension.state_store_scope_key.v1",
              reason: :unsupported_state_store_scope_key,
              value_type: :tuple
            }} = Canonical.state_store_scope_key(%{{:bad, "key"} => "value"})
  end
end

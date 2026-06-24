defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.RegistryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry

  defmodule DeleteFailingBackend do
    @behaviour SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage
    @behaviour SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.AdminBackend

    @impl true
    def load(_opts), do: {:ok, []}

    @impl true
    def put(%KnownTarget{}, _opts), do: :ok

    @impl true
    def put_many(_targets, _opts), do: :ok

    @impl true
    def delete(_issue_id, _opts), do: {:error, %{"code" => "known_target_delete_failed"}}

    @impl true
    def reset(_opts), do: :ok
  end

  test "public functions reject non-keyword options with bounded diagnostics" do
    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_registry_options",
              reason: :opts_not_keyword,
              value_type: "list"
            }} = Registry.register(valid_attrs("issue-invalid-opts"), [{"server", self()}])

    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_registry_options",
              reason: :opts_not_keyword,
              value_type: "list"
            }} = Registry.list_targets([{"limit", 1}])
  end

  test "startup rejects invalid storage backend instead of falling back to memory" do
    assert {:error,
            {:known_target_registry_invalid_options,
             %{
               code: "invalid_coding_pr_delivery_known_target_registry_storage_backend",
               reason: :invalid_storage_backend,
               value_type: "string"
             }}} =
             Registry.start_link(
               name: nil,
               workflow_scope: workflow_scope("invalid-backend"),
               storage_backend: "not-a-backend"
             )
  end

  test "ttl prune reports storage delete failures without dropping in-memory state" do
    registry =
      start_supervised!({Registry, name: nil, workflow_scope: workflow_scope("ttl-delete-failure"), storage_backend: DeleteFailingBackend, target_ttl_ms: 10})

    assert {:ok, %KnownTarget{}} =
             Registry.register(valid_attrs("issue-expired"), server: registry, now_ms: 1)

    assert {:error,
            %{
              code: "coding_pr_delivery_known_target_registry_storage_delete_failed",
              reason: {:storage_delete_failed, :ttl_prune},
              storage_reason_type: "map",
              storage_error_code: "known_target_delete_failed"
            }} = Registry.get("issue-expired", server: registry, now_ms: 11)

    assert %KnownTarget{issue_id: "issue-expired"} = Registry.get("issue-expired", server: registry, now_ms: 1)
  end

  test "target-limit eviction reports storage delete failures" do
    registry =
      start_supervised!({Registry, name: nil, workflow_scope: workflow_scope("limit-delete-failure"), storage_backend: DeleteFailingBackend, max_targets: 1})

    assert {:ok, %KnownTarget{}} =
             Registry.register(valid_attrs("issue-kept"), server: registry, now_ms: 1)

    assert {:error,
            %{
              code: "coding_pr_delivery_known_target_registry_storage_delete_failed",
              reason: {:storage_delete_failed, :max_target_evict},
              storage_reason_type: "map",
              storage_error_code: "known_target_delete_failed"
            }} = Registry.register(valid_attrs("issue-rejected"), server: registry, now_ms: 2)

    assert [%KnownTarget{issue_id: "issue-kept"}] = Registry.list_targets(server: registry)
  end

  defp valid_attrs(issue_id) do
    %{
      Fields.issue_id() => issue_id,
      Fields.number() => "42",
      Fields.repository() => "acme/widgets"
    }
  end

  defp workflow_scope(label), do: %{"test" => label}
end

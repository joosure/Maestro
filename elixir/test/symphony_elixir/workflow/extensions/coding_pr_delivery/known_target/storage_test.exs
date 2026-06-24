defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.StorageTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.Admin
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Storage.AdminBackend

  defmodule ValidBackend do
    @behaviour Storage
    @behaviour AdminBackend

    @impl true
    def load(_opts), do: {:ok, []}

    @impl true
    def put(%KnownTarget{}, _opts), do: :ok

    @impl true
    def put_many(_targets, _opts), do: :ok

    @impl true
    def delete(_issue_id, _opts), do: :ok

    @impl true
    def reset(_opts), do: :ok
  end

  defmodule IncompleteBackend do
    def load(_opts), do: {:ok, []}
  end

  test "facade rejects non-module backend values with bounded diagnostics" do
    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_storage_backend",
              reason: :backend_not_module,
              value_type: "string"
            }} = Storage.load(backend: "not-a-module")
  end

  test "facade rejects unloaded backend modules with bounded diagnostics" do
    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_storage_backend",
              reason: :backend_not_loaded,
              value_type: "atom"
            }} = Storage.load(backend: __MODULE__.MissingBackend)
  end

  test "facade rejects backend modules that do not implement the storage contract" do
    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_storage_backend_contract",
              reason: :missing_storage_backend_callbacks,
              backend_module: backend_module,
              missing_callbacks: missing_callbacks
            }} = Storage.load(backend: IncompleteBackend)

    assert backend_module == inspect(IncompleteBackend)
    assert "put/2" in missing_callbacks
    assert "put_many/2" in missing_callbacks
    assert "delete/2" in missing_callbacks
    refute "reset/1" in missing_callbacks
  end

  test "storage admin rejects backend modules that do not implement admin reset" do
    assert {:error,
            %{
              code: "invalid_coding_pr_delivery_known_target_storage_backend_contract",
              reason: :missing_storage_backend_callbacks,
              backend_module: backend_module,
              missing_callbacks: missing_callbacks
            }} = Admin.reset(backend: IncompleteBackend)

    assert backend_module == inspect(IncompleteBackend)
    assert "reset/1" in missing_callbacks
  end

  test "facade delegates ordinary operations through a validated backend" do
    {:ok, target} =
      KnownTarget.new(%{
        Fields.issue_id() => "issue-storage",
        Fields.number() => "42",
        Fields.repository() => "acme/widgets"
      })

    assert {:ok, []} = Storage.load(backend: ValidBackend)
    assert :ok = Storage.put(target, backend: ValidBackend)
    assert :ok = Storage.put_many([target], backend: ValidBackend)
    assert :ok = Storage.delete("issue-storage", backend: ValidBackend)
  end

  test "destructive reset is exposed through the storage admin boundary" do
    assert :ok = Admin.reset(backend: ValidBackend)
  end
end

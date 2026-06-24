defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceStoreTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceStore

  defmodule FakeBackend do
    @behaviour EvidenceStore

    @impl true
    def snapshot(keys, opts), do: %{"observations" => %{"keys" => keys, "tag" => Keyword.get(opts, :tag)}}

    @impl true
    def record(keys, evidence, opts) do
      send(self(), {:recorded_evidence, keys, evidence, opts})
      :ok
    end

    @impl true
    def scope_issue_keys(run_id, issue_keys, opts), do: ["#{run_id}:#{inspect(issue_keys)}:#{Keyword.get(opts, :tag)}"]
  end

  defmodule RaisingBackend do
    @behaviour EvidenceStore

    @impl true
    def snapshot(_keys, _opts), do: raise("backend failed")

    @impl true
    def record(_keys, _evidence, _opts), do: raise("backend failed")

    @impl true
    def scope_issue_keys(_run_id, _issue_keys, _opts), do: raise("backend failed")
  end

  test "delegates through backend opts" do
    opts = [readiness_evidence_store_backend: FakeBackend, readiness_evidence_store_opts: [tag: "demo"]]

    assert EvidenceStore.snapshot(["issue-1"], opts) == %{"observations" => %{"keys" => ["issue-1"], "tag" => "demo"}}
    assert EvidenceStore.scope_issue_keys("run-1", ["issue-1"], opts) == ["run-1:[\"issue-1\"]:demo"]
    assert :ok = EvidenceStore.record(["issue-1"], %{"observations" => %{}}, opts)
    assert_received {:recorded_evidence, ["issue-1"], %{"observations" => %{}}, [tag: "demo"]}
  end

  test "fails closed on invalid opts and backend failures" do
    test_pid = self()
    emit_event_fn = fn level, event, fields -> send(test_pid, {:evidence_store_event, level, event, fields}) end

    invalid_opts = [emit_event_fn: emit_event_fn] ++ [:not_keyword]

    assert EvidenceStore.snapshot("issue-1", invalid_opts) == %{
             "declarations" => %{},
             "metadata" => %{},
             "observations" => %{}
           }

    assert EvidenceStore.scope_issue_keys("run-1", "issue-1", invalid_opts) == []
    assert :ok = EvidenceStore.record("issue-1", %{"observations" => %{}}, invalid_opts)

    opts = [readiness_evidence_store_backend: RaisingBackend, emit_event_fn: emit_event_fn]

    assert EvidenceStore.snapshot("issue-1", opts) == %{"declarations" => %{}, "metadata" => %{}, "observations" => %{}}
    assert EvidenceStore.scope_issue_keys("run-1", "issue-1", opts) == []
    assert :ok = EvidenceStore.record("issue-1", %{"observations" => %{}}, opts)

    assert_received {:evidence_store_event, :warning, :coding_pr_delivery_readiness_evidence_store_error,
                     %{
                       component: "workflow.extensions.coding_pr_delivery.readiness.evidence_store",
                       error_code: "coding_pr_delivery_readiness_evidence_store_error",
                       operation: "snapshot",
                       payload_summary: %{reason: :backend_failed, kind: :error, exception: _exception}
                     } = event}

    refute inspect(event) =~ "backend failed"
  end
end

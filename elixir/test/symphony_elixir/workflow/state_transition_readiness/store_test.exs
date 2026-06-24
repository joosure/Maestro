defmodule SymphonyElixir.Workflow.StateTransitionReadiness.StoreTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Store

  setup do
    unless Process.whereis(Store), do: start_supervised!(Store)
    if Process.whereis(Store), do: Store.reset()
    :ok
  end

  test "snapshots use a policy-neutral evidence envelope" do
    snapshot = Store.snapshot("DEMO-18")

    assert snapshot == %{
             "observations" => %{},
             "declarations" => %{},
             "metadata" => %{}
           }

    refute Map.has_key?(snapshot, "schema")
    refute Map.has_key?(snapshot, "policy_id")
  end

  test "record replaces an observation group so stale fields do not persist" do
    Store.record("DEMO-18", %{
      "observations" => %{
        "checks" => %{
          "status" => "passed",
          "source" => "repo_provider_observed",
          "head_sha" => "old-head"
        }
      }
    })

    Store.record("DEMO-18", %{
      "observations" => %{
        "checks" => %{
          "status" => "not_required",
          "source" => "repo_provider_observed"
        }
      }
    })

    assert get_in(Store.snapshot("DEMO-18"), ["observations", "checks"]) == %{
             "status" => "not_required",
             "source" => "repo_provider_observed"
           }
  end

  test "record keeps unrelated observation groups while replacing the touched group" do
    Store.record("DEMO-18", %{
      "observations" => %{
        "repo" => %{"head_sha" => "head-1"},
        "checks" => %{"status" => "passed", "head_sha" => "head-1"}
      }
    })

    Store.record("DEMO-18", %{
      "observations" => %{
        "checks" => %{"status" => "not_required"}
      }
    })

    snapshot = Store.snapshot("DEMO-18")

    assert get_in(snapshot, ["observations", "repo", "head_sha"]) == "head-1"
    assert get_in(snapshot, ["observations", "checks"]) == %{"status" => "not_required"}
  end
end

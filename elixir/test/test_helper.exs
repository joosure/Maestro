ExUnit.start()
Code.require_file("support/snapshot_support.exs", __DIR__)
Code.require_file("support/test_support.exs", __DIR__)
Code.require_file("support/repo_provider_adapter_contract.ex", __DIR__)
Code.require_file("support/tracker_adapter_contract.ex", __DIR__)
Code.require_file("support/workflow_profile_contract.ex", __DIR__)

# Define Mox mocks for Behaviour-based contracts.
# Usage: `Mox.expect(SymphonyElixir.MockTrackerAdapter, :kind, fn -> "test" end)`
Mox.defmock(SymphonyElixir.MockTrackerAdapter, for: SymphonyElixir.Tracker.Adapter)

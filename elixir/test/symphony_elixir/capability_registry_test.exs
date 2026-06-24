defmodule SymphonyElixir.CapabilityRegistryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.Capabilities, as: AgentCapabilities
  alias SymphonyElixir.AssemblyCatalog.CapabilitySources
  alias SymphonyElixir.Capability.Registry
  alias SymphonyElixir.Repo.Capabilities, as: RepoCapabilities
  alias SymphonyElixir.RepoProvider.Capabilities, as: RepoProviderCapabilities
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities
  alias SymphonyElixir.Workflow.CapabilityNames, as: WorkflowCapabilities

  test "uses configured assembly catalogs for built-in capability sources" do
    assert Registry.sources(catalogs: [CapabilitySources]) == CapabilitySources.source_modules()
  end

  test "built-in catalog entries implement capability source contract" do
    for source <- CapabilitySources.source_modules() do
      assert Code.ensure_loaded?(source)
      assert function_exported?(source, :capabilities, 0)
    end
  end

  test "aggregates domain-owned capability sources" do
    assert TrackerCapabilities.attach_external_reference() in Registry.typed_tool_capabilities()
    assert RepoCapabilities.commit() in Registry.typed_tool_capabilities()
    assert RepoProviderCapabilities.create_or_update_change_proposal() in Registry.typed_tool_capabilities()
    assert AgentCapabilities.execution_plan_snapshot() in Registry.typed_tool_capabilities()
    assert WorkflowCapabilities.workflow_plan_snapshot() in Registry.typed_tool_capabilities()
  end

  test "keeps repo-provider merge gate capabilities source-owned" do
    assert Registry.merge_gate_capability?(RepoProviderCapabilities.merge())
    assert Registry.merge_gate_capability?(RepoProviderCapabilities.merge_change_proposal())
    refute Registry.merge_gate_capability?(RepoCapabilities.push())
  end

  test "classifies known provider unavailable capabilities through source contributions" do
    assert Registry.known_provider_unavailable_capability?(RepoProviderCapabilities.submit_change_proposal_review())
    refute Registry.known_provider_unavailable_capability?(RepoProviderCapabilities.merge_change_proposal())
  end

  defmodule CustomSource do
    @behaviour SymphonyElixir.Capability.Source

    @impl true
    def capabilities, do: ["custom.capability"]

    @impl true
    def typed_tool_capabilities, do: ["custom.capability"]
  end

  defmodule CustomCatalog do
    @behaviour SymphonyElixir.Capability.SourceCatalog

    @impl true
    def source_modules, do: [CustomSource]
  end

  test "supports explicit source overrides for assembly and tests" do
    assert Registry.capabilities(sources: [CustomSource]) == ["custom.capability"]
    assert Registry.typed_tool_capability?("custom.capability", sources: [CustomSource])
    refute Registry.typed_tool_capability?(TrackerCapabilities.issue_snapshot(), sources: [CustomSource])
  end

  test "supports explicit catalog overrides for assembly and tests" do
    assert Registry.capabilities(catalogs: [CustomCatalog]) == ["custom.capability"]
    assert Registry.typed_tool_capability?("custom.capability", catalogs: [CustomCatalog])
    refute Registry.typed_tool_capability?(TrackerCapabilities.issue_snapshot(), catalogs: [CustomCatalog])
  end

  defmodule NonListCatalog do
    @behaviour SymphonyElixir.Capability.SourceCatalog

    @impl true
    def source_modules, do: CustomSource
  end

  test "fails closed when a source catalog returns a non-list" do
    assert_raise ArgumentError, ~r/source_modules\/0 must return a list/, fn ->
      Registry.capabilities(catalogs: [NonListCatalog])
    end
  end

  defmodule NonListSource do
    @behaviour SymphonyElixir.Capability.Source

    @impl true
    def capabilities, do: "custom.capability"
  end

  test "fails closed when a source callback returns a non-list" do
    assert_raise ArgumentError, ~r/must return a list/, fn ->
      Registry.capabilities(sources: [NonListSource])
    end
  end

  defmodule InvalidCapabilitySource do
    @behaviour SymphonyElixir.Capability.Source

    @impl true
    def capabilities, do: ["custom.capability", :not_a_capability]
  end

  test "fails closed when a source returns invalid capability values" do
    assert_raise ArgumentError, ~r/returned invalid capability/, fn ->
      Registry.capabilities(sources: [InvalidCapabilitySource])
    end
  end
end

defmodule SymphonyElixir.Agent.ExecutionPlan.SchemaTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Schema, as: SchemaErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Record
  alias SymphonyElixir.Agent.ExecutionPlan.Schema

  test "valid generic execution plan does not require workflow fields" do
    plan = minimal_plan()

    assert ExecutionPlan.schema_id() == "agent.execution_plan.v1"
    assert {:ok, ^plan} = Schema.validate(plan)
  end

  test "workflow adoption fields are rejected outside namespaced extensions" do
    assert {:error, %{errors: errors}} =
             minimal_plan()
             |> Map.merge(%{
               "issue_id" => "TES-1",
               "tracker_kind" => "linear",
               "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
               "route_key" => "developing"
             })
             |> Schema.validate()

    assert has_error?(errors, "unknown_key", ["issue_id"])
    assert has_error?(errors, "unknown_key", ["tracker_kind"])
    assert has_error?(errors, "unknown_key", ["workflow_profile"])
    assert has_error?(errors, "unknown_key", ["route_key"])
  end

  test "workflow schema and workflow-only status do not enter generic core" do
    assert {:error, %{errors: schema_errors}} =
             minimal_plan()
             |> Map.put("schema", "workflow.execution_plan.v1")
             |> Schema.validate()

    assert has_error?(schema_errors, "invalid_schema", ["schema"])

    assert {:error, %{errors: status_errors}} =
             minimal_plan()
             |> Map.put("status", "handoff_ready")
             |> Schema.validate()

    assert has_error?(status_errors, "invalid_enum", ["status"])
  end

  test "critical generic items require trusted evidence requirements" do
    assert {:error, %{errors: errors}} =
             minimal_plan()
             |> put_in(["items", Access.at(0), "criticality"], "policy_required")
             |> Schema.validate()

    assert has_error?(errors, SchemaErrorCodes.missing_evidence_requirements(), ["items", 0, "evidence_requirements"])
  end

  test "normalizes canonical maps into stable internal records" do
    assert {:ok, %Record.Plan{} = plan} = Schema.normalize(minimal_plan())
    assert plan.plan_id == "plan-agent-1"
    assert plan.context.context_kind == "agent_run"
    assert [%Record.Item{item_id: "agent.plan"}] = plan.items
  end

  test "normalizes bounded metadata maps into explicit internal records" do
    matcher = %{"path_prefix" => "specs/"}
    reason = %{"reason_code" => "external_blocker", "actor" => "backend", "message" => "Waiting on input."}

    plan =
      minimal_plan()
      |> Map.put("source_plan_ref", %{"artifact_id" => "artifact-1", "hash" => "sha256:abc"})
      |> Map.put("rendering", %{"mode" => "preview"})
      |> Map.put("extensions", %{"symphony.test" => %{"enabled" => true}})
      |> put_in(["items", Access.at(0), "status"], "blocked")
      |> put_in(["items", Access.at(0), "status_reason"], reason)
      |> put_in(
        ["items", Access.at(0), "evidence_requirements"],
        [
          %{
            "evidence_kind" => "validation_result",
            "required_fields" => ["ok"],
            "trust_classes" => ["backend_observed"],
            "matcher" => matcher
          }
        ]
      )

    assert {:ok, %Record.Plan{} = normalized} = Schema.normalize(plan)
    assert %Record.SourcePlanRef{artifact_id: "artifact-1", hash: "sha256:abc"} = normalized.source_plan_ref
    assert %Record.Rendering{value: %{"mode" => "preview"}} = normalized.rendering
    assert %Record.Extensions{value: %{"symphony.test" => %{"enabled" => true}}} = normalized.extensions
    assert [%Record.Item{status_reason: %Record.StatusReason{reason_code: "external_blocker"}} = item] = normalized.items
    assert [%Record.EvidenceRequirement{matcher: %Record.Matcher{value: ^matcher}}] = item.evidence_requirements
    assert Record.to_map(normalized) == plan
  end

  test "context refs are bounded identity records, not raw provider payloads" do
    plan =
      minimal_plan()
      |> put_in(["context", "workflow_ref"], %{
        "profile_kind" => "coding_pr_delivery",
        "profile_version" => 1,
        "route_key" => "developing",
        "issue_id" => "ISS-1",
        "tracker_kind" => "linear"
      })
      |> put_in(["context", "repo_ref"], %{
        "provider" => "github",
        "repository_id" => "repo-1",
        "branch" => "feature/ref"
      })
      |> put_in(["context", "tracker_ref"], %{
        "tracker_kind" => "linear",
        "issue_id" => "ISS-1"
      })

    assert {:ok, %Record.Plan{} = normalized} = Schema.normalize(plan)
    assert %Record.WorkflowRef{profile_kind: "coding_pr_delivery", profile_version: 1} = normalized.context.workflow_ref
    assert %Record.RepoRef{provider: "github", repository_id: "repo-1"} = normalized.context.repo_ref
    assert %Record.TrackerRef{tracker_kind: "linear", issue_id: "ISS-1"} = normalized.context.tracker_ref

    assert {:error, %{errors: errors}} =
             plan
             |> put_in(["context", "workflow_ref", "profile"], %{"kind" => "coding_pr_delivery", "version" => 1})
             |> put_in(["context", "repo_ref", "raw_payload"], %{"clone_url" => "https://example.invalid/repo.git"})
             |> Schema.validate()

    assert has_error?(errors, "unknown_key", ["context", "workflow_ref", "profile"])
    assert has_error?(errors, "unknown_key", ["context", "repo_ref", "raw_payload"])
  end

  test "context refs must include minimum stable identity fields" do
    assert {:error, %{errors: errors}} =
             minimal_plan()
             |> put_in(["context", "workflow_ref"], %{})
             |> put_in(["context", "repo_ref"], %{"provider" => "github"})
             |> put_in(["context", "tracker_ref"], %{"tracker_kind" => "linear"})
             |> Schema.validate()

    assert has_error?(errors, SchemaErrorCodes.invalid_identity_ref(), ["context", "workflow_ref"])
    assert has_error?(errors, SchemaErrorCodes.invalid_identity_ref(), ["context", "repo_ref"])
    assert has_error?(errors, SchemaErrorCodes.invalid_identity_ref(), ["context", "tracker_ref"])
  end

  test "context kind source and mode use generic contract enums" do
    assert {:error, %{errors: errors}} =
             minimal_plan()
             |> put_in(["context", "source"], "tracker_payload")
             |> put_in(["context", "mode"], "handoff")
             |> Schema.validate()

    assert has_error?(errors, "invalid_enum", ["context", "source"])
    assert has_error?(errors, "invalid_enum", ["context", "mode"])
  end

  test "item dependencies must refer to existing items and must not cycle" do
    assert {:error, %{errors: unknown_errors}} =
             minimal_plan()
             |> put_in(["items", Access.at(0), "depends_on"], ["missing.item"])
             |> Schema.validate()

    assert Enum.any?(unknown_errors, &(&1.code == SchemaErrorCodes.invalid_dependency() and &1.dependency_id == "missing.item"))

    first = minimal_item() |> Map.put("item_id", "first") |> Map.put("depends_on", ["second"])
    second = minimal_item() |> Map.put("item_id", "second") |> Map.put("depends_on", ["first"])

    assert {:error, %{errors: cycle_errors}} =
             minimal_plan()
             |> Map.put("items", [first, second])
             |> Schema.validate()

    assert has_error?(cycle_errors, SchemaErrorCodes.dependency_cycle(), ["items"])
  end

  test "source plan refs and status reasons are bounded records" do
    assert {:error, %{errors: source_errors}} =
             minimal_plan()
             |> Map.put("source_plan_ref", %{"artifact_id" => "artifact-1"})
             |> Schema.validate()

    assert has_error?(source_errors, "missing_required_field", ["source_plan_ref", "hash"])

    assert {:error, %{errors: reason_errors}} =
             minimal_plan()
             |> put_in(["items", Access.at(0), "status"], "blocked")
             |> put_in(["items", Access.at(0), "status_reason"], %{"code" => "waiting_for_operator"})
             |> Schema.validate()

    assert has_error?(reason_errors, "unknown_key", ["items", 0, "status_reason", "code"])
    assert has_error?(reason_errors, "missing_required_field", ["items", 0, "status_reason", "reason_code"])
  end

  defp minimal_plan do
    %{
      "schema" => "agent.execution_plan.v1",
      "plan_id" => "plan-agent-1",
      "context" => %{
        "context_kind" => "agent_run",
        "workspace_id" => "workspace-1",
        "run_id" => "run-agent-1",
        "source" => "workflow",
        "mode" => "execution"
      },
      "status" => "active",
      "items" => [minimal_item()],
      "created_at" => "2026-05-20T00:00:00Z",
      "updated_at" => "2026-05-20T00:00:00Z",
      "revision" => 1
    }
  end

  defp minimal_item do
    %{
      "item_id" => "agent.plan",
      "title" => "Track execution progress",
      "kind" => "agent_step",
      "status" => "pending",
      "required" => false,
      "criticality" => "informational",
      "owned_by" => "agent",
      "source" => "agent_draft",
      "depends_on" => [],
      "evidence_requirements" => [],
      "evidence_refs" => [],
      "created_at" => "2026-05-20T00:00:00Z",
      "updated_at" => "2026-05-20T00:00:00Z",
      "revision" => 1
    }
  end

  defp has_error?(errors, code, path) do
    Enum.any?(errors, &(&1.code == code and &1.path == path))
  end
end

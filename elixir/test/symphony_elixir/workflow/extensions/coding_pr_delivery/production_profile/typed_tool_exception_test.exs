defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.TypedToolExceptionTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.TypedToolException

  test "accepts a tightly scoped non-typed tool production exception record" do
    assert {:ok, record} = TypedToolException.validate_record(valid_record())

    assert record["exception_id"] == "typed-tool-exception-linear-github-1"
    assert record["workflow_profile"] == %{"kind" => "coding_pr_delivery", "version" => 1}
    assert record["route_set"] == ["developing", "review"]
    assert record["operation_set"] == ["repo_provider.review.read"]
    assert record["fallback_authority"]["accepted_by_profile_owners"] == true
    assert record["input_schema_allowlist"]["rejects_unknown_fields"] == true
    assert record["rollback"]["restores_typed_tool_requirement"] == true
  end

  test "rejects broad raw provider passthrough and wildcard operation scopes" do
    record =
      valid_record()
      |> Map.put("raw_provider_passthrough", true)
      |> Map.put("provider_native_prompt_snippets", true)
      |> Map.put("operation_set", ["*", "provider_native_cli", "repo_provider.review.read"])

    assert {:error, %{code: "coding_pr_delivery_typed_tool_exception_invalid", errors: errors}} =
             TypedToolException.validate_record(record)

    assert Enum.any?(errors, &(&1.code == "raw_provider_passthrough_forbidden" and &1.path == ["raw_provider_passthrough"]))
    assert Enum.any?(errors, &(&1.code == "provider_native_prompt_snippets_forbidden" and &1.path == ["provider_native_prompt_snippets"]))
    assert Enum.any?(errors, &(&1.code == "overbroad_operation_scope" and &1.path == ["operation_set", "*"]))
    assert Enum.any?(errors, &(&1.code == "overbroad_operation_scope" and &1.path == ["operation_set", "provider_native_cli"]))
  end

  test "rejects Linear + CNB shadow exceptions that attempt raw provider authority" do
    record =
      valid_record()
      |> Map.put("exception_id", "typed-tool-exception-linear-cnb-shadow-raw")
      |> put_in(["repo_provider", "kind"], "cnb")
      |> Map.put("raw_provider_passthrough", true)
      |> Map.put("provider_native_prompt_snippets", true)
      |> Map.put("operation_set", ["provider_native_api", "repo_provider.change_proposal_snapshot"])
      |> Map.put("real_integration_evidence", [
        "evidence/typed-tool-exceptions/linear-cnb-shadow-raw.md"
      ])
      |> put_in(["rollback", "instructions"], "Remove linear-cnb-shadow exception and require typed CNB repo-provider tools.")

    assert {:error, %{code: "coding_pr_delivery_typed_tool_exception_invalid", errors: errors}} =
             TypedToolException.validate_record(record)

    assert Enum.any?(errors, &(&1.code == "raw_provider_passthrough_forbidden" and &1.path == ["raw_provider_passthrough"]))
    assert Enum.any?(errors, &(&1.code == "provider_native_prompt_snippets_forbidden" and &1.path == ["provider_native_prompt_snippets"]))
    assert Enum.any?(errors, &(&1.code == "overbroad_operation_scope" and &1.path == ["operation_set", "provider_native_api"]))
  end

  test "rejects missing evidence and missing expiry or re-review trigger" do
    record =
      valid_record()
      |> Map.delete("expires_at")
      |> Map.put("deterministic_tests", [])
      |> Map.put("real_integration_evidence", [])

    assert {:error, %{errors: errors}} = TypedToolException.validate_record(record)

    assert Enum.any?(errors, &(&1.code == "required_field_missing" and &1.path == ["deterministic_tests"]))
    assert Enum.any?(errors, &(&1.code == "required_field_missing" and &1.path == ["real_integration_evidence"]))
    assert Enum.any?(errors, &(&1.code == "expiry_or_re_review_required" and &1.path == []))
  end

  test "rejects unbounded real integration evidence references" do
    record =
      valid_record()
      |> Map.put("real_integration_evidence", [
        "fill-real-integration-evidence.md",
        "file:///var/tmp/typed-tool-exception.txt"
      ])

    assert {:error, %{errors: errors}} = TypedToolException.validate_record(record)

    assert Enum.any?(errors, &(&1.code == "invalid_evidence_ref"))
    assert Enum.any?(errors, &(&1.code == "placeholder_evidence_ref"))
  end

  test "accepts a re-review trigger instead of a fixed expiry" do
    record =
      valid_record()
      |> Map.delete("expires_at")
      |> Map.put("re_review_trigger", %{
        "condition" => "typed repo-provider review tool ships for this provider",
        "owner" => "workflow-tools"
      })

    assert {:ok, normalized} = TypedToolException.validate_record(record)
    assert normalized["re_review_trigger"]["owner"] == "workflow-tools"
  end

  test "rejects invalid profile and route scope" do
    record =
      valid_record()
      |> put_in(["workflow_profile", "kind"], "other_profile")
      |> Map.put("route_set", ["developing", "terminal"])

    assert {:error, %{errors: errors}} = TypedToolException.validate_record(record)

    assert Enum.any?(errors, &(&1.code == "invalid_workflow_profile" and &1.path == ["workflow_profile", "kind"]))
    assert Enum.any?(errors, &(&1.code == "invalid_route_key" and &1.path == ["route_set", "terminal"]))
  end

  test "rejects weak schema limits observability approval and rollback controls without leaking raw ids" do
    record =
      valid_record()
      |> put_in(["fallback_authority", "accepted_by_profile_owners"], false)
      |> put_in(["input_schema_allowlist", "rejects_unknown_fields"], false)
      |> put_in(["limits", "max_calls_per_run"], 0)
      |> put_in(["operator_observability", "metrics"], [])
      |> put_in(["rollback", "disables_exception"], false)
      |> Map.put("exception_id", "exception-token=ghp_secret")

    assert {:error, %{errors: errors} = error} = TypedToolException.validate_record(record)

    assert Enum.any?(errors, &(&1.code == "owner_approval_required" and &1.path == ["fallback_authority", "accepted_by_profile_owners"]))
    assert Enum.any?(errors, &(&1.code == "strict_schema_required" and &1.path == ["input_schema_allowlist", "rejects_unknown_fields"]))
    assert Enum.any?(errors, &(&1.code == "required_field_missing" and &1.path == ["limits", "max_calls_per_run"]))
    assert Enum.any?(errors, &(&1.code == "required_field_missing" and &1.path == ["operator_observability", "metrics"]))
    assert Enum.any?(errors, &(&1.code == "rollback_must_disable_exception" and &1.path == ["rollback", "disables_exception"]))
    refute inspect(error) =~ "ghp_secret"
  end

  defp valid_record do
    %{
      "exception_id" => "typed-tool-exception-linear-github-1",
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "tracker" => %{"kind" => "linear"},
      "repo_provider" => %{"kind" => "github"},
      "agent_provider" => %{"kind" => "codex"},
      "repository_class" => "single_repo_change_proposal",
      "workspace_class" => "staging_workspace",
      "route_set" => ["developing", "review"],
      "operation_set" => ["repo_provider.review.read"],
      "fallback_authority" => %{
        "owner" => "workflow-runtime",
        "authority_kind" => "temporary_backend_adapter",
        "accepted_by_profile_owners" => true
      },
      "compensating_controls" => [
        "read_only_operation",
        "bounded_schema_allowlist",
        "operator_review_packet"
      ],
      "input_schema_allowlist" => %{
        "schema_ids" => ["repo_provider.review.read.v1"],
        "rejects_unknown_fields" => true
      },
      "limits" => %{
        "max_calls_per_run" => 3,
        "max_concurrency" => 1
      },
      "audit_logging" => %{
        "event_name" => "coding_pr_delivery_typed_tool_exception_used",
        "retention_class" => "workflow_audit_staging"
      },
      "deterministic_tests" => [
        "test/symphony_elixir/workflow/extensions/coding_pr_delivery/production_profile/typed_tool_exception_test.exs"
      ],
      "real_integration_evidence" => [
        "evidence/typed-tool-exceptions/linear-github-review-read.md"
      ],
      "operator_observability" => %{
        "metrics" => ["typed_tool_exception_used_total"],
        "alerts" => ["typed_tool_exception_usage_outside_scope"],
        "runbook" => "runbooks/coding-pr-delivery/typed-tool-exception.md"
      },
      "rollback" => %{
        "owner" => "workflow-runtime",
        "instructions" => "Remove exception id from production enablement packet and require typed tool inventory.",
        "disables_exception" => true,
        "restores_typed_tool_requirement" => true
      },
      "expires_at" => "2026-07-25T00:00:00Z"
    }
  end
end

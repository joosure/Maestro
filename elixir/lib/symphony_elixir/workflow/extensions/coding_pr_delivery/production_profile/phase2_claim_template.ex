defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2ClaimTemplate do
  @moduledoc """
  Builds starter Phase 2 production-claim packets for provider evidence runs.

  Templates are bounded metadata packets for review and evidence planning. The
  builder validates each generated packet through `Claim.validate/1`, but it
  does not collect live evidence, call providers, mutate workflow state, or
  enable production gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Claim
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Contract, as: ProfileContract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.Governance

  @error_code "coding_pr_delivery_phase2_claim_template_invalid"
  @template_ids ["reference", "linear_github_ready", "tapd_cnb_shadow", "linear_cnb_shadow"]
  @runtime_targeted_discovery "runtime_targeted"
  @default_repository_class "single_repo_change_proposal"
  @default_agent_provider "configured_agent_provider"
  @default_storage_backend "workflow_extension_state_store"
  @default_retention_class "workflow_audit_staging"
  @default_retention_days 30
  @default_scrubbing_catalog "2026-06-25"

  @type template :: :reference | :linear_github_ready | :tapd_cnb_shadow | :linear_cnb_shadow
  @type result :: {:ok, map()} | {:error, map()}

  @spec templates() :: [String.t()]
  def templates, do: @template_ids

  @spec build(template() | String.t(), keyword()) :: result()
  def build(template, opts \\ [])

  def build(template, opts) when is_list(opts) do
    with {:ok, template_id} <- normalize_template(template),
         claim = claim_for(template_id, opts),
         {:ok, _normalized} <- Claim.validate(claim) do
      {:ok, claim}
    end
  end

  def build(_template, _opts) do
    {:error, invalid([issue("invalid_options", [], "Phase 2 claim template options must be a keyword list.")])}
  end

  defp normalize_template(template) when is_atom(template), do: normalize_template(Atom.to_string(template))

  defp normalize_template(template) when is_binary(template) do
    template_id = String.trim(template)

    if template_id in @template_ids do
      {:ok, template_id}
    else
      {:error, invalid([issue("unknown_template", ["template"], "Phase 2 claim template is not supported.", %{allowed_values: @template_ids})])}
    end
  end

  defp normalize_template(_template) do
    {:error, invalid([issue("invalid_template", ["template"], "Phase 2 claim template must be a string or atom.", %{allowed_values: @template_ids})])}
  end

  defp claim_for(template_id, opts) do
    profile_instance_id = profile_instance_id(template_id, opts)
    entries = entries_for(template_id, opts)

    %{
      "profile_instance_id" => profile_instance_id,
      "provider_matrix" => entries,
      "production_governance" => Enum.map(entries, &governance_packet(&1, profile_instance_id, opts)),
      "typed_tool_exceptions" => typed_tool_exceptions(template_id, opts)
    }
  end

  defp entries_for("reference", opts), do: [linear_github_ready_entry(opts), tapd_cnb_shadow_entry(opts)]
  defp entries_for("linear_github_ready", opts), do: [linear_github_ready_entry(opts)]
  defp entries_for("tapd_cnb_shadow", opts), do: [tapd_cnb_shadow_entry(opts)]
  defp entries_for("linear_cnb_shadow", opts), do: [linear_cnb_shadow_entry(opts)]

  defp linear_github_ready_entry(opts) do
    base_entry("linear-github-ready", "linear", "github", opts)
    |> Map.merge(%{
      "side_effect_mode" => "ready_to_land_write",
      "structured_plan_gates" => gates(true),
      "deployment_topology" => singleton_topology()
    })
  end

  defp tapd_cnb_shadow_entry(opts) do
    cnb_shadow_entry("tapd-cnb-shadow", "tapd", opts)
  end

  defp linear_cnb_shadow_entry(opts) do
    cnb_shadow_entry("linear-cnb-shadow", "linear", opts)
  end

  defp cnb_shadow_entry(id, tracker, opts) do
    base_entry(id, tracker, "cnb", opts)
    |> Map.merge(%{
      "side_effect_mode" => OneShotContract.shadow_mode(),
      "structured_plan_gates" => gates(false),
      "deployment_topology" => singleton_topology(),
      "shadow" => %{
        "prefix" => OneShotContract.shadow_prefix(),
        "run_id" => Keyword.get(opts, :shadow_run_id, "#{id}-run-1"),
        "authority" => OneShotContract.shadow_authority(),
        "canonical_authority" => false,
        "allowed_destinations" => OneShotContract.shadow_allowed_destinations()
      }
    })
  end

  defp base_entry(id, tracker, repo_provider, opts) do
    %{
      "id" => id,
      "workflow_profile" => workflow_profile(),
      "tracker" => %{"kind" => tracker},
      "repo_provider" => %{"kind" => repo_provider},
      "agent_provider" => %{"kind" => Keyword.get(opts, :agent_provider, @default_agent_provider)},
      "repository_class" => Keyword.get(opts, :repository_class, @default_repository_class),
      "candidate_discovery" => @runtime_targeted_discovery,
      "typed_tool_inventory" => typed_tool_inventory(),
      "evidence_files" => ["evidence/provider-matrix/#{id}.md"],
      "recovery" => %{"model" => "operator_one_shot"},
      "rollback" => %{
        "owner" => Keyword.get(opts, :rollback_owner, "workflow-runtime"),
        "disable_readiness_gate" => Gates.transition_readiness_required_gate_key()
      }
    }
  end

  defp typed_tool_inventory do
    %{
      "tracker" => ["tracker.issue_snapshot", "tracker.move_issue"],
      "repo_core" => ["repo.diff", "repo.head_sha"],
      "repo_provider" => ["repo_provider.change_proposal_snapshot", "repo_provider.change_proposal_checks"]
    }
  end

  defp governance_packet(%{"id" => entry_id}, profile_instance_id, opts) do
    retention_class = Keyword.get(opts, :retention_class, @default_retention_class)
    retention_days = Keyword.get(opts, :retention_period_days, @default_retention_days)

    %{
      "provider_matrix_entry_id" => entry_id,
      "profile_instance_id" => profile_instance_id,
      "durability_profile" => %{
        "storage_backend" => Keyword.get(opts, :storage_backend, @default_storage_backend),
        "restart_behavior" => "survives process, worker, and service restarts",
        "backup_restore" => "documented backup and restore drill before production enablement",
        "retention_class" => retention_class,
        "retention_period_days" => retention_days,
        "cleanup_behavior" => "tombstone_preserving_prune",
        "survives_process_restart" => true,
        "survives_worker_restart" => true,
        "survives_service_restart" => true
      },
      "data_governance" => %{
        "data_classification" => "workflow_audit",
        "redaction_policy" => "backend_scrubber_before_persist_or_render",
        "retention_class" => retention_class,
        "retention_period_days" => retention_days,
        "cleanup_owner" => Keyword.get(opts, :cleanup_owner, "workflow-runtime"),
        "cleanup_schedule" => Keyword.get(opts, :cleanup_schedule, "daily"),
        "scrubbing_pipeline" => %{
          "owner" => Keyword.get(opts, :scrubbing_owner, "workflow-runtime-security"),
          "pattern_catalog_version" => Keyword.get(opts, :scrubbing_pattern_catalog_version, @default_scrubbing_catalog),
          "failure_behavior" => "fail_closed",
          "enforced_boundaries" => [
            "structured_plan_evidence_write",
            "structured_plan_render",
            "coding_pr_delivery_provider_summary",
            "coding_pr_delivery_review_packet_render"
          ]
        },
        "tombstone" => %{
          "metadata_fields" => Governance.required_tombstone_fields(),
          "prevents_id_reuse" => true,
          "prevents_hidden_readiness_claims" => true,
          "preserves_audit_trail" => true
        }
      },
      "rollback" => %{
        "disable_recording_gate" => Gates.enabled_gate_key(),
        "disable_rendering_gate" => Gates.render_workpad_gate_key(),
        "disable_readiness_gate" => Gates.transition_readiness_required_gate_key(),
        "disable_provider_adapters_gate" => Gates.provider_adapters_enabled_gate_key(),
        "preserves_stored_plans_and_evidence" => true,
        "deletes_records" => false,
        "rewrites_evidence" => false,
        "makes_workpad_authoritative" => false
      },
      "evidence_files" => ["evidence/structured-plan/governance/#{entry_id}.md"]
    }
  end

  defp typed_tool_exceptions(template_id, opts) when template_id in ["reference", "linear_github_ready"] do
    if Keyword.get(opts, :include_linear_github_review_read_exception?, false) do
      [linear_github_review_read_exception(opts)]
    else
      []
    end
  end

  defp typed_tool_exceptions(_template_id, _opts), do: []

  defp linear_github_review_read_exception(opts) do
    %{
      "exception_id" => "typed-tool-exception-linear-github-review-read",
      "workflow_profile" => workflow_profile(),
      "tracker" => %{"kind" => "linear"},
      "repo_provider" => %{"kind" => "github"},
      "agent_provider" => %{"kind" => Keyword.get(opts, :agent_provider, @default_agent_provider)},
      "repository_class" => Keyword.get(opts, :repository_class, @default_repository_class),
      "workspace_class" => Keyword.get(opts, :workspace_class, "staging_workspace"),
      "route_set" => ["developing", "review"],
      "operation_set" => ["repo_provider.review.read"],
      "fallback_authority" => %{
        "owner" => Keyword.get(opts, :rollback_owner, "workflow-runtime"),
        "authority_kind" => "temporary_backend_adapter",
        "accepted_by_profile_owners" => true
      },
      "compensating_controls" => ["read_only_operation", "bounded_schema_allowlist"],
      "input_schema_allowlist" => %{
        "schema_ids" => ["repo_provider.review.read.v1"],
        "rejects_unknown_fields" => true
      },
      "limits" => %{"max_calls_per_run" => 3, "max_concurrency" => 1},
      "audit_logging" => %{
        "event_name" => "coding_pr_delivery_typed_tool_exception_used",
        "retention_class" => Keyword.get(opts, :retention_class, @default_retention_class)
      },
      "deterministic_tests" => [
        "test/symphony_elixir/workflow/extensions/coding_pr_delivery/production_profile/typed_tool_exception_test.exs"
      ],
      "real_integration_evidence" => ["evidence/typed-tool-exceptions/linear-github-review-read.md"],
      "operator_observability" => %{
        "metrics" => ["typed_tool_exception_used_total"],
        "alerts" => ["typed_tool_exception_usage_outside_scope"],
        "runbook" => "runbooks/coding-pr-delivery/typed-tool-exception.md"
      },
      "rollback" => %{
        "owner" => Keyword.get(opts, :rollback_owner, "workflow-runtime"),
        "instructions" => "Remove exception id from production enablement packet and require typed tool inventory.",
        "disables_exception" => true,
        "restores_typed_tool_requirement" => true
      },
      "expires_at" => Keyword.get(opts, :typed_tool_exception_expires_at, "2026-07-25T00:00:00Z")
    }
  end

  defp profile_instance_id(template_id, opts) do
    Keyword.get(opts, :profile_instance_id, "coding_pr_delivery.production.phase2.#{template_id}")
  end

  defp workflow_profile do
    %{"kind" => ProfileContract.kind(), "version" => ProfileContract.version()}
  end

  defp singleton_topology do
    %{
      "mode" => "singleton",
      "readiness_check" => "Reconciliation.runtime_topology_readiness/1"
    }
  end

  defp gates(transition_readiness_required) do
    %{
      Gates.enabled_gate_key() => true,
      Gates.provider_adapters_enabled_gate_key() => true,
      Gates.render_workpad_gate_key() => true,
      Gates.transition_readiness_required_gate_key() => transition_readiness_required
    }
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery Phase 2 claim template is invalid.",
      errors: errors
    }
  end

  defp issue(code, path, message, extra \\ %{}) do
    Map.merge(
      %{
        code: code,
        path: path,
        message: message
      },
      extra
    )
  end
end

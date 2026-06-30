defmodule SymphonyElixir.RepoArchitectureTest do
  use ExUnit.Case, async: true

  @provider_source_dirs [
    "lib/symphony_elixir/repo_provider",
    "lib/mix/tasks"
  ]

  @retired_agent_provider_dirs [
    "lib/symphony_elixir/codex",
    "lib/symphony_elixir/agent_provider/claude_code/tooling/mcp_server_source",
    "priv/agent",
    "priv/codex",
    Path.join(["priv", "agent_provider", "codex"])
  ]

  @retired_agent_runtime_dirs [
    Path.join(["lib", "symphony_elixir", "exec" <> "ution"]),
    Path.join(["lib", "symphony_elixir", "agent_" <> "runtime"]),
    Path.join(["lib", "symphony_elixir", "agent_" <> "credential"]),
    Path.join(["lib", "symphony_elixir", "agent_" <> "quota"])
  ]

  @retired_agent_provider_files [
    "lib/symphony_elixir/agent_provider/automation_pack.ex",
    "lib/symphony_elixir/agent_provider/runtime_environment.ex",
    "lib/symphony_elixir/agent_provider/tracker_environment.ex",
    "lib/symphony_elixir/agent_provider/workspace_tooling.ex",
    "lib/symphony_elixir/agent_provider/codex/dynamic_tool.ex",
    "lib/symphony_elixir/agent_provider/claude_code/tooling/linear_graphql_mcp_source.ex",
    "lib/symphony_elixir/agent_provider/claude_code/tooling/mcp_server_source.ex",
    "lib/symphony_elixir/agent_provider/open_code/tooling/linear_graphql_source.ex",
    Path.join(["lib", "symphony_elixir", "ssh.ex"])
  ]

  @retired_provider_app_server_support_files [
    "lib/symphony_elixir/agent_provider/claude_code/app_server/messages.ex",
    "lib/symphony_elixir/agent_provider/claude_code/app_server/port_metadata.ex",
    "lib/symphony_elixir/agent_provider/codex/app_server/port_metadata.ex",
    "lib/symphony_elixir/agent_provider/open_code/app_server/messages.ex",
    "lib/symphony_elixir/agent_provider/open_code/app_server/port_metadata.ex"
  ]

  @retired_orchestrator_files [
    "lib/symphony_elixir/orchestrator/runtime_state.ex"
  ]

  @retired_tracker_files [
    "lib/symphony_elixir/tracker/agent_environment.ex",
    "lib/symphony_elixir/tracker/linear/graphql_tool_source.ex"
  ]

  @retired_worker_daemon_session_files [
    "lib/symphony_worker_daemon/session_ledger.ex",
    "lib/symphony_worker_daemon/session_server.ex",
    "lib/symphony_worker_daemon/session_supervisor.ex",
    "lib/symphony_worker_daemon/session_server/events.ex",
    "lib/symphony_worker_daemon/session_server/payloads.ex"
  ]

  @retired_agent_automation_paths [
    Path.join(["priv", "agent_provider", "codex"]),
    Path.join(["elixir", "priv", "agent_provider", "codex"]),
    Path.join(["priv", "agent"]),
    Path.join(["elixir", "priv", "agent"]),
    Path.join(["priv", "workspace_automation", "skills", "commit"]),
    Path.join(["priv", "workspace_automation", "skills", "pull"]),
    Path.join(["priv", "workspace_automation", "skills", "debug"]),
    Path.join(["priv", "workspace_automation", "skills", "push"]),
    Path.join(["priv", "workspace_automation", "skills", "land"]),
    Path.join(["priv", "workspace_automation", "skills", "linear"]),
    Path.join(["priv", "workspace_automation", "skills", "tapd"]),
    Path.join(["elixir", "priv", "workspace_automation", "skills", "commit"]),
    Path.join(["elixir", "priv", "workspace_automation", "skills", "pull"]),
    Path.join(["elixir", "priv", "workspace_automation", "skills", "debug"]),
    Path.join(["elixir", "priv", "workspace_automation", "skills", "push"]),
    Path.join(["elixir", "priv", "workspace_automation", "skills", "land"]),
    Path.join(["elixir", "priv", "workspace_automation", "skills", "linear"]),
    Path.join(["elixir", "priv", "workspace_automation", "skills", "tapd"]),
    Path.join(["priv", "codex"]),
    Path.join(["elixir", "priv", "codex"])
  ]

  @retired_flat_workspace_automation_skill_dirs [
    "priv/workspace_automation/skills/commit",
    "priv/workspace_automation/skills/pull",
    "priv/workspace_automation/skills/debug",
    "priv/workspace_automation/skills/push",
    "priv/workspace_automation/skills/land",
    "priv/workspace_automation/skills/linear",
    "priv/workspace_automation/skills/tapd"
  ]

  @retired_platform_workflow_extension_template_asset_paths [
    "priv/workflow_templates/linear",
    "priv/workflow_templates/tapd",
    "priv/workflow_templates/_partials"
  ]

  @retired_workflow_template_api_files [
    "lib/symphony_elixir/workflow/templates.ex",
    "lib/symphony_elixir/workflow/template_registry.ex",
    "lib/symphony_elixir/workflow/template_assets.ex"
  ]

  @retired_workflow_extension_runtime_api_files [
    "lib/symphony_elixir/workflow/extension/runtime_command.ex",
    "lib/symphony_elixir/workflow/extension/runtime_context.ex",
    "lib/symphony_elixir/workflow/extension/runtime_projection.ex",
    "lib/symphony_elixir/workflow/extension/runtime_result.ex"
  ]

  @retired_workflow_extension_state_store_api_files [
    "lib/symphony_elixir/workflow/extension/state_record.ex"
  ]

  @retired_known_target_registry_api_files [
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/known_target/registry_admin.ex"
  ]

  @retired_coding_pr_delivery_reconciliation_flat_known_target_files [
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/known_target_observation.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/known_target_registration.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/known_target_registration/commands.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/known_target_registration/events.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/known_target_registration/options.ex",
    "test/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/known_target_observation_test.exs"
  ]

  @retired_coding_pr_delivery_reconciliation_flat_candidate_files [
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/candidate_inbox.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/candidate_lifecycle.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/candidate_inbox/admin.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/candidate_inbox/error.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/candidate_inbox/options.ex"
  ]

  @retired_structured_plan_review_handoff_flat_plan_files [
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/structured_plan_review_handoff/plan_evidence.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/structured_plan_review_handoff/plan_scope.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/structured_plan_review_handoff/plan_reader.ex"
  ]

  @retired_coding_pr_delivery_flat_readiness_evidence_files [
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness_evidence.ex"
  ]

  @retired_coding_pr_delivery_structured_plan_evidence_binding_flat_contract_files [
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/structured_execution_plan/evidence_binding/contract.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/structured_execution_plan/evidence_binding/raw_payload_contract.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/structured_execution_plan/evidence_binding/payload_contract.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/structured_execution_plan/evidence_binding/status_contract.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/structured_execution_plan/evidence_binding/url_contract.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/structured_execution_plan/evidence_binding/tool_contract.ex"
  ]

  @agent_automation_path_reference_files [
    "../README.md",
    "README.md",
    "docs",
    "lib",
    "priv/workspace_automation",
    "../.codex/skills"
  ]

  @codex_provider_source_dir "lib/symphony_elixir/agent_provider/codex"

  @codex_provider_allowlist [
    "lib/symphony_elixir/agent_provider/defaults.ex",
    "lib/symphony_elixir/agent_provider/kinds.ex",
    "lib/symphony_elixir/agent_provider/model_credential_env.ex",
    "lib/symphony_elixir/agent_provider/registry.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/template_catalog.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/template_catalog/contract.ex",
    "lib/symphony_elixir/workflow/template/registry.ex"
  ]

  @codex_identifier_pattern ~r/\b(?:Codex|codex|CODEX)\b/

  @forbidden_provider_patterns [
    {~r/TargetRepo\.(current_branch|head_sha|remote_url|base_branch)\(\s*"\."/, "provider code must not hardcode the current directory for repo-core reads"},
    {~r/TargetRepo\.remote_url\([^)]*"origin"/, "provider code must not hardcode origin for repo-core remote lookups"},
    {~r/Repo\.(current_branch|head_sha|remote_url|base_branch)\(\s*"\."/, "provider code must not bypass Repo.Context with hardcoded current-directory reads"},
    {~r/System\.cmd\(\s*"git"/, "provider code must use SymphonyElixir.Repo instead of direct git commands"},
    {~r/(Shell|CLI)\.run_command\(\s*"git"/, "provider code must use SymphonyElixir.Repo instead of direct git commands"},
    {~r/MuonTrap\.cmd\(\s*"git"/, "provider code must use SymphonyElixir.Repo instead of direct git commands"},
    {~r/Port\.open\([^)]*"git"/, "provider code must use SymphonyElixir.Repo instead of direct git commands"}
  ]

  @forbidden_repo_provider_workflow_extension_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions(?:\.|\b)|\bWorkflow\.Extensions(?:\.|\b)/, "RepoProvider must stay provider-neutral and must not depend on concrete workflow extension business modules"}
  ]

  @forbidden_change_proposal_body_workflow_state_patterns [
    {~r/\bSymphonyElixir\.Workflow(?:\.|\b)|\bWorkflow\.(?:Extensions|Runtime|StateTransitionReadiness|StructuredExecutionPlan|Readiness)(?:\.|\b)/,
     "RepoProvider.ChangeProposalBody must not read workflow or plugin state; extensions must precompute business bodies and pass body explicitly"},
    {~r/\b(?:CodingPrDelivery|KnownTarget|Reconciliation|ReviewHandoff|StateTransitionReadiness)\b/, "RepoProvider.ChangeProposalBody must not depend on concrete workflow business vocabulary"},
    {~r/\b(?:Config\.settings!|SymphonyElixir\.Config|Application\.get_env)\b/, "RepoProvider.ChangeProposalBody must not discover workflow/runtime state while rendering fallback bodies"}
  ]

  @forbidden_tracker_workflow_extension_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions(?:\.|\b)|\bWorkflow\.Extensions(?:\.|\b)|\bCodingPrDelivery(?:\.|\b)|\bKnownTarget(?:\.|\b)|\bReconciliation(?:\.|\b)/,
     "Tracker must stay provider-neutral and must not depend on concrete workflow extension business modules"}
  ]

  @forbidden_tracker_change_proposal_reference_patterns [
    {~r/\bChangeProposalReference\b|\bchange_proposal_reference\s*\(/,
     "Tracker must not own Coding PR Delivery change-proposal reference extraction; extension-owned adapters must interpret issue metadata"}
  ]

  @forbidden_tracker_change_proposal_reference_call_patterns [
    {~r/\bTracker\.change_proposal_reference\s*\(/, "Coding PR Delivery code must use extension-owned reference extraction instead of Tracker.change_proposal_reference/1"}
  ]

  @forbidden_domain_workflow_capability_facade_patterns [
    {~r/\bSymphonyElixir\.Workflow\.CapabilityNames\b|\bWorkflow\.CapabilityNames\b/,
     "domain contexts must own capability strings through their own Capabilities modules, not Workflow.CapabilityNames"}
  ]

  @forbidden_workflow_capability_name_owner_patterns [
    {~r/"(?:tracker|repo|repo_provider|agent)\./, "Workflow.CapabilityNames must not own provider, tracker, repo, repo-provider, or agent capability strings"}
  ]

  @forbidden_observability_concrete_capability_patterns [
    {~r/\bSymphonyElixir\.(?:Tracker|Repo|RepoProvider|Agent)\.Capabilities\b/, "Observability must classify capabilities through Capability.Registry, not concrete domain capability modules"},
    {~r/"(?:tracker|repo|repo_provider|agent)\.[^"]+"/, "Observability must not hardcode concrete provider capability strings"}
  ]

  @forbidden_capability_registry_domain_source_patterns [
    {~r/\bSymphonyElixir\.(?:Tracker|Repo|RepoProvider|Agent)\.Capabilities\b|\bSymphonyElixir\.Workflow\.CapabilityNames\b/,
     "Capability.Registry must aggregate configured catalog/source modules and must not name built-in domain capability sources directly"},
    {~r/"(?:tracker|repo|repo_provider|agent|workflow)\.[^"]+"/, "Capability platform mechanisms must not own concrete domain capability strings"}
  ]

  @forbidden_assembly_catalog_capability_patterns [
    {~r/^\s*(?:alias|import|require|use)\s+/m, "assembly capability catalog modules must stay assembly-only and avoid local aliases/imports/use"},
    {~r/"(?:tracker|repo|repo_provider|agent|workflow)\.[^"]+"/, "assembly capability catalog modules must list source modules only and must not own concrete capability strings"},
    {~r/\bdefp?\s+(?!source_modules\b)[a-zA-Z_][a-zA-Z0-9_?!]*/, "assembly capability catalog modules must only expose the source_modules/0 catalog callback"}
  ]

  @forbidden_assembly_catalog_dynamic_tool_source_patterns [
    {~r/^\s*(?:alias|import|require|use)\s+/m, "assembly Dynamic Tool source catalog modules must stay assembly-only and avoid local aliases/imports/use"},
    {~r/\bdefp?\s+(?!source_specs\b)[a-zA-Z_][a-zA-Z0-9_?!]*/, "assembly Dynamic Tool source catalog modules must only expose the source_specs/1 catalog callback"}
  ]

  @forbidden_root_config_capability_source_patterns [
    {~r/config\s+:symphony_elixir,\s+:capability_sources,[\s\S]*?\bsources:/, "root config must register capability source catalogs, not direct capability source modules"},
    {~r/\bSymphonyElixir\.(?:Tracker|Repo|RepoProvider|Agent)\.Capabilities\b|\bSymphonyElixir\.Workflow\.CapabilityNames\b/,
     "root config must register assembly catalog capability sources, not built-in domain capability modules"}
  ]

  @forbidden_root_config_dynamic_tool_source_patterns [
    {~r/config\s+:symphony_elixir,\s+:dynamic_tool_sources,[\s\S]*?\bSymphonyElixir\.(?:Tracker|Repo|RepoProvider)\.DynamicToolSource\b/,
     "root config must register Dynamic Tool source assembly catalogs, not concrete source modules"}
  ]

  @repo_local_skill_roots [
    "../.codex/skills"
  ]

  @runtime_skill_paths [
    "priv/workspace_automation/skills/core/pull/SKILL.md",
    "priv/workspace_automation/skills/repo/push/SKILL.md",
    "priv/workspace_automation/skills/repo/land/SKILL.md",
    "priv/workspace_automation/skills/core/commit/SKILL.md"
  ]

  @forbidden_runtime_skill_patterns [
    {~r/\bgit\s+clone\b/, "repo bootstrap should use the repo helper clone command"},
    {~r/\bgit\s+fetch\b/, "repo sync should use the repo helper fetch command"},
    {~r/\bgit\s+merge\b/, "repo sync should use the repo helper merge command"},
    {~r/\bgit\s+config\s+rerere\./, "rerere setup should use the repo helper enable-rerere command"},
    {~r/\bgit\s+diff\b/, "diff inspection should use the repo helper diff command"},
    {~r/\bgit\s+pull\b/, "repo sync should use repo helper fetch and merge commands"},
    {~r/\bgit\s+push\b/, "publishing should use the repo helper push command"},
    {~r/\bgit\s+branch\s+--show-current\b/, "branch lookup should use the repo helper current-branch command"},
    {~r/\bgit\s+status\b/, "status lookup should use the repo helper status command"},
    {~r/\bgit\s+add\b/, "staging should use the repo helper stage-all command"},
    {~r/\bgit\s+commit\b/, "committing should use the repo helper commit-staged command"}
  ]

  @forbidden_repo_local_skill_patterns [
    {~r/\bSYMPHONY_WORKSPACE_AUTOMATION_DIR\b/, "repo-local Codex skills must not depend on runtime workspace env"},
    {~r/elixir\/priv\/workspace_automation/, "repo-local Codex skills must not use the bundled runtime automation path"},
    {~r/\b(?:automation_dir|repo_cmd|provider_cmd)\b/, "repo-local Codex skills must not use runtime automation helper variables"},
    {~r/\bbundled repo(?:-provider)? helper\b/i, "repo-local Codex skills must not describe bundled runtime helpers as their default path"},
    {~r/\brepo-provider helper\b/i, "repo-local Codex skills must not depend on runtime repo-provider helpers"}
  ]

  @forbidden_agent_provider_patterns [
    {Regex.compile!("\\bSymphonyElixir\\." <> "Exec" <> "ution\\b"), "agent runtime modules must use SymphonyElixir.Agent"},
    {Regex.compile!("\\bSymphonyElixir\\.Agent" <> "Runtime\\b"), "agent runtime modules must use SymphonyElixir.Agent.Runtime"},
    {Regex.compile!("\\bSymphonyElixir\\.Agent" <> "Credential\\b"), "agent credential modules must use SymphonyElixir.Agent.Credential"},
    {Regex.compile!("\\bSymphonyElixir\\.Agent" <> "Quota\\b"), "agent quota modules must use SymphonyElixir.Agent.Quota"},
    {Regex.compile!("\\bSymphonyElixir\\." <> "SSH\\b"), "SSH transport must use SymphonyElixir.Platform.SSH"},
    {~r/\bSymphonyElixir\.AgentProvider\.(?:RuntimeEnvironment|TrackerEnvironment|WorkspaceTooling)\b/,
     "shared runtime environment and workspace helpers must live under Agent.Runtime, Tracker, or Workspace"},
    {Regex.compile!("\\bAgent" <> "Credentials\\b"), "agent credential schema modules must not keep flat credential naming"},
    {Regex.compile!("\\bAgent" <> "Quota\\b"), "agent quota schema modules must not keep flat quota naming"},
    {~r/\bSymphonyElixir\.Tracker\.AgentEnvironment\b/, "dynamic-tool provider process env must be coordinated by SymphonyElixir.Agent.Runtime.DynamicToolBridge.Environment"},
    {~r/\bSymphonyElixir\.Tracker\.Linear\.GraphqlToolSource\b/, "provider-specific Linear GraphQL source renderers must live under their owning AgentProvider tooling namespaces"},
    {~r/\bcodex_humanizer\b/i, "Codex display mapping must live under agent_provider/codex event summary mapping"},
    {~r/\bhumanize(?:r|_message|_event)?\b/i, "agent message display should use EventSummary and MessagePresenter naming"},
    {Regex.compile!("\\b" <> "com" <> "pat" <> "ibility_wrappers?\\b", "i"), "removed wrapper modules and tests must not return"},
    {~r/\bautomation_source_dir\b/, "workspace automation source resolution belongs under workspace/"},
    {~r/\bSymphonyElixir\.Orchestrator\.RuntimeState\b/, "orchestrator running-entry state helper must use SymphonyElixir.Orchestrator.RunningState"}
  ]

  @forbidden_agent_automation_patterns [
    {@codex_identifier_pattern, "bundled workspace automation must stay provider-neutral"},
    {~r/\.codex\b/, "bundled workspace automation must not hardcode the Codex discovery directory"},
    {~r/elixir\/priv\/workspace_automation/, "bundled workspace automation runtime guidance must use SYMPHONY_WORKSPACE_AUTOMATION_DIR"}
  ]

  @forbidden_agent_automation_reference_patterns [
    {~r/\bworkspace_codex_bootstrap_/, "workspace automation events must stay provider-neutral"},
    {~r/\bSymphonyElixir\.Codex\./, "Codex modules must use the AgentProvider.Codex namespace"}
  ]

  @forbidden_agent_provider_dependency_patterns [
    {~r/\bSymphonyElixir\.Platform\.SSH\b/, "agent providers must use Workspace.Remote instead of direct SSH transport"},
    {~r/\bSymphonyElixir\.Tracker\.(?:Linear|Tapd|Memory)\b/, "agent providers must consume dynamic tools through Agent.DynamicTool or the Tracker facade, not concrete tracker adapter modules"},
    {~r/\bTracker\.(?:dynamic_tools|tool_environment|execute_dynamic_tool)\b/, "agent providers must route dynamic tool advertisement and execution through Agent.DynamicTool"},
    {~r/\b(?:LinearGraphql|SYMPHONY_LINEAR|symphony-linear|linear_graphql_mcp|api\.linear\.app)\b/, "agent providers must not hardcode concrete tracker tool names, credential variables, or endpoints"}
  ]

  @forbidden_agent_dynamic_tool_dependency_patterns [
    {~r/\balias\s+SymphonyElixir\.Tracker\b|\bTracker\.(?:dynamic_tools|tool_environment|execute_dynamic_tool)\b/,
     "Agent.DynamicTool core must depend on Source abstractions, not the Tracker facade directly"},
    {~r/\bSymphonyElixir\.Workflow(?:\.|\b)|\bWorkflow\./, "Agent.DynamicTool core must not depend on Workflow domain modules or interpret workflow semantics"},
    {~r/\bSymphonyElixir\.Tracker(?:\.|\b)|\bTracker\./, "Agent.DynamicTool core must not depend on Tracker domain modules; tracker behavior belongs in Source/adoption layers"},
    {~r/\bSymphonyElixir\.RepoProvider(?:\.|\b)|\bRepoProvider\./, "Agent.DynamicTool core must not depend on RepoProvider domain modules; repo-provider behavior belongs in Source/adoption layers"},
    {~r/\bSymphonyElixir\.Repo(?:\.|\b)|\bRepo\./, "Agent.DynamicTool core must not depend on Repo domain modules; repo behavior belongs in Source/adoption layers"},
    {~r/\bCapabilityNames\b/, "Agent.DynamicTool core must treat capability strings as opaque and must not depend on domain capability registries"},
    {~r/\bworkflowCapability\b|\bdynamic_tool_workflow_capability\b/, "Agent.DynamicTool core must use platform capability keys, not legacy workflow-specific Dynamic Tool keys"}
  ]

  @forbidden_agent_dynamic_tool_opaque_payload_patterns [
    {~r/\bdefp?\s+(?:workflow_profile|workflow_route|tracker_kind|repo_provider_kind|readiness_policy|route_policy|workflow_readiness)\b/,
     "Agent.DynamicTool core must not expose business-domain accessors for opaque source/adoption payloads"},
    {~r/\bContext\.(?:workflow_profile|workflow_route|tracker_kind|repo_provider_kind|readiness_policy|route_policy|workflow_readiness)\b/,
     "Agent.DynamicTool callers must not rely on business-domain context accessors in the Dynamic Tool core"},
    {~r/\b(?:Map\.get|get_in|Access\.get)\s*\(\s*(?:source_context|adoption_settings)\b[^\n]*(?:"(?:workflow|workflow_profile|profile|route|route_policy|readiness|readiness_policy|tracker|tracker_kind|repo|repo_provider|repository|pull_request|change_proposal)"|:(?:workflow|workflow_profile|profile|route|route_policy|readiness|readiness_policy|tracker|tracker_kind|repo|repo_provider|repository|pull_request|change_proposal)\b)/i,
     "Agent.DynamicTool core must not read business fields from opaque source_context or adoption_settings"},
    {~r/\b(?:source_context|adoption_settings)\s*\[[^\]\n]*(?:"(?:workflow|workflow_profile|profile|route|route_policy|readiness|readiness_policy|tracker|tracker_kind|repo|repo_provider|repository|pull_request|change_proposal)"|:(?:workflow|workflow_profile|profile|route|route_policy|readiness|readiness_policy|tracker|tracker_kind|repo|repo_provider|repository|pull_request|change_proposal)\b)/i,
     "Agent.DynamicTool core must not index business fields from opaque source_context or adoption_settings"},
    {~r/\b(?:source_context|adoption_settings)\.(?:workflow|workflow_profile|profile|route_policy|readiness|readiness_policy|tracker|tracker_kind|repo|repo_provider|repository|pull_request|change_proposal)\b/i,
     "Agent.DynamicTool core must not use dot access for business fields from opaque source_context or adoption_settings"},
    {~r/%\{\s*(?:"(?:workflow|workflow_profile|profile|route|route_policy|readiness|readiness_policy|tracker|tracker_kind|repo|repo_provider|repository|pull_request|change_proposal)"|(?:workflow|workflow_profile|profile|route|route_policy|readiness|readiness_policy|tracker|tracker_kind|repo|repo_provider|repository|pull_request|change_proposal):)[^}]*\}\s*=\s*(?:source_context|adoption_settings)\b/i,
     "Agent.DynamicTool core must not pattern match business fields from opaque source_context or adoption_settings"}
  ]

  @forbidden_orchestrator_coding_pr_delivery_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions\.CodingPrDelivery(?:\.|\b)|\bCodingPrDelivery(?:\.|\b)/,
     "orchestrator must invoke Workflow.Extension runtime boundaries, not concrete Coding PR Delivery extension modules"}
  ]

  @forbidden_orchestrator_poll_cycle_extension_bypass_patterns [
    {~r/\bSymphonyElixir\.ChangeProposalReconciliation(?:\.|\b)|\bChangeProposalReconciliation(?:\.|\b)/,
     "orchestrator poll cycle must invoke workflow runtime extensions instead of legacy concrete workflow business contexts"},
    {~r/\bSymphonyElixir\.Workflow\.Extensions\.CodingPrDelivery(?:\.|\b)|\bCodingPrDelivery(?:\.|\b)|\bReconciliation(?:\.|\b)/,
     "orchestrator poll cycle must invoke workflow runtime extensions instead of concrete Coding PR Delivery modules"},
    {~r/\bchange_proposal_reconciler_opts\b/, "orchestrator poll cycle must expose generic runtime_extension_opts instead of concrete extension option names"}
  ]

  @forbidden_workflow_platform_concrete_extension_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions\.CodingPrDelivery(?:\.|\b)|\bCodingPrDelivery(?:\.|\b)|\bKnownTarget(?:\.|\b)|\bReviewHandoff(?:\.|\b)|\breview_handoff_not_ready\b/,
     "workflow platform core must consume registered extension contributions instead of concrete Coding PR Delivery business modules"}
  ]

  @forbidden_workflow_registry_concrete_extension_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions(?:\.|\b)/, "workflow profile/template registries must consume extension contributions, not concrete extension modules"},
    {~r/\b(?:CodingPrDelivery|KnownTarget|Reconciliation|ReviewHandoff|ChangeProposal)\b/, "workflow profile/template registries must not mention concrete extension business vocabulary"}
  ]

  @forbidden_workflow_template_source_priv_path_patterns [
    {~r/Path\.join\(\s*"[^"]*\.\.[^"]*priv/, "workflow template asset roots must resolve from OTP application priv directories, not source-relative priv paths"}
  ]

  @forbidden_legacy_workflow_template_api_patterns [
    {~r/\bSymphonyElixir\.Workflow\.(?:Templates|TemplateRegistry|TemplateAssets)\b|\bWorkflow\.(?:Templates|TemplateRegistry|TemplateAssets)\b/,
     "workflow template callers must use the Workflow.Template facade"}
  ]

  @forbidden_workflow_template_internal_api_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Template\.(?:Registry|Resolver|Assets|PathRules)\b|\bWorkflow\.Template\.(?:Registry|Resolver|Assets|PathRules)\b/,
     "production workflow template callers must use the Workflow.Template facade instead of internal template modules"}
  ]

  @workflow_extensions_dir "lib/symphony_elixir/workflow/extensions"
  @coding_pr_delivery_dir "lib/symphony_elixir/workflow/extensions/coding_pr_delivery"
  @coding_pr_delivery_host_adapters_dir "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/host_adapters"

  @bundled_workflow_extension_namespace_entries [
    "coding_pr_delivery",
    "coding_pr_delivery.ex"
  ]

  @bundled_workflow_extension_modules [
    SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  ]

  @forbidden_coding_pr_delivery_facade_implementation_patterns [
    {~r/\bdefp\s+/, "CodingPrDelivery facade must stay a thin extension manifest and must not own private helper logic"},
    {~r/\b(?:Reconciliation|KnownTarget|Inbox|StartupBacklogBootstrap|Watcher)\b/,
     "CodingPrDelivery facade must delegate business, registry, producer, and supervision details to extension-owned submodules"},
    {~r/\b(?:RuntimeProjection|RuntimeResult|reconcile_runtime|reconciler_opts|targeted_issue_ids_fn|defer_targeted_issue_ids_fn)\b/,
     "CodingPrDelivery facade must delegate runtime adapter details to CodingPrDelivery.Runtime"},
    {~r/\b(?:Workflow\.Template\.(?:Registry|Resolver|Assets|PathRules)|Template\.(?:entry!|app_priv_root!|asset_path!))\b|@template_asset_dir|"(?:linear|tapd)\/(?:github|cnb)\/[^"]+"/,
     "CodingPrDelivery facade must delegate template catalog details to CodingPrDelivery.TemplateCatalog"},
    {~r/\b(?:Storage\.Repo|StateStore|Ecto|SQLite|CredentialStore|Credential\.Store)\b/, "CodingPrDelivery facade must not depend on physical storage or storage-oriented credential APIs"}
  ]

  @forbidden_coding_pr_delivery_key_compatibility_patterns [
    {~r/\bString\.to_existing_atom\b|\bmap_get_existing_atom\b/,
     "Coding PR Delivery adapters must consume typed structs, keyword opts, or canonical string-key payloads instead of dynamic atom/string key compatibility"},
    {~r/Map\.get\([^\n]+\) \|\| Map\.get\([^\n]+Atom\.to_string/,
     "Coding PR Delivery adapters must not use generic atom/string key fallback; add explicit typed-struct selectors or canonical string-key contracts"}
  ]

  @forbidden_workflow_extension_flat_runtime_module_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extension\.Runtime(?:Command|Context|Projection|Result)\b/, "workflow extension runtime envelopes must live under Workflow.Extension.Runtime.*"}
  ]

  @forbidden_workflow_extension_flat_state_store_module_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extension\.StateRecord\b/, "workflow extension state records must live under Workflow.Extension.StateStore.Record"}
  ]

  @workflow_extension_diagnostics_path "lib/symphony_elixir/workflow/extension/diagnostics.ex"

  @workflow_extension_diagnostics_public_functions ~w(caught detailed_type_atom exception type_atom type_name)

  @known_target_dir "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/known_target"

  @known_target_registry_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/known_target/registry.ex"

  @known_target_registry_line_limit 280

  @known_target_storage_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/known_target/storage.ex"

  @known_target_state_store_backend_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/known_target/storage/state_store_backend.ex"

  @candidate_inbox_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/candidate/inbox.ex"

  @candidate_inbox_public_functions ~w(defer_issue_ids drain_issue_ids enqueue_issue_ids handle_call init lifecycle_snapshot reactivate_issue_ids start_link)

  @coding_pr_delivery_reconciliation_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation.ex"
  @coding_pr_delivery_reconciliation_line_limit 70
  @coding_pr_delivery_reconciliation_public_functions ~w(enqueue_issue_ids known_targets reconcile_runtime register_known_target run_known_target_watcher_once runtime_topology_readiness)

  @coding_pr_delivery_reconciliation_config_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/config.ex"
  @coding_pr_delivery_reconciliation_config_dir "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/config"
  @coding_pr_delivery_reconciliation_config_contract_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/config/contract.ex"
  @coding_pr_delivery_reconciliation_config_line_limit 120
  @coding_pr_delivery_reconciliation_config_public_functions ~w(config_path config_path_name enabled enabled? from_settings outcome_route source_route source_route? source_route_keys validate_settings)

  @coding_pr_delivery_reconciliation_contract_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/contract.ex"
  @coding_pr_delivery_reconciliation_contract_dir "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/contract"
  @coding_pr_delivery_reconciliation_contract_capabilities_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/contract/capabilities.ex"
  @coding_pr_delivery_reconciliation_contract_events_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/contract/events.ex"
  @coding_pr_delivery_reconciliation_contract_producers_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/contract/producers.ex"
  @coding_pr_delivery_reconciliation_contract_statuses_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/contract/statuses.ex"
  @coding_pr_delivery_reconciliation_contract_line_limit 70
  @coding_pr_delivery_reconciliation_contract_public_functions ~w(component event event_name producer producer_status reason_name reconciliation_status tracker_attach_external_reference_capability tracker_move_issue_capability transition_event_name transition_events)

  @coding_pr_delivery_reconciliation_events_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/events.ex"
  @coding_pr_delivery_reconciliation_events_base_fields_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/events/base_fields.ex"
  @coding_pr_delivery_reconciliation_events_change_proposal_fields_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/events/change_proposal_fields.ex"
  @coding_pr_delivery_reconciliation_events_emitter_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/events/emitter.ex"
  @coding_pr_delivery_reconciliation_events_emitter_defaults_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/host_adapters/reconciliation/event_emitter_defaults.ex"
  @coding_pr_delivery_reconciliation_events_fields_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/events/fields.ex"
  @coding_pr_delivery_reconciliation_events_route_fields_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/events/route_fields.ex"
  @coding_pr_delivery_reconciliation_events_diagnostics_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/events/diagnostics.ex"
  @coding_pr_delivery_reconciliation_provider_facts_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/provider_facts.ex"
  @coding_pr_delivery_reconciliation_provider_facts_contract_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/provider_facts/contract.ex"
  @coding_pr_delivery_reconciliation_provider_facts_client_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/provider_facts/client.ex"
  @coding_pr_delivery_reconciliation_provider_facts_builder_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/provider_facts/builder.ex"
  @coding_pr_delivery_reconciliation_provider_facts_defaults_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/host_adapters/reconciliation/provider_facts_defaults.ex"
  @coding_pr_delivery_reconciliation_provider_facts_summary_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/provider_facts/summary.ex"
  @coding_pr_delivery_reconciliation_provider_facts_summary_dir "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/provider_facts/summary"
  @coding_pr_delivery_reconciliation_provider_facts_summary_line_limit 80
  @coding_pr_delivery_reconciliation_provider_facts_summary_public_functions ~w(check_summary mergeability_summary provider_state review_summary unresolved_actionable_feedback?)
  @coding_pr_delivery_reconciliation_provider_facts_line_limit 130
  @coding_pr_delivery_reconciliation_provider_facts_public_functions ~w(facts)
  @coding_pr_delivery_reconciliation_one_shot_deps_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/one_shot/deps.ex"
  @coding_pr_delivery_reconciliation_one_shot_host_deps_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/host_adapters/reconciliation/one_shot_host_deps.ex"
  @coding_pr_delivery_reconciler_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/reconciler.ex"
  @coding_pr_delivery_reconciler_clients_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/reconciler/clients.ex"
  @coding_pr_delivery_reconciler_defaults_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/host_adapters/reconciliation/reconciler_defaults.ex"
  @coding_pr_delivery_reconciler_diagnostics_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/reconciler/diagnostics.ex"
  @coding_pr_delivery_reconciler_line_limit 120
  @coding_pr_delivery_reconciler_public_functions ~w(reconcile)

  @forbidden_candidate_inbox_patterns [
    {~r/^\s*def\s+reset\s*\(/m, "Inbox destructive reset must stay behind Inbox.Admin, not the runtime inbox facade"},
    {~r/@spec\s+drain_issue_ids\b[^\n]*pos_integer/, "Inbox.drain_issue_ids must accept keyword opts only"},
    {~r/def\s+drain_issue_ids\([^)]*\)\s+when\s+is_integer\(/, "Inbox must not keep integer drain-limit shortcut APIs"},
    {~r/\bdef\s+defer_issue_ids\b(?s:.{0,700})\bis_map\(\s*(?:details|opts)\s*\)/, "Inbox must not accept map details or map opts compatibility input"},
    {~r/\bKeyword\.(?:get|fetch|get_lazy)\(\s*opts\s*,\s*:server\b/, "Inbox server selection must stay behind Inbox.Options"},
    {~r/\bwith_server\b/, "Inbox must fail closed on missing server instead of using fallback helpers"},
    {~r/\bMap\.to_list\(\s*details\s*\)/, "Inbox defer details must stay canonical keyword opts"}
  ]

  @workflow_extension_registry_path "lib/symphony_elixir/workflow/extension/registry.ex"

  @workflow_extension_registry_line_limit 120

  @workflow_extension_registry_public_functions ~w(entries validate validate!)

  @workflow_extension_runtime_path "lib/symphony_elixir/workflow/extension/runtime.ex"

  @workflow_extension_runtime_line_limit 60

  @workflow_extension_runtime_public_functions ~w(run_poll_cycle)

  @workflow_extension_state_store_path "lib/symphony_elixir/workflow/extension/state_store.ex"

  @workflow_extension_state_store_line_limit 90

  @workflow_extension_state_store_public_functions ~w(delete get list put)

  @workflow_extension_state_store_record_path "lib/symphony_elixir/workflow/extension/state_store/record.ex"

  @workflow_extension_state_store_record_line_limit 260

  @operator_command_registry_path "lib/symphony_elixir/workflow/extension/operator_command/registry.ex"

  @operator_command_registry_line_limit 90

  @operator_command_registry_public_functions ~w(entries fetch validate)

  @tool_result_recorder_registry_path "lib/symphony_elixir/workflow/extension/tool_result_recorder/registry.ex"

  @tool_result_recorder_registry_line_limit 80

  @tool_result_recorder_registry_public_functions ~w(entries validate)

  @tool_result_recorder_dispatcher_path "lib/symphony_elixir/workflow/extension/tool_result_recorder/dispatcher.ex"

  @tool_result_recorder_dispatcher_line_limit 140

  @tool_result_recorder_dispatcher_public_functions ~w(record_tool_result)

  @forbidden_known_target_registry_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions\.CodingPrDelivery\.KnownTarget\.RegistryAdmin\b|\bKnownTarget\.RegistryAdmin\b|\bRegistryAdmin\b/,
     "flat KnownTarget RegistryAdmin API is retired; use KnownTarget.Registry.Admin"},
    {~r/\bSymphonyElixir\.Workflow\.Extension\.StateStore\b|\bStateStore\./, "KnownTarget.Registry must persist through KnownTarget.Storage, not the platform StateStore facade"},
    {~r/\bSymphonyElixir\.Storage\.Repo\b|\bStorage\.Repo\b|\bRepo\./, "KnownTarget.Registry must not depend on physical storage repos"},
    {~r/\b(?:Ecto|SQLite)\b|\bon_conflict\b|\btransaction\b/i, "KnownTarget.Registry must not own database or transaction details"},
    {~r/\bSymphonyElixir\.Orchestrator(?:\.|\b)|\bOrchestrator\./, "KnownTarget.Registry must not call Orchestrator internals"},
    {~r/\b(?:Reconciliation|Readiness|ReviewHandoff|Watcher|Inbox|RuntimeCommand|ToolResultRecorder)\b/,
     "KnownTarget.Registry must not own reconciliation, readiness, producer, or runtime-command logic"},
    {~r/\b(?:expected_revision|revision|status_machine|transition_table)\b/i, "KnownTarget.Registry must not grow execution-plan-style revision or state-machine semantics"},
    {~r/^\s*def\s+reset\s*\(/m, "destructive KnownTarget reset must stay behind Registry.Admin, not the runtime Registry facade"},
    {Regex.compile!("\\bKnownTarget\\.Storage\\.StateStoreBackend\\b|\\bStateStoreBackend\\b|\\bKnownTarget\\.Storage\\.Extension" <> "StateBackend\\b|\\bExtension" <> "StateBackend\\b"),
     "KnownTarget.Registry must depend on the KnownTarget.Storage port, not a concrete storage backend"}
  ]

  @forbidden_known_target_storage_patterns [
    {~r/\bStateStoreBackend\b/, "KnownTarget.Storage facade must not directly bind to a concrete backend; use Storage.BackendSelector"},
    {~r/^\s*@callback\s+reset\s*\(/m, "destructive KnownTarget storage reset must not be part of the ordinary Storage backend behaviour"},
    {~r/^\s*def\s+reset\s*\(/m, "destructive KnownTarget storage reset must stay behind Storage.Admin, not the ordinary storage facade"},
    {~r/\bdefp\s+(?:backend!?|validate_opts|validate_target|validate_targets|validate_issue_id)\b/,
     "KnownTarget.Storage facade must delegate backend selection and validation to Storage.BackendSelector/Storage.Validator"}
  ]

  @forbidden_known_target_state_store_backend_patterns [
    {~r/\bKeyword\.(?:get|get_lazy|fetch|fetch!)\(\s*opts\s*,\s*:extension_id\b/, "KnownTarget StateStoreBackend must not let storage callers override the extension namespace"},
    {~r/@extension_version\b|\"builtin\"/, "KnownTarget StateStoreBackend must read plugin/extension version metadata from the extension facade, not hardcode backend-local versions"},
    {~r/\bdefp\s+(?:json_value|json_key|json_map|diagnostic_type|invalid_workflow_scope_value)\b/,
     "KnownTarget StateStoreBackend must delegate workflow-scope JSON validation to KnownTarget.Storage.Scope"},
    {~r/\bdefp\s+(?:validate_opts|validate_target|validate_targets|validate_issue_id)\b/,
     "KnownTarget StateStoreBackend must reuse KnownTarget.Storage.Validator instead of owning duplicate validation rules"}
  ]

  @forbidden_known_target_core_dependency_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions\.CodingPrDelivery\.Reconciliation\.Facts\b|\bReconciliation\.Facts\b/,
     "KnownTarget core modules must not depend on reconciliation facts; use a reconciliation-owned adapter"},
    {~r/\bSymphonyElixir\.Issue\b|\b%Issue\s*\{|\balias\s+SymphonyElixir\.Issue\b/,
     "KnownTarget core modules must not compile-time depend on platform Issue structs; accept issue-like maps/structs at adapter boundaries"}
  ]

  @forbidden_concrete_workflow_extension_reference_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions\.CodingPrDelivery(?:\.|\b)|\bCodingPrDelivery(?:\.|\b)|\bKnownTarget(?:\.|\b)|\bChangeProposalReconciliation(?:\.|\b)|\bReviewHandoff(?:\.|\b)/,
     "concrete workflow extension references must stay in the owning extension or workflow-extension catalog assembly"}
  ]

  @forbidden_legacy_change_proposal_runtime_patterns [
    {~r/\bSymphonyElixir\.ChangeProposalReconciliation(?:\.|\b)|\bChangeProposalReconciliation(?:\.|\b)/,
     "legacy ChangeProposalReconciliation runtime modules must not return outside Coding PR Delivery extension internals"},
    {~r/\bSymphonyElixir\.Workflow\.ChangeProposalReconciliation(?:\.|\b)/,
     "legacy Workflow.ChangeProposalReconciliation runtime modules must not return outside Coding PR Delivery extension internals"},
    {~r/\bchange_proposal_reconciliation\b/, "legacy change_proposal_reconciliation runtime paths must not return outside Coding PR Delivery extension internals"},
    {~r/\bchange_proposal_reconciler_opts\b/, "platform runtime options must stay generic and must not expose legacy change-proposal reconciler option names"},
    {~r/\bchange_proposal\.reconcile\b|\bMix\.Tasks\.ChangeProposal\.Reconcile\b/,
     "legacy change_proposal.reconcile Mix entrypoint must not return; use workflow.command with registered operator commands"}
  ]

  @forbidden_assembly_catalog_workflow_extension_patterns [
    {~r/^\s*(?:alias|import|require|use)\s+/m, "assembly workflow-extension catalog modules must stay assembly-only and avoid local aliases/imports/use"},
    {~r/\bSymphonyElixir\.(?:Storage\.Repo|Tracker|RepoProvider|Orchestrator)\b|\b(?:Storage\.Repo|Tracker|RepoProvider|Orchestrator|Ecto|SQLite)\b/,
     "assembly workflow-extension catalog modules must not depend on provider, orchestrator, or physical storage APIs"},
    {~r/\b(?:StateStore|OperatorCommand|ToolResultRecorder|RuntimeCommand|Reconciliation|KnownTarget|ReviewHandoff)\b/,
     "assembly workflow-extension catalog modules must not contain extension business logic, runtime command handling, state storage, or recorder/command implementations"},
    {~r/\bdefp?\s+(?!extension_modules\b)[a-zA-Z_][a-zA-Z0-9_?!]*/, "assembly workflow-extension catalog modules must only expose the extension_modules/1 source callback"}
  ]

  @forbidden_assembly_catalog_storage_patterns [
    {~r/^\s*(?:alias|import|require|use)\s+/m, "assembly storage catalog modules must stay assembly-only and avoid local aliases/imports/use"},
    {~r/\bSymphonyElixir\.Storage\.Repo\b|\b(?:Storage\.Repo|Ecto)\b/, "assembly storage catalog modules must not depend on physical storage runtime APIs"},
    {~r/\bdefp?\s+(?!entry_modules\b)[a-zA-Z_][a-zA-Z0-9_?!]*/, "assembly storage catalog modules must only expose the entry_modules/1 source callback"}
  ]

  @forbidden_storage_table_catalog_facade_patterns [
    {~r/\bSymphonyElixir\.(?:Agent|Workflow|Tracker|Repo|RepoProvider|Orchestrator|WorkerDaemon)(?:\.|\b)/,
     "Storage.TableCatalog must stay a platform facade and must not compile-depend on concrete domain modules"},
    {~r/\b(?:File\.(?:ls!?|read!?|regular\?|dir\?|exists\?)|Path\.wildcard|Code\.compile_file|:code\.all_loaded)\b/,
     "Storage.TableCatalog must not discover table contracts by scanning runtime source files"},
    {~r/(?:^|[,{(\[])\s*(?:columns|indexes|projection|derive_fields|upsert_replace_columns|sql|ddl)\s*:/m,
     "Storage.TableCatalog must not own subsystem schema, SQL, projection, index, or upsert details"},
    {~r/(?:^|[,{(\[])\s*\"(?:columns|indexes|projection|derive_fields|upsert_replace_columns|sql|ddl)\"\s*=>/m,
     "Storage.TableCatalog must not own subsystem schema, SQL, projection, index, or upsert details"}
  ]

  @forbidden_root_config_legacy_catalog_patterns [
    {~r/\bSymphonyElixir\.(?:StorageCatalog|WorkflowExtensionCatalog|CapabilityCatalog)\b/, "root config must use unified AssemblyCatalog modules instead of legacy per-mechanism catalog namespaces"}
  ]

  @forbidden_structured_execution_plan_business_evidence_patterns [
    {~r/\bPayloads\.ChangeProposal\b|payloads\/change_proposal|repo_(?:create_or_update_change_proposal|change_proposal_snapshot|read_change_proposal(?:_checks|_discussion)?)|tracker_attach_change_proposal|\bchange_proposal(?:[._][a-z0-9_]+)?\b/,
     "Workflow.StructuredExecutionPlan platform core and tests must keep Coding PR Delivery evidence vocabulary under Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan"}
  ]

  @coding_pr_delivery_structured_plan_evidence_binding_facade_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/structured_execution_plan/evidence_binding.ex"
  @coding_pr_delivery_structured_plan_evidence_binding_evidence_kind_contract_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/structured_execution_plan/evidence_binding/contract/evidence_kind.ex"
  @coding_pr_delivery_completion_validator_facade_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/completion_validator.ex"
  @coding_pr_delivery_completion_validator_evidence_reader_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/completion_validator/evidence_reader.ex"
  @coding_pr_delivery_completion_validator_profile_defaults_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/host_adapters/completion_validator/profile_defaults.ex"
  @coding_pr_delivery_profile_facade_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/profile.ex"

  @forbidden_coding_pr_delivery_structured_plan_evidence_binding_facade_patterns [
    {~r/"(?:repo_create_or_update_change_proposal|repo_change_proposal_snapshot|repo_read_change_proposal_checks|repo_read_change_proposal_discussion|tracker_attach_change_proposal|data|changeProposal|provider_kind|action_required|\/compare\/)"/,
     "CodingPrDelivery structured-plan EvidenceBinding facade must delegate evidence vocabulary, raw payload keys, status values, and URL markers to focused contract modules"},
    {~r/\b(?:RepoProviderCapabilities|TrackerCapabilities|Metadata|RawInput|CheckStatus)\b/,
     "CodingPrDelivery structured-plan EvidenceBinding facade must delegate tool/capability mapping and payload normalization to focused submodules"}
  ]

  @forbidden_coding_pr_delivery_structured_plan_evidence_binding_contract_patterns [
    {~r/"(?:data|changeProposal|provider_kind|action_required|\/compare\/|url|status|head_sha|linked_to_tracker)"/,
     "CodingPrDelivery structured-plan EvidenceBinding.Contract.EvidenceKind must stay evidence-kind only; raw payload, normalized payload, status, and URL vocabulary belong to focused sibling contracts"},
    {~r/\b(?:RawPayloadContract|PayloadContract|StatusContract|UrlContract|RawInput|CheckStatus|EvidenceContract|StateTransitionReadiness\.Contract\.Values)\b|\bContract\.(?:RawPayload|Payload|Status|Url|Tool)\b/,
     "CodingPrDelivery structured-plan EvidenceBinding.Contract.EvidenceKind must not depend on payload, status, URL, or payload-normalization contracts"}
  ]

  @forbidden_coding_pr_delivery_completion_validator_facade_patterns [
    {~r/^\s*defp\s+/m, "CodingPrDelivery CompletionValidator facade must stay a thin registered behaviour implementation without private helper logic"},
    {~r/\b(?:Contract|EvidenceContract|Values|ReadinessContract|RouteRef|IssueContext|WorkflowLifecycle|ProfileRegistry)\b/,
     "CodingPrDelivery CompletionValidator facade must delegate check vocabulary, evidence reading, result envelopes, profile/route parsing, and lifecycle predicates to focused completion-validator submodules"},
    {~r/\b(?:change_proposal_exists\?|change_proposal_linked_to_tracker\?|commit_or_diff_exists\?|checks_read_and_recorded\?|tracker_workpad_written\?|change_proposal_approved\?|checks_passing\?|merge_capability_available\?|tracker_merge_state_observed\?)\b/,
     "CodingPrDelivery CompletionValidator facade must delegate predicate rules to CompletionValidator.Checks"},
    {~r/\b(?:map_field|deep_field|workflow_value|settings_profile|completion_contract|completion_route|issue_route_key|truthy\?|present_string\?|non_empty_list\?|capability_set|string_list|normalize_string|normalize_map)\b/,
     "CodingPrDelivery CompletionValidator facade must delegate input normalization and evidence access to CompletionValidator.EvidenceReader"},
    {~r/"(?:change_proposal_exists|change_proposal_linked_to_tracker|commit_or_diff_exists|checks_read_and_recorded|tracker_workpad_written|completion_route_allowed|change_proposal_approved|checks_passing|merge_capability_available|tracker_merge_state_observed|linked change proposal exists|change proposal is attached or linked to the tracker issue|commit or diff evidence exists|CI\/check evidence was read and recorded|tracker workpad\/comment was written|required human approval is present|required CI\/checks passed|merge capability is available)"/,
     "CodingPrDelivery CompletionValidator facade must delegate check ids and required-evidence strings to CompletionValidator.Contract"},
    {~r/"(?:allowed_completion_routes|changeProposal|linkedIssue|change_proposal\.url|data\.changeProposal\.url|data\.attachment\.id|attachment\.id|tracker\.change_proposal_attached|repo\.commits|repo\.diff_present|repo\.head_sha|checks\.passing|checks\.read|tracker\.workpad_written|review\.approved|merge_capability\.available|tracker\.merge_state|route=)"/,
     "CodingPrDelivery CompletionValidator facade must delegate raw evidence keys and observed-evidence labels to CompletionValidator.EvidenceContract"},
    {~r/"(?:passing|passed|success|successful|approved|approval|true|yes|merging)"/,
     "CodingPrDelivery CompletionValidator facade must delegate status aliases and route values to CompletionValidator.Values"},
    {~r/\bRepoProviderCapabilities\b|\bSymphonyElixir\.RepoProvider\.Capabilities\b/,
     "CodingPrDelivery CompletionValidator facade must delegate provider capability binding to CompletionValidator.Values"}
  ]

  @forbidden_coding_pr_delivery_profile_facade_patterns [
    {~r/^\s*defp\s+/m, "CodingPrDelivery Profile facade must stay a thin Workflow.Profile implementation without private helper logic"},
    {~r/\b(?:AgentCapabilities|RepoCapabilities|RepoProviderCapabilities|TrackerCapabilities|WorkflowLifecycle|WorkflowProfileOptions|ProfileOptions)\b/,
     "CodingPrDelivery Profile facade must delegate capability, lifecycle, and option-schema details to focused Profile.* submodules"},
    {~r/@(?:default_policy_by_route_key|lifecycle_phase_by_route_key|completion_contract_base|requirements_option_key|change_proposal_checks_options_schema)\b/,
     "CodingPrDelivery Profile facade must not own route policy, completion-contract, or option-schema internals"}
  ]

  @forbidden_root_config_concrete_workflow_extension_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions(?:\.|\b)|\bWorkflow\.Extensions(?:\.|\b)/,
     "root config must register workflow extension assembly sources, not modules under the workflow extension business namespace"},
    {~r/\bSymphonyElixir\.Workflow\.Extensions\.CodingPrDelivery(?:\.|\b)|\bCodingPrDelivery(?:\.|\b)/,
     "root config must register workflow extension sources, not concrete workflow business extension modules"}
  ]

  @forbidden_platform_workflow_template_asset_patterns [
    {~r/\b(?:CodingPrDelivery|Coding PR Delivery|KnownTarget|ReviewHandoff)\b|\bcoding_pr_delivery\b|\bchange_proposal\b/,
     "platform workflow template assets must stay extension-neutral; concrete workflow template assets belong under priv/workflow_extensions/<extension>/templates"}
  ]

  @forbidden_tracker_skill_concrete_extension_patterns [
    {~r/\b(?:CodingPrDelivery|Coding PR Delivery|KnownTarget|Reconciliation|ReviewHandoff)\b|\bcoding_pr_delivery\b|\bchange_proposal\b/,
     "tracker skills must stay tracker-neutral and must not name concrete workflow extensions or extension-owned reference kinds"}
  ]

  @forbidden_workflow_extension_storage_patterns [
    {~r/\bSymphonyElixir\.Storage\.Repo\b|\bStorage\.Repo\b|\bEcto\./, "workflow runtime extensions must use Workflow.Extension.StateStore, not physical storage APIs"},
    {~r/\bSQLite\b|\bsqlite_path\b|\bsql_fragment\b|\btransaction_sql\b|\brepo_module\b/i, "workflow runtime extensions must not depend on database-specific details"},
    {~r/\bSymphonyElixir\.Workflow\.Extension\.StateStore\.(?:MemoryBackend|Storage)\b|\bStateStore\.(?:MemoryBackend|Storage)\b/,
     "workflow runtime extensions must use the StateStore facade, not state-store backend modules"}
  ]

  @forbidden_workflow_extension_runtime_contract_callback_patterns [
    {~r/@callback\s+(?:operator_commands|tool_result_recorders|readiness_policies|readiness_evidence_recorders|readiness_evidence_providers|structured_execution_plan_evidence_binding_providers|completion_validators|profiles|template_entries|children|typed_tool_failure_retry_policies|typed_tool_failure_resource_identity)\b/,
     "Workflow.Extension must remain the minimal runtime contract; optional static contributions belong in Workflow.Extension.ContributionCallbacks or future manifest projection"}
  ]

  @forbidden_workflow_extension_state_store_facade_patterns [
    {~r/^\s*def\s+reset\s*\(/m, "Workflow.Extension.StateStore facade must not expose destructive reset operations"},
    {~r/\bApplication\.get_env\b/, "Workflow.Extension.StateStore facade must delegate app config shape validation to StateStore.Config"},
    {~r/\bStorage\.Backend\b|\bStorage\.Config\b/, "Workflow.Extension.StateStore facade must delegate backend selection and validation to StateStore.BackendSelector"},
    {~r/\b(?:MemoryBackend|SQLiteBackend)\b/, "Workflow.Extension.StateStore facade must not reference concrete backend modules directly"},
    {~r/\bErrorCodes\b|\bDiagnostics\b/, "Workflow.Extension.StateStore facade must delegate bounded error construction to StateStore.Error"},
    {~r/\bSymphonyElixir\.Storage\.Repo\b|\bStorage\.Repo\b|\bEcto\./, "Workflow.Extension.StateStore facade must not depend on physical Repo/Ecto APIs"},
    {~r/\bsqlite_path\b|\bsql_fragment\b|\btransaction_sql\b/i, "Workflow.Extension.StateStore facade must not expose database-specific option vocabulary"}
  ]

  @forbidden_workflow_extension_diagnostics_patterns [
    {~r/^\s*(?:alias|import|require|use)\s+/m, "Workflow.Extension.Diagnostics must stay a pure platform helper without domain aliases/imports/use"},
    {~r/\bSymphonyElixir\.Workflow\.Extensions(?:\.|\b)|\bWorkflow\.Extensions(?:\.|\b)|\b(?:CodingPrDelivery|KnownTarget|Reconciliation|ReviewHandoff)\b/,
     "Workflow.Extension.Diagnostics must not depend on concrete workflow extension business modules or vocabulary"},
    {~r/\bSymphonyElixir\.(?:Tracker|RepoProvider|AgentProvider|Repo|Orchestrator|Storage)(?:\.|\b)|\b(?:Tracker|RepoProvider|AgentProvider|Orchestrator|Storage\.Repo|Ecto|SQLite)\b/,
     "Workflow.Extension.Diagnostics must not depend on provider, tracker, orchestrator, repo, or storage domains"},
    {~r/\b(?:change_proposal|tool_name|tool_id|schema_id|payload_schema|payload_json|provider_kind|tracker_issue|repo_provider)\b/i,
     "Workflow.Extension.Diagnostics must not own plugin/provider payload, schema, source, or tool vocabulary"},
    {~r/Exception\.message\(/, "Workflow.Extension.Diagnostics must not expose exception messages"},
    {~r/inspect\(\s*(?:value|reason|payload|result|arguments|attrs|opts|term)\s*\)/, "Workflow.Extension.Diagnostics must not inspect raw runtime, extension, provider, or plugin values"}
  ]

  @forbidden_tool_result_recorder_mechanism_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions(?:\.|\b)|\bCodingPrDelivery(?:\.|\b)|\bKnownTarget(?:\.|\b)|\bReconciliation(?:\.|\b)/,
     "tool-result-recorder platform mechanisms must not depend on concrete workflow extension business modules"},
    {~r/\bSymphonyElixir\.(?:Tracker|RepoProvider|Repo|Orchestrator)\b|\b(?:Tracker|RepoProvider|Orchestrator)\./,
     "tool-result-recorder platform mechanisms must not depend on provider, tracker, repo-provider, or orchestrator domains"},
    {~r/\bSymphonyElixir\.Storage\.Repo\b|\bStorage\.Repo\b|\bEcto\.|\bSQLite\b/i, "tool-result-recorder platform mechanisms must not depend on physical storage APIs"},
    {~r/Exception\.message\(/, "tool-result-recorder platform mechanisms must not expose exception messages; use bounded exception/type diagnostics"}
  ]

  @forbidden_workflow_extension_orchestrator_patterns [
    {~r/\bSymphonyElixir\.Orchestrator\.(?:BlockedResourceRegistry|State|PollCycle|Runtime|Running|Dispatch)\b/,
     "workflow runtime extensions must emit typed runtime commands or use workflow contracts instead of direct Orchestrator internals"}
  ]

  @forbidden_state_transition_readiness_concrete_extension_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions(?:\.|\b)|\bWorkflow\.Extensions(?:\.|\b)|\bCodingPrDelivery(?:\.|\b)|\bPolicies\.CodingPrDelivery(?:\.|\b)/,
     "StateTransitionReadiness platform mechanisms must not depend on concrete workflow extension readiness policy modules"},
    {~r/"(?:change_proposal|linked_to_tracker|provider_kind|repository|number|no_code_change|code_change|published_head_sha|commits|change_kind)"/,
     "StateTransitionReadiness platform contracts must not own Coding PR Delivery or repo review-handoff evidence vocabulary"}
  ]

  @forbidden_structured_plan_review_handoff_facade_patterns [
    {~r/\bSymphonyElixir\.Workflow\.StructuredExecutionPlan\.Store\b|\bStructuredExecutionPlan\.Store\b|\bStore\.(?:fetch|active_plan)\b/,
     "StructuredPlanReviewHandoff facade must read plans through its Plan.Reader port, not the canonical store directly"},
    {~r/defp\s+(?:fetch_plan|plan_scope_check|category_check|critical_items|observed_plan|observed_category|latest_repo_head|latest_repo_change_at|payload_head|parse_datetime)\b/,
     "StructuredPlanReviewHandoff facade must delegate reader, scope, category, and observed-evidence details to focused submodules"}
  ]

  @structured_plan_review_handoff_context_boundary_dir "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/structured_plan_review_handoff"

  @structured_plan_review_handoff_context_boundary_allowed_files [
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/structured_plan_review_handoff/context.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/structured_plan_review_handoff/options.ex"
  ]

  @forbidden_structured_plan_review_handoff_raw_context_patterns [
    {~r/\bString\.to_existing_atom\b|\bAtom\.to_string\s*\(\s*key\s*\)/, "StructuredPlanReviewHandoff raw atom/string compatibility must stay in Context/Options boundary modules"},
    {~r/\bKeyword\.get\s*\(\s*opts\s*,\s*:(?:run_id|issue_key|tool_context|workflow_scope|structured_plan_reader|structured_plan_reader_opts|gates)\b/,
     "StructuredPlanReviewHandoff rule modules must receive normalized context instead of reading raw option keys"}
  ]

  @review_handoff_validator_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/review_handoff/validator.ex"

  @forbidden_review_handoff_validator_raw_context_patterns [
    {~r/\bKeyword\.get\s*\(\s*opts\b/, "ReviewHandoff.Validator must consume ReviewHandoff.Context instead of reading raw option keys"}
  ]

  @structured_plan_reader_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/structured_plan_review_handoff/plan/reader.ex"

  @forbidden_structured_plan_reader_legacy_store_patterns [
    {Regex.compile!("\\bstructured_" <> "execution_plan_store\\b"), "StructuredPlanReviewHandoff.Plan.Reader must use structured_plan_reader_opts instead of top-level plan store injection"}
  ]

  @review_handoff_evidence_store_port_files [
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/review_handoff/evidence_source.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/review_handoff/evidence_recorder.ex",
    "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/review_handoff/evidence_recorder/payloads/issue_keys.ex"
  ]

  @forbidden_review_handoff_direct_readiness_store_patterns [
    {~r/\bSymphonyElixir\.Workflow\.StateTransitionReadiness\.Store\b|\bStateTransitionReadiness\.Store\b|\bStore\.(?:record|snapshot|scope_issue_keys)\b/,
     "ReviewHandoff evidence logic must use CodingPrDelivery.Readiness.EvidenceStore instead of the platform readiness store directly"}
  ]

  @typed_tool_failure_policy_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/typed_tool_failure_policy.ex"

  @forbidden_typed_tool_failure_policy_resource_identity_patterns [
    {~r/@(?:change_proposal_resource_kind|pr_url_key|pull_request_url_key|url_key|reference_kind_atom_key|external_id_atom_key|url_atom_key)\b|"(?:change_proposal|pr_url|pull_request_url)"|:(?:reference_kind|external_id)\b/,
     "TypedToolFailurePolicy must use Readiness.ResourceIdentityContract for resource identity vocabulary"}
  ]

  @review_handoff_remediation_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/review_handoff/remediation.ex"
  @review_handoff_remediation_dir "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/review_handoff/remediation"
  @review_handoff_remediation_capabilities_file "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/review_handoff/remediation/capabilities.ex"

  @forbidden_review_handoff_remediation_patterns [
    {~r/\bSymphonyElixir\.(?:Tracker|Repo|RepoProvider)\.Capabilities\b|\b(?:TrackerCapabilities|RepoCapabilities|RepoProviderCapabilities)\b/,
     "ReviewHandoff.Remediation must consume capability provider categories instead of directly binding domain capability modules"}
  ]

  @coding_pr_delivery_reconciliation_producer_dir "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/producer"
  @coding_pr_delivery_reconciliation_producer_config_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/producer/config.ex"
  @coding_pr_delivery_reconciliation_producer_defaults_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/host_adapters/reconciliation/producer_defaults.ex"
  @coding_pr_delivery_tracker_tool_result_handler_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/producer/tracker_tool_result_handler.ex"
  @coding_pr_delivery_known_target_watcher_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/producer/watcher.ex"
  @coding_pr_delivery_startup_backlog_bootstrap_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/producer/startup_backlog_bootstrap.ex"

  @coding_pr_delivery_tracker_tool_result_handler_line_limit 70
  @coding_pr_delivery_known_target_watcher_line_limit 110
  @coding_pr_delivery_startup_backlog_bootstrap_line_limit 80

  @forbidden_coding_pr_delivery_producer_diagnostic_patterns [
    {~r/\bException\.message\s*\(/, "Coding PR Delivery producer diagnostics must use bounded exception/type fields instead of exception messages"},
    {~r/\binspect\s*\(/, "Coding PR Delivery producer diagnostics must not inspect raw provider, registry, command, payload, or option values"}
  ]

  @forbidden_coding_pr_delivery_producer_payload_compatibility_patterns [
    {~r/\bString\.to_existing_atom\b|\bmap_get_existing_atom\b/, "Coding PR Delivery producer raw payload adapters must consume canonical string-key payloads instead of atom/string compatibility"}
  ]

  @forbidden_coding_pr_delivery_producer_config_patterns [
    {~r/\bApplication\.get_env\b/, "Coding PR Delivery producer modules must read application config through Producer.Config"},
    {~r/:(?:coding_pr_delivery_known_target_watcher|coding_pr_delivery_startup_backlog_bootstrap)\b/, "Coding PR Delivery producer app-env keys must stay centralized in Producer.Config"}
  ]

  @forbidden_coding_pr_delivery_producer_default_port_patterns [
    {~r/\bSymphonyElixir\.(?:Config|Tracker|RepoProvider|Observability)(?:\.|\b)/,
     "Coding PR Delivery producer platform facade defaults must stay centralized in HostAdapters.Reconciliation.ProducerDefaults"},
    {~r/\b(?:Config\.settings|Tracker\.(?:fetch|dynamic_tools|normalize)|RepoProvider\.|ObservabilityLogger\.)/,
     "Coding PR Delivery producer modules must call platform facade defaults through HostAdapters.Reconciliation.ProducerDefaults or injected deps"}
  ]

  @forbidden_coding_pr_delivery_producer_facade_patterns [
    {~r/\bSymphonyElixir\.(?:Config|Issue|Tracker|RepoProvider|Observability)(?:\.|\b)/,
     "Coding PR Delivery producer facades must delegate platform/provider/observability integration to focused producer submodules"},
    {~r/\bSymphonyElixir\.Workflow\.Extension\.Runtime\.Command\b|\bRuntimeCommand\b/, "Coding PR Delivery producer facades must delegate runtime command emission to Watcher.Commands"},
    {~r/\b(?:Inbox|ProviderFacts|ObservationProjection|RouteContext|TrackerCallOptions|ReferenceExtractor|RepoConfig|TrackerConfig|Issue|ReconciliationConfig)\b/,
     "Coding PR Delivery producer facades must not own producer business rules, provider facts, payload projection, or event construction"}
  ]

  @forbidden_coding_pr_delivery_reconciliation_config_schema_literals [
    {~r/"(?:workflow|profile|reconciliation|tracker|lifecycle|policy_by_route_key|change_proposal|enabled|candidates|gates|outcome_routes|thresholds|discovery|source_routes|max_processed_issues_per_cycle|approval_required|passing_checks_required|mergeable_required|ready|changes_requested|failed_checks|already_merged|failed_checks_confirmation_count|source_route_scan|runtime_targeted|merging|rework|done)"/,
     "Coding PR Delivery reconciliation config schema strings must stay centralized in Reconciliation.Config.Contract"}
  ]

  @forbidden_coding_pr_delivery_reconciliation_facade_patterns [
    {~r/^\s*defp\s+/m, "Reconciliation facade must stay thin and must not own private KnownTarget registration, event, command, or producer helpers"},
    {~r/\b(?:ObservabilityLogger|RuntimeCommand|KnownTargetClock)\b|\bSymphonyElixir\.Observability\b/, "Reconciliation facade must not bind host observability, runtime commands, or clock details"},
    {~r/\bKnownTarget\.Registry\b|\bInbox\.enqueue_issue_ids\b|\bProducer\.Watcher\.run_once\b/, "Reconciliation facade must delegate registry, inbox, and producer use cases to focused submodules"},
    {~r/\bContract\.(?:event|producer)\b|\b(?:candidate_enqueue_dropped|release_blocked_issue|known_target_updated)\b/,
     "Reconciliation facade must not own event, producer, or runtime-command vocabulary"},
    {~r/\bKeyword\.(?:get|fetch|get_lazy|put|drop)\(/, "Reconciliation facade must delegate option normalization to focused use-case modules"}
  ]

  @forbidden_coding_pr_delivery_reconciliation_config_facade_patterns [
    {~r/^\s*defp\s+/m, "Reconciliation.Config must stay a facade/value object and must not own private parser, validator, route, or source helpers"},
    {~r/\b(?:RoutePolicy|WorkflowLifecycle|TrackerConfig)\b/, "Reconciliation.Config must delegate route semantics and settings source extraction to Config.Routes and Config.Source"},
    {~r/\bRouteRef\.new\s*\(/, "Reconciliation.Config must delegate route parsing to Config.Routes"}
  ]

  @forbidden_coding_pr_delivery_reconciliation_contract_facade_patterns [
    {~r/^\s*defp\s+/m, "Reconciliation.Contract must stay a facade and must not own private event, producer, status, capability, or reason helpers"},
    {~r/\bTrackerCapabilities\b|\bSymphonyElixir\.Tracker\.Capabilities\b/, "Reconciliation.Contract must delegate tracker capability binding to Contract.Capabilities"},
    {~r/^\s*@(?!type\b|spec\b|moduledoc\b)(?:component|.*producer|.*event|.*status)\b/m, "Reconciliation.Contract facade must not own component, producer, event, or status constants"}
  ]

  @forbidden_coding_pr_delivery_reconciliation_contract_capability_patterns [
    {~r/\bTrackerCapabilities\b|\bSymphonyElixir\.Tracker\.Capabilities\b/, "Reconciliation tracker capability binding must stay centralized in Contract.Capabilities"}
  ]

  @forbidden_coding_pr_delivery_reconciliation_contract_event_patterns [
    {~r/:change_proposal_(?:tracker_tool_result_ignored|candidate_enqueue_dropped|candidate_suspended|known_target_watcher_failed|startup_backlog_bootstrap_completed|reconciliation_config_invalid|reconciliation_started|reconciliation_completed|reconciliation_candidate_selected|reconciliation_candidate_skipped|located|lookup_failed|reconciliation_decision|transition_attempted|transition_failed|transition_skipped|transition_succeeded)\b/,
     "Reconciliation event ids must stay centralized in Contract.Events"}
  ]

  @forbidden_coding_pr_delivery_reconciliation_contract_producer_patterns [
    {~r/"(?:change_proposal_reconciliation|tracker_tool_result|known_target_watcher|known_target_registry|startup_backlog_bootstrap)"/,
     "Reconciliation component and producer names must stay centralized in Contract.Producers"}
  ]

  @forbidden_coding_pr_delivery_reconciliation_contract_status_patterns [
    {~r/"(?:ok|tracker_error|error|skipped)"/, "Reconciliation status strings must stay centralized in Contract.Statuses"}
  ]

  @forbidden_coding_pr_delivery_reconciliation_event_field_patterns [
    {~r/^\s*(?:component|tracker_kind|issue_id|issue_identifier|running_count|claimed_count|available_slots|max_concurrent_agents|workflow_profile_kind|workflow_profile_version|source_route_refs|source_states|source_state|source_workflow_profile|source_workflow_profile_version|source_workflow_route_key|target_workflow_profile|target_workflow_profile_version|target_workflow_route_key|repo_provider_kind|repository|change_proposal_number|change_proposal_url|change_proposal_branch|head_sha|provider_state|review_summary|check_summary|mergeability_summary|retryable|error|decision|reason|skip_reason|lookup_failure_reason)\s*:/m,
     "Reconciliation event field atom keys must stay centralized in Reconciliation.Events.Fields"},
    {~r/^\s*"(?:workflow_profile|workflow_profile_version|workflow_route_key)"\s*=>/m, "Reconciliation route-ref event string keys must stay centralized in Reconciliation.Events.Fields"}
  ]

  @forbidden_coding_pr_delivery_reconciliation_events_facade_patterns [
    {~r/\bObservabilityLogger\b|\bSymphonyElixir\.Observability\b/, "Reconciliation.Events facade must emit through Reconciliation.Events.Emitter instead of binding host Observability"},
    {~r/\b(?:RepoProvider|TrackerConfig|RuntimeProjection|ProfileRegistry|KnownTargetReference)\b|\bSymphonyElixir\.(?:RepoProvider|Tracker\.Config)\b|\bSymphonyElixir\.Workflow\.(?:Extension\.Runtime\.Projection|ProfileRegistry)\b|\bKnownTarget\.Reference\b/,
     "Reconciliation.Events facade must delegate base/runtime/profile/provider and change-proposal field projection to focused Events.* field modules"},
    {~r/\b(?:IssueContext|RouteRef)\b|\bSymphonyElixir\.Workflow\.(?:IssueContext|RouteRef)\b/,
     "Reconciliation.Events facade must delegate route reference projection to Reconciliation.Events.RouteFields"},
    {~r/\bdefp\s+(?:source_route_fields|target_route_fields|route_ref|profile_context|issue_workflow_profile\?|prefixed_route_ref_fields|route_ref_map|route_key_name)\b/,
     "Reconciliation.Events facade must keep route field projection in Reconciliation.Events.RouteFields"},
    {~r/\bdefp\s+(?:event_fields|tracker_kind|profile_fields|issue_id|issue_identifier|running_count|claimed_count|available_slots_for_event|max_concurrent_agents_for_event|running_count_for_slots|change_proposal_reference_fields|reference_value|decision_fields|normalize_transition_fields)\b/,
     "Reconciliation.Events facade must keep horizontal field projection in Reconciliation.Events.BaseFields or Reconciliation.Events.ChangeProposalFields"},
    {~r/\binspect\s*\(/, "Reconciliation.Events facade must keep public error formatting in Reconciliation.Events.Diagnostics"}
  ]

  @forbidden_coding_pr_delivery_provider_facts_contract_literals [
    {~r/"(?:number|url|headRefName|headRefOid|merged|mergedAt|state|mergeable|mergeStateStatus|user|submitted_at|created_at|login|open|closed|changes_requested|approved|conflicting|dirty|blocked|draft|clean|has_hooks|unstable|unknown|Z|\+00:00)"/,
     "ProviderFacts provider payload keys, state tokens, mergeability tokens, and timestamp vocabulary must stay centralized in ProviderFacts.Contract"}
  ]

  @forbidden_coding_pr_delivery_provider_facts_facade_patterns [
    {~r/\bRepoProvider\.(?:pr_view|pr_issue_comments|pr_review_comments|pr_reviews|pr_checks)\b/, "ProviderFacts facade must delegate provider calls to ProviderFacts.Client"},
    {~r/\b(?:LandWatch|Checks|Reviews)\b/, "ProviderFacts facade must delegate summary logic to ProviderFacts.Summary"},
    {~r/\bContract\.payload_key\b|\bfield_value\b|\bnormalize_token\b/, "ProviderFacts facade must delegate provider payload extraction to ProviderFacts.Payload"},
    {~r/\bKeyword\.get\(\s*opts\b|\bKeyword\.keyword\?\(\s*opts\b/, "ProviderFacts facade must delegate option validation to ProviderFacts.Options"},
    {~r/\b(?:rescue|catch)\b/, "ProviderFacts facade must delegate callback exception handling to ProviderFacts.Client"}
  ]

  @forbidden_coding_pr_delivery_provider_facts_client_diagnostic_patterns [
    {~r/\bException\.message\s*\(/, "ProviderFacts.Client must not expose callback exception messages in public facts errors"},
    {~r/\binspect\s*\(\s*(?:reason|other|payload)\s*\)/, "ProviderFacts.Client must use bounded type diagnostics instead of inspecting callback reasons or payloads"}
  ]

  @forbidden_coding_pr_delivery_provider_facts_summary_patterns [
    {~r/\bRepoProvider\.LandWatch\b|\bLandWatch\b/,
     "ProviderFacts.Summary must own reconciliation summary semantics or depend on public provider-neutral contracts, not RepoProvider.LandWatch internals"}
  ]

  @forbidden_coding_pr_delivery_one_shot_deps_patterns [
    {~r/\b(?:Tracker|EventStore|Templates|KnownTarget|RuntimeProjection|RuntimeContext)\b|\bSymphonyElixir\.Config\b|\bWorkflow\.(?:workflow_file_path|set_workflow_file_path|clear_workflow_file_path)\b/,
     "OneShot.Deps must stay a host-deps contract/validator; host facade assembly belongs in HostAdapters.Reconciliation.OneShotHostDeps"},
    {~r/\b(?:Application|System|File)\./, "OneShot.Deps must not perform host runtime IO or process assembly"}
  ]

  @forbidden_coding_pr_delivery_one_shot_host_deps_patterns [
    {~r/\bConfig\.from_settings\b|\bDecision\b|\bTransition\b|\bProviderFacts\b|\bRouteContext\b/, "OneShot host adapter must not own reconciliation business rules"}
  ]

  @forbidden_coding_pr_delivery_reconciler_facade_patterns [
    {~r/\bSymphonyElixir\.(?:Tracker|Observability|RepoProvider)(?:\.|\b)|\b(?:Tracker|ObservabilityLogger|RepoProvider)\b/,
     "Reconciler facade must access platform/provider capabilities through HostAdapters.Reconciliation.ReconcilerDefaults and Reconciler.Clients"},
    {~r/\b(?:KnownTarget|KnownTargetReference|ReferenceExtractor|ProviderFacts|Decision|Transition|Counters|TrackerCallOptions|RouteRef)\b/,
     "Reconciler facade must delegate target lookup, facts, decisions, transitions, counters, tracker options, and route refs to Reconciler.* submodules"},
    {~r/\bKeyword\.(?:get|fetch|get_lazy)\(\s*opts\b|\bKeyword\.keyword\?\(\s*opts\b/, "Reconciler facade must delegate option validation and extraction to Reconciler.Options"},
    {~r/\binspect\s*\(/, "Reconciler facade must use Reconciler.Diagnostics for bounded public error diagnostics"}
  ]

  @forbidden_coding_pr_delivery_reconciler_client_diagnostic_patterns [
    {~r/\bException\.message\s*\(/, "Reconciler.Clients must not expose callback exception messages in public diagnostics"},
    {~r/\binspect\s*\(\s*(?:reason|other|payload|result|value)\s*\)/, "Reconciler.Clients must use bounded type diagnostics instead of raw inspected callback values"}
  ]

  @forbidden_coding_pr_delivery_reconciler_default_patterns [
    {~r/\b(?:Decision|Transition|KnownTarget|ReferenceExtractor|Inbox|RouteContext|Config)\b/,
     "Reconciler host defaults must stay a platform facade adapter and must not own reconciliation business rules"}
  ]

  @coding_pr_delivery_transition_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/transition.ex"
  @coding_pr_delivery_transition_clients_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/transition/clients.ex"
  @coding_pr_delivery_transition_defaults_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/host_adapters/reconciliation/transition_defaults.ex"
  @coding_pr_delivery_transition_diagnostics_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/transition/diagnostics.ex"

  @forbidden_coding_pr_delivery_transition_facade_patterns [
    {~r/\bSymphonyElixir\.Tracker(?:\.|\b)|\bTracker\.(?:fetch|update)\b/,
     "Transition facade must access tracker capabilities through HostAdapters.Reconciliation.TransitionDefaults and Transition.Clients"},
    {~r/\bTrackerCallOptions\b/, "Transition facade must delegate tracker call option filtering to Transition.Clients"},
    {~r/\bKeyword\.(?:get|fetch|get_lazy)\(\s*opts\b|\bKeyword\.keyword\?\(\s*opts\b/, "Transition facade must delegate option validation and extraction to Transition.Options"},
    {~r/\binspect\s*\(/, "Transition facade must use Transition.Diagnostics for bounded public error diagnostics"},
    {~r/^\s*(?:error|skip_reason|target_state|previous_state)\s*:/m, "Transition event field keys must come from Reconciliation.Events.Fields"}
  ]

  @forbidden_coding_pr_delivery_transition_client_diagnostic_patterns [
    {~r/\bException\.message\s*\(/, "Transition.Clients must not expose callback exception messages in public diagnostics"},
    {~r/\binspect\s*\(\s*(?:reason|other|payload|result|value)\s*\)/, "Transition.Clients must use bounded type diagnostics instead of raw inspected callback values"}
  ]

  @forbidden_coding_pr_delivery_transition_defaults_patterns [
    {~r/\b(?:Decision|KnownTarget|ProviderFacts|RouteContext|Events|RoutePolicy)\b/, "Transition host defaults must stay a platform tracker adapter and must not own transition business rules"}
  ]

  @coding_pr_delivery_route_context_path "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/reconciliation/route_context.ex"

  @forbidden_coding_pr_delivery_route_context_tracker_lifecycle_literals [
    {~r/"(?:workflows_by_type|raw_state_by_route_key|policy_by_route_key)"/, "RouteContext must read tracker lifecycle config through Tracker.Config accessors instead of hard-coded lifecycle keys"}
  ]

  @forbidden_cli_concrete_extension_command_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions(?:\.|\b)|\bWorkflow\.Extensions(?:\.|\b)|\bCodingPrDelivery(?:\.|\b)|\bOneShot(?:\.|\b)|\bChangeProposalReconcile(?:\.|\b)/,
     "platform CLI and Mix tasks must dispatch extension operator commands through Workflow.Extension.OperatorCommand.Dispatcher and command ids, not concrete extension modules"}
  ]

  @forbidden_workflow_command_business_patterns [
    {~r/\b(?:CodingPrDelivery|ChangeProposal|ChangeProposalReconcile|OneShot|KnownTarget|PR\/MR|pull request|merge request)\b/i,
     "mix workflow.command must stay a generic operator-command host and must not contain concrete workflow business vocabulary"},
    {~r/(?:--issue\b|--template\b|--workflow\b|--confirm-state-write\b)/,
     "mix workflow.command must not understand extension-specific command arguments; owning operator commands parse their own argv"},
    {~r/\bSymphonyElixir\.(?:Workflow\.Extensions|Tracker|RepoProvider|Orchestrator|Storage\.Repo)(?:\.|\b)|\b(?:Tracker|RepoProvider|Orchestrator|Storage\.Repo|SQLite|Ecto)\b/,
     "mix workflow.command must not depend on workflow extension business, provider, orchestrator, or physical storage modules"}
  ]

  @forbidden_workflow_extension_operator_command_declaration_patterns [
    {~r/def\s+operator_commands\b(?s:.{0,500})\b(?:Application|System|File|Repo|StateStore|Storage\.Repo|Ecto|SQLite|Tracker|RepoProvider|Orchestrator)\b/,
     "workflow extension operator_commands/0 declarations must stay static module lists and must not perform IO, read runtime state, or depend on platform/provider/storage internals"}
  ]

  @forbidden_workflow_extension_registry_facade_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions(?:\.|\b)|\bWorkflow\.Extensions(?:\.|\b)|\b(?:CodingPrDelivery|ChangeProposal|KnownTarget|Reconciliation|ReviewHandoff)\b/,
     "workflow extension registry must stay concrete-extension neutral"},
    {~r/\bSymphonyElixir\.(?:CLI|Tracker|RepoProvider|Orchestrator|Storage\.Repo)(?:\.|\b)|\b(?:Mix\.Tasks|OptionParser|IO\.|Tracker|RepoProvider|Orchestrator|Storage\.Repo|Ecto|SQLite)\b/,
     "workflow extension registry must not own CLI parsing, provider integration, Orchestrator effects, or physical storage details"},
    {~r/\b(?:File\.(?:read!?|write!?|ls!?|regular\?|exists\?)|Path\.wildcard|Code\.compile_file|System\.get_env)\b/,
     "workflow extension registry must not discover extensions through runtime files or mutable process environment state"},
    {~r/\b(?:audit|permission|authorize|authentication|manifest_path|manifest_file|enable|disable|enabled_plugins|disabled_plugins)\b/i,
     "workflow extension registry must not grow audit, permission, manifest-loading, or plugin lifecycle responsibilities"}
  ]

  @forbidden_operator_command_registry_facade_patterns [
    {~r/\bSymphonyElixir\.Workflow\.Extensions(?:\.|\b)|\bWorkflow\.Extensions(?:\.|\b)|\b(?:CodingPrDelivery|ChangeProposal|KnownTarget|Reconciliation|ReviewHandoff)\b/,
     "operator-command registry must stay concrete-extension neutral"},
    {~r/\bSymphonyElixir\.(?:CLI|Tracker|RepoProvider|Orchestrator|Storage\.Repo)(?:\.|\b)|\b(?:Mix\.Tasks|OptionParser|IO\.|Tracker|RepoProvider|Orchestrator|Storage\.Repo|Ecto|SQLite)\b/,
     "operator-command registry must not own CLI parsing, provider integration, Orchestrator effects, or physical storage details"},
    {~r/\b(?:File\.(?:read!?|write!?|ls!?|regular\?|exists\?)|Path\.wildcard|Code\.compile_file|Application\.get_env|System\.get_env)\b/,
     "operator-command registry must not discover commands through runtime files or mutable environment state"},
    {~r/\b(?:audit|permission|authorize|authentication|manifest_path|manifest_file|enable|disable|enabled_plugins|disabled_plugins)\b/i,
     "operator-command registry must not grow audit, permission, manifest-loading, or plugin lifecycle responsibilities"}
  ]

  @forbidden_orchestrator_running_lifecycle_patterns [
    {~r/\bSymphonyElixir\.AgentProvider\.(?:OpenCode|Codex|ClaudeCode|CodeBuddyCode)\b/, "orchestrator running/exit lifecycle must not depend on concrete agent provider modules"},
    {~r/\b(?:OpenCode|Codex|ClaudeCode|CodeBuddyCode|Claude Code|CodeBuddy Code)\b/, "orchestrator running/exit lifecycle must stay provider-neutral"}
  ]

  @forbidden_provider_app_server_support_patterns [
    {~r/\bSymphonyElixir\.AgentProvider\.(?:Codex|ClaudeCode|OpenCode)\b/, "provider-neutral app-server support must not depend on concrete provider modules"},
    {~r/\b(?:Launcher|StreamProtocol|SessionProtocol|TurnRequests|HttpRequests|EventStream)\b/, "provider-neutral app-server support must not own provider protocol or startup modules"}
  ]

  @forbidden_platform_dependency_patterns [
    {~r/\bSymphonyElixir\.(?:Agent|AgentProvider|Workspace|Tracker|Repo|RepoProvider|Workflow|Orchestrator|Observability|Config)\b/,
     "platform modules must not depend on higher-level Symphony contexts"},
    {~r/\bSymphonyElixir\.(?:Agent|AgentProvider|Workspace|Tracker|Repo|RepoProvider|Workflow|Orchestrator|Observability|Config)\./,
     "platform modules must not depend on higher-level Symphony contexts"}
  ]

  @forbidden_platform_filename_patterns [
    {~r/(?:^|\/)(?:observability|logger|log_file|event_store|status_dashboard|redaction|formatter)(?:\/|\.ex$)/, "observability modules must stay under lib/symphony_elixir/observability"}
  ]

  @forbidden_worker_daemon_server_dependency_patterns [
    {~r/\bSymphonyElixir\.(?:Agent|AgentProvider|Tracker|Repo|RepoProvider|Workflow|Orchestrator|Workspace|Config)\b/,
     "worker daemon server modules must not depend on higher-level Symphony contexts"},
    {~r/\bSymphonyElixir\.(?:Agent|AgentProvider|Tracker|Repo|RepoProvider|Workflow|Orchestrator|Workspace|Config)\./, "worker daemon server modules must not depend on higher-level Symphony contexts"}
  ]

  @process_wide_state_test_patterns [
    {~r/Application\.(?:put_env|delete_env)\(/, "tests that mutate application env must not run async"},
    {~r/Supervisor\.(?:terminate_child|restart_child)\(/, "tests that mutate supervised application children must not run async"},
    {~r/Process\.whereis\(SymphonyElixir\.(?:Supervisor|Orchestrator|PubSub|Workflow\.Runtime\.Store)/, "tests that inspect global application process names must not run async"},
    {~r/free_port!\(/, "tests that reserve TCP ports before server startup must not run async"}
  ]

  @direct_string_mapping_patterns [
    {~r/"[A-Za-z0-9_.:-]+"\s*->\s*:[a-zA-Z_][a-zA-Z0-9_]*/, "direct string-to-atom normalization must be centralized in a named boundary map or constant"},
    {~r/"[A-Za-z0-9_.:\/-]+"\s*->\s*"[A-Za-z0-9_.:\/-]+"/, "direct string-to-string normalization must be centralized in a named boundary map or constant"}
  ]

  @top_level_source_module_files [
    {"lib/symphony_elixir/agent.ex", "SymphonyElixir.Agent"},
    {"lib/symphony_elixir/agent_provider.ex", "SymphonyElixir.AgentProvider"},
    {"lib/symphony_elixir/application.ex", "SymphonyElixir.Application"},
    {"lib/symphony_elixir/cli.ex", "SymphonyElixir.CLI"},
    {"lib/symphony_elixir/config.ex", "SymphonyElixir.Config"},
    {"lib/symphony_elixir/http_server.ex", "SymphonyElixir.HttpServer"},
    {"lib/symphony_elixir/issue.ex", "SymphonyElixir.Issue"},
    {"lib/symphony_elixir/legal_source_info.ex", "SymphonyElixir.LegalSourceInfo"},
    {"lib/symphony_elixir/orchestrator.ex", "SymphonyElixir.Orchestrator"},
    {"lib/symphony_elixir/path_safety.ex", "SymphonyElixir.PathSafety"},
    {"lib/symphony_elixir/repo.ex", "SymphonyElixir.Repo"},
    {"lib/symphony_elixir/repo_provider.ex", "SymphonyElixir.RepoProvider"},
    {"lib/symphony_elixir/specs_check.ex", "SymphonyElixir.SpecsCheck"},
    {"lib/symphony_elixir/tracker.ex", "SymphonyElixir.Tracker"},
    {"lib/symphony_elixir/workflow.ex", "SymphonyElixir.Workflow"},
    {"lib/symphony_elixir/workspace.ex", "SymphonyElixir.Workspace"}
  ]

  @namespace_path_rules [
    {"lib/symphony_elixir/config", "SymphonyElixir.Config"},
    {"lib/symphony_elixir/config/schema", "SymphonyElixir.Config.Schema"},
    {"lib/symphony_elixir/assembly_catalog", "SymphonyElixir.AssemblyCatalog"},
    {"lib/symphony_elixir/capability", "SymphonyElixir.Capability"},
    {"lib/symphony_elixir/workflow", "SymphonyElixir.Workflow"},
    {"lib/symphony_elixir/workflow/extension", "SymphonyElixir.Workflow.Extension"},
    {"lib/symphony_elixir/workflow/extensions", "SymphonyElixir.Workflow.Extensions"},
    {"lib/symphony_elixir/workflow/execution_profile_registry", "SymphonyElixir.Workflow.ExecutionProfileRegistry"},
    {"lib/symphony_elixir/workflow/profile", "SymphonyElixir.Workflow.Profile"},
    {"lib/symphony_elixir/workflow/profiles", "SymphonyElixir.Workflow.Profiles"},
    {"lib/symphony_elixir/workflow/prompt", "SymphonyElixir.Workflow.Prompt"},
    {"lib/symphony_elixir/workflow/route_policy", "SymphonyElixir.Workflow.RoutePolicy"},
    {"lib/symphony_elixir/workflow/runtime", "SymphonyElixir.Workflow.Runtime"},
    {"lib/symphony_elixir/observability", "SymphonyElixir.Observability"},
    {"lib/symphony_elixir/observability/event_store", "SymphonyElixir.Observability.EventStore"},
    {"lib/symphony_elixir/observability/log_file", "SymphonyElixir.Observability.LogFile"},
    {"lib/symphony_elixir/observability/status_dashboard", "SymphonyElixir.Observability.StatusDashboard"},
    {"lib/symphony_elixir/agent", "SymphonyElixir.Agent"},
    {"lib/symphony_elixir/agent/credential", "SymphonyElixir.Agent.Credential"},
    {"lib/symphony_elixir/agent/credential/accounts", "SymphonyElixir.Agent.Credential.Accounts"},
    {"lib/symphony_elixir/agent/credential/store", "SymphonyElixir.Agent.Credential.Store"},
    {"lib/symphony_elixir/agent/dynamic_tool", "SymphonyElixir.Agent.DynamicTool"},
    {"lib/symphony_elixir/agent/quota", "SymphonyElixir.Agent.Quota"},
    {"lib/symphony_elixir/agent/runner", "SymphonyElixir.Agent.Runner"},
    {"lib/symphony_elixir/agent/runtime", "SymphonyElixir.Agent.Runtime"},
    {"lib/symphony_elixir/agent/runtime/dynamic_tool_bridge", "SymphonyElixir.Agent.Runtime.DynamicToolBridge"},
    {"lib/symphony_elixir/agent/runtime/executor", "SymphonyElixir.Agent.Runtime.Executor"},
    {"lib/symphony_elixir/agent/runtime/worker_daemon", "SymphonyElixir.Agent.Runtime.WorkerDaemon"},
    {"lib/symphony_elixir/agent/runtime/worker_daemon/client", "SymphonyElixir.Agent.Runtime.WorkerDaemon.Client"},
    {"lib/symphony_elixir/orchestrator", "SymphonyElixir.Orchestrator"},
    {"lib/symphony_elixir/orchestrator/dispatch", "SymphonyElixir.Orchestrator.Dispatch"},
    {"lib/symphony_elixir/orchestrator/retry", "SymphonyElixir.Orchestrator.Retry"},
    {"lib/symphony_elixir/orchestrator/running", "SymphonyElixir.Orchestrator.Running"},
    {"lib/symphony_elixir/workspace", "SymphonyElixir.Workspace"},
    {"lib/symphony_elixir/repo/git", "SymphonyElixir.Repo.Git"},
    {"lib/symphony_elixir/tracker", "SymphonyElixir.Tracker"},
    {"lib/symphony_elixir/tracker/linear", "SymphonyElixir.Tracker.Linear"},
    {"lib/symphony_elixir/tracker/tapd", "SymphonyElixir.Tracker.Tapd"},
    {"lib/symphony_elixir/tracker/tapd/client", "SymphonyElixir.Tracker.Tapd.Client"},
    {"lib/symphony_elixir/tracker/tapd/comment_codec", "SymphonyElixir.Tracker.Tapd.CommentCodec"},
    {"lib/symphony_elixir/tracker/tapd/tool_executor", "SymphonyElixir.Tracker.Tapd.ToolExecutor"},
    {"lib/symphony_elixir/repo_provider", "SymphonyElixir.RepoProvider"},
    {"lib/symphony_elixir/repo_provider/cnb", "SymphonyElixir.RepoProvider.CNB"},
    {"lib/symphony_elixir/repo_provider/cnb/api_handler", "SymphonyElixir.RepoProvider.CNB.ApiHandler"},
    {"lib/symphony_elixir/repo_provider/cnb/normalizer", "SymphonyElixir.RepoProvider.CNB.Normalizer"},
    {"lib/symphony_elixir/repo_provider/cnb/pull_request_handler", "SymphonyElixir.RepoProvider.CNB.PullRequestHandler"},
    {"lib/symphony_elixir/repo_provider/github", "SymphonyElixir.RepoProvider.GitHub"},
    {"lib/symphony_elixir/repo_provider/cli", "SymphonyElixir.RepoProvider.CLI"},
    {"lib/symphony_elixir/repo_provider/command", "SymphonyElixir.RepoProvider.Command"},
    {"lib/symphony_elixir/repo_provider/invocation", "SymphonyElixir.RepoProvider.Invocation"},
    {"lib/symphony_elixir/repo_provider/land_watch", "SymphonyElixir.RepoProvider.LandWatch"},
    {"lib/symphony_elixir/repo_provider/smoke", "SymphonyElixir.RepoProvider.Smoke"},
    {"lib/symphony_elixir/repo_provider/smoke/cnb_provisioner", "SymphonyElixir.RepoProvider.Smoke.CNBProvisioner"},
    {"lib/symphony_elixir/agent_provider", "SymphonyElixir.AgentProvider"},
    {"lib/symphony_elixir/agent_provider/app_server", "SymphonyElixir.AgentProvider.AppServer"},
    {"lib/symphony_elixir/agent_provider/planned_tool_mcp_server", "SymphonyElixir.AgentProvider.PlannedToolMcpServer"},
    {"lib/symphony_elixir/agent_provider/event_summary_mapper", "SymphonyElixir.AgentProvider.EventSummaryMapper"},
    {"lib/symphony_elixir/agent_provider/claude_code", "SymphonyElixir.AgentProvider.ClaudeCode"},
    {"lib/symphony_elixir/agent_provider/claude_code/app_server", "SymphonyElixir.AgentProvider.ClaudeCode.AppServer"},
    {"lib/symphony_elixir/agent_provider/claude_code/tooling", "SymphonyElixir.AgentProvider.ClaudeCode.Tooling"},
    {"lib/symphony_elixir/agent_provider/codex", "SymphonyElixir.AgentProvider.Codex"},
    {"lib/symphony_elixir/agent_provider/codex/app_server", "SymphonyElixir.AgentProvider.Codex.AppServer"},
    {"lib/symphony_elixir/agent_provider/codex/event_summary_mapper", "SymphonyElixir.AgentProvider.Codex.EventSummaryMapper"},
    {"lib/symphony_elixir/agent_provider/codex/event_summary_mapper/methods", "SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Methods"},
    {"lib/symphony_elixir/agent_provider/open_code", "SymphonyElixir.AgentProvider.OpenCode"},
    {"lib/symphony_elixir/agent_provider/open_code/app_server", "SymphonyElixir.AgentProvider.OpenCode.AppServer"},
    {"lib/symphony_elixir/agent_provider/open_code/tooling", "SymphonyElixir.AgentProvider.OpenCode.Tooling"},
    {"lib/symphony_elixir/agent_provider/open_code/tooling/planned_tool_plugin", "SymphonyElixir.AgentProvider.OpenCode.Tooling.PlannedToolPlugin"},
    {"lib/symphony_elixir_web/observability", "SymphonyElixirWeb.Observability"},
    {"lib/symphony_worker_daemon", "SymphonyWorkerDaemon"},
    {"lib/symphony_worker_daemon/api", "SymphonyWorkerDaemon.Api"},
    {"lib/symphony_worker_daemon/protocol", "SymphonyWorkerDaemon.Protocol"},
    {"lib/symphony_worker_daemon/session", "SymphonyWorkerDaemon.Session"}
  ]

  @explicit_module_files [
    {"lib/symphony_elixir/config/schema.ex", "SymphonyElixir.Config.Schema"},
    {"lib/symphony_elixir/workflow/execution_profile_registry.ex", "SymphonyElixir.Workflow.ExecutionProfileRegistry"},
    {"lib/symphony_elixir/workflow/extension.ex", "SymphonyElixir.Workflow.Extension"},
    {"lib/symphony_elixir/workflow/profile.ex", "SymphonyElixir.Workflow.Profile"},
    {"lib/symphony_elixir/workflow/route_policy.ex", "SymphonyElixir.Workflow.RoutePolicy"},
    {"lib/symphony_elixir/observability/event_store.ex", "SymphonyElixir.Observability.EventStore"},
    {"lib/symphony_elixir/observability/log_file.ex", "SymphonyElixir.Observability.LogFile"},
    {"lib/symphony_elixir/observability/status_dashboard.ex", "SymphonyElixir.Observability.StatusDashboard"},
    {"lib/symphony_elixir/agent/credential/accounts.ex", "SymphonyElixir.Agent.Credential.Accounts"},
    {"lib/symphony_elixir/agent/credential/store.ex", "SymphonyElixir.Agent.Credential.Store"},
    {"lib/symphony_elixir/agent/dynamic_tool.ex", "SymphonyElixir.Agent.DynamicTool"},
    {"lib/symphony_elixir/agent/quota.ex", "SymphonyElixir.Agent.Quota"},
    {"lib/symphony_elixir/agent/runner.ex", "SymphonyElixir.Agent.Runner"},
    {"lib/symphony_elixir/agent/runtime/executor.ex", "SymphonyElixir.Agent.Runtime.Executor"},
    {"lib/symphony_elixir/agent/runtime/dynamic_tool_bridge.ex", "SymphonyElixir.Agent.Runtime.DynamicToolBridge"},
    {"lib/symphony_elixir/agent/runtime/worker_daemon/client.ex", "SymphonyElixir.Agent.Runtime.WorkerDaemon.Client"},
    {"lib/symphony_elixir/orchestrator/dispatch.ex", "SymphonyElixir.Orchestrator.Dispatch"},
    {"lib/symphony_elixir/orchestrator/retry.ex", "SymphonyElixir.Orchestrator.Retry"},
    {"lib/symphony_elixir/orchestrator/running.ex", "SymphonyElixir.Orchestrator.Running"},
    {"lib/symphony_elixir/tracker/tapd/client.ex", "SymphonyElixir.Tracker.Tapd.Client"},
    {"lib/symphony_elixir/tracker/tapd/comment_codec.ex", "SymphonyElixir.Tracker.Tapd.CommentCodec"},
    {"lib/symphony_elixir/tracker/tapd/tool_executor.ex", "SymphonyElixir.Tracker.Tapd.ToolExecutor"},
    {"lib/symphony_elixir/repo_provider/invocation.ex", "SymphonyElixir.RepoProvider.Invocation"},
    {"lib/symphony_elixir/repo_provider/land_watch.ex", "SymphonyElixir.RepoProvider.LandWatch"},
    {"lib/symphony_elixir/repo_provider/smoke.ex", "SymphonyElixir.RepoProvider.Smoke"},
    {"lib/symphony_elixir/repo_provider/cnb/api_handler.ex", "SymphonyElixir.RepoProvider.CNB.ApiHandler"},
    {"lib/symphony_elixir/repo_provider/cnb/normalizer.ex", "SymphonyElixir.RepoProvider.CNB.Normalizer"},
    {"lib/symphony_elixir/repo_provider/cnb/pull_request_handler.ex", "SymphonyElixir.RepoProvider.CNB.PullRequestHandler"},
    {"lib/symphony_elixir/agent_provider/claude_code/app_server.ex", "SymphonyElixir.AgentProvider.ClaudeCode.AppServer"},
    {"lib/symphony_elixir/agent_provider/claude_code/tooling.ex", "SymphonyElixir.AgentProvider.ClaudeCode.Tooling"},
    {"lib/symphony_elixir/agent_provider/planned_tool_mcp_server.ex", "SymphonyElixir.AgentProvider.PlannedToolMcpServer"},
    {"lib/symphony_elixir/agent_provider/codex/app_server.ex", "SymphonyElixir.AgentProvider.Codex.AppServer"},
    {"lib/symphony_elixir/agent_provider/codex/event_summary_mapper.ex", "SymphonyElixir.AgentProvider.Codex.EventSummaryMapper"},
    {"lib/symphony_elixir/agent_provider/open_code/app_server.ex", "SymphonyElixir.AgentProvider.OpenCode.AppServer"},
    {"lib/symphony_elixir/agent_provider/open_code/tooling.ex", "SymphonyElixir.AgentProvider.OpenCode.Tooling"},
    {"lib/symphony_elixir/agent_provider/open_code/tooling/planned_tool_plugin.ex", "SymphonyElixir.AgentProvider.OpenCode.Tooling.PlannedToolPlugin"},
    {"lib/symphony_elixir/agent_provider/settings_normalizer.ex", "SymphonyElixir.AgentProvider.SettingsNormalizer"},
    {"lib/symphony_worker_daemon/application.ex", "SymphonyWorkerDaemon.Application"},
    {"lib/symphony_worker_daemon/application/children.ex", "SymphonyWorkerDaemon.Application.Children"},
    {"lib/symphony_worker_daemon/auth/access_policy.ex", "SymphonyWorkerDaemon.Auth.AccessPolicy"},
    {"lib/symphony_worker_daemon/auth/clients.ex", "SymphonyWorkerDaemon.Auth.Clients"},
    {"lib/symphony_worker_daemon/auth/token.ex", "SymphonyWorkerDaemon.Auth.Token"},
    {"lib/symphony_worker_daemon/auth/values.ex", "SymphonyWorkerDaemon.Auth.Values"},
    {"lib/symphony_worker_daemon/capacity_manager/leases.ex", "SymphonyWorkerDaemon.CapacityManager.Leases"},
    {"lib/symphony_worker_daemon/capacity_manager/options.ex", "SymphonyWorkerDaemon.CapacityManager.Options"},
    {"lib/symphony_worker_daemon/capacity_manager/status.ex", "SymphonyWorkerDaemon.CapacityManager.Status"},
    {"lib/symphony_worker_daemon/capacity_manager/tenant_key.ex", "SymphonyWorkerDaemon.CapacityManager.TenantKey"},
    {"lib/symphony_worker_daemon/cli.ex", "SymphonyWorkerDaemon.CLI"},
    {"lib/symphony_worker_daemon/cli/arguments.ex", "SymphonyWorkerDaemon.CLI.Arguments"},
    {"lib/symphony_worker_daemon/cli/output.ex", "SymphonyWorkerDaemon.CLI.Output"},
    {"lib/symphony_worker_daemon/cli/server_spec.ex", "SymphonyWorkerDaemon.CLI.ServerSpec"},
    {"lib/symphony_worker_daemon/command_policy/allowed_executables.ex", "SymphonyWorkerDaemon.CommandPolicy.AllowedExecutables"},
    {"lib/symphony_worker_daemon/command_policy/capabilities.ex", "SymphonyWorkerDaemon.CommandPolicy.Capabilities"},
    {"lib/symphony_worker_daemon/command_policy/validation.ex", "SymphonyWorkerDaemon.CommandPolicy.Validation"},
    {"lib/symphony_worker_daemon/config/authentication.ex", "SymphonyWorkerDaemon.Config.Authentication"},
    {"lib/symphony_worker_daemon/config/listen_address.ex", "SymphonyWorkerDaemon.Config.ListenAddress"},
    {"lib/symphony_worker_daemon/config/options.ex", "SymphonyWorkerDaemon.Config.Options"},
    {"lib/symphony_worker_daemon/config/policies.ex", "SymphonyWorkerDaemon.Config.Policies"},
    {"lib/symphony_worker_daemon/config/worker_identity.ex", "SymphonyWorkerDaemon.Config.WorkerIdentity"},
    {"lib/symphony_worker_daemon/config/workspace_roots.ex", "SymphonyWorkerDaemon.Config.WorkspaceRoots"},
    {"lib/symphony_worker_daemon/bridge_proxy/port_reservation.ex", "SymphonyWorkerDaemon.BridgeProxy.PortReservation"},
    {"lib/symphony_worker_daemon/bridge_proxy/proxy_options.ex", "SymphonyWorkerDaemon.BridgeProxy.ProxyOptions"},
    {"lib/symphony_worker_daemon/bridge_proxy/requester.ex", "SymphonyWorkerDaemon.BridgeProxy.Requester"},
    {"lib/symphony_worker_daemon/bridge_proxy/router_plug.ex", "SymphonyWorkerDaemon.BridgeProxy.RouterPlug"},
    {"lib/symphony_worker_daemon/bridge_proxy/upstream_policy.ex", "SymphonyWorkerDaemon.BridgeProxy.UpstreamPolicy"},
    {"lib/symphony_worker_daemon/orphan_sweeper/ledger_recorder.ex", "SymphonyWorkerDaemon.OrphanSweeper.LedgerRecorder"},
    {"lib/symphony_worker_daemon/orphan_sweeper/process_control.ex", "SymphonyWorkerDaemon.OrphanSweeper.ProcessControl"},
    {"lib/symphony_worker_daemon/orphan_sweeper/result.ex", "SymphonyWorkerDaemon.OrphanSweeper.Result"},
    {"lib/symphony_worker_daemon/orphan_sweeper/session_candidate.ex", "SymphonyWorkerDaemon.OrphanSweeper.SessionCandidate"},
    {"lib/symphony_worker_daemon/process_runner/environment.ex", "SymphonyWorkerDaemon.ProcessRunner.Environment"},
    {"lib/symphony_worker_daemon/process_runner/stop_options.ex", "SymphonyWorkerDaemon.ProcessRunner.StopOptions"},
    {"lib/symphony_worker_daemon/rate_limiter/bucket.ex", "SymphonyWorkerDaemon.RateLimiter.Bucket"},
    {"lib/symphony_worker_daemon/rate_limiter/options.ex", "SymphonyWorkerDaemon.RateLimiter.Options"},
    {"lib/symphony_worker_daemon/rate_limiter/pruning.ex", "SymphonyWorkerDaemon.RateLimiter.Pruning"},
    {"lib/symphony_worker_daemon/workspace_manager/paths.ex", "SymphonyWorkerDaemon.WorkspaceManager.Paths"},
    {"lib/symphony_worker_daemon/api.ex", "SymphonyWorkerDaemon.Api"},
    {"lib/symphony_worker_daemon/api/audit.ex", "SymphonyWorkerDaemon.Api.Audit"},
    {"lib/symphony_worker_daemon/api/health.ex", "SymphonyWorkerDaemon.Api.Health"},
    {"lib/symphony_worker_daemon/api/rate_limit.ex", "SymphonyWorkerDaemon.Api.RateLimit"},
    {"lib/symphony_worker_daemon/api/request_limits.ex", "SymphonyWorkerDaemon.Api.RequestLimits"},
    {"lib/symphony_worker_daemon/api/request_params.ex", "SymphonyWorkerDaemon.Api.RequestParams"},
    {"lib/symphony_worker_daemon/api/response.ex", "SymphonyWorkerDaemon.Api.Response"},
    {"lib/symphony_worker_daemon/api/session_access.ex", "SymphonyWorkerDaemon.Api.SessionAccess"},
    {"lib/symphony_worker_daemon/api/session_cleanup.ex", "SymphonyWorkerDaemon.Api.SessionCleanup"},
    {"lib/symphony_worker_daemon/api/session_create.ex", "SymphonyWorkerDaemon.Api.SessionCreate"},
    {"lib/symphony_worker_daemon/api/session_options.ex", "SymphonyWorkerDaemon.Api.SessionOptions"},
    {"lib/symphony_worker_daemon/protocol.ex", "SymphonyWorkerDaemon.Protocol"},
    {"lib/symphony_worker_daemon/protocol/paths.ex", "SymphonyWorkerDaemon.Protocol.Paths"},
    {"lib/symphony_worker_daemon/protocol/query_params.ex", "SymphonyWorkerDaemon.Protocol.QueryParams"},
    {"lib/symphony_worker_daemon/protocol/request.ex", "SymphonyWorkerDaemon.Protocol.Request"},
    {"lib/symphony_worker_daemon/protocol/response.ex", "SymphonyWorkerDaemon.Protocol.Response"},
    {"lib/symphony_worker_daemon/protocol/validation.ex", "SymphonyWorkerDaemon.Protocol.Validation"},
    {"lib/symphony_worker_daemon/protocol/validation/fields.ex", "SymphonyWorkerDaemon.Protocol.Validation.Fields"},
    {"lib/symphony_worker_daemon/protocol/validation/payload.ex", "SymphonyWorkerDaemon.Protocol.Validation.Payload"},
    {"lib/symphony_worker_daemon/session/filters.ex", "SymphonyWorkerDaemon.Session.Filters"},
    {"lib/symphony_worker_daemon/session/ledger.ex", "SymphonyWorkerDaemon.Session.Ledger"},
    {"lib/symphony_worker_daemon/session/ledger/health.ex", "SymphonyWorkerDaemon.Session.Ledger.Health"},
    {"lib/symphony_worker_daemon/session/ledger/persistence.ex", "SymphonyWorkerDaemon.Session.Ledger.Persistence"},
    {"lib/symphony_worker_daemon/session/ledger/summary.ex", "SymphonyWorkerDaemon.Session.Ledger.Summary"},
    {"lib/symphony_worker_daemon/session/server.ex", "SymphonyWorkerDaemon.Session.Server"},
    {"lib/symphony_worker_daemon/session/server/events.ex", "SymphonyWorkerDaemon.Session.Server.Events"},
    {"lib/symphony_worker_daemon/session/server/options.ex", "SymphonyWorkerDaemon.Session.Server.Options"},
    {"lib/symphony_worker_daemon/session/server/payloads.ex", "SymphonyWorkerDaemon.Session.Server.Payloads"},
    {"lib/symphony_worker_daemon/session/server/provider_environment.ex", "SymphonyWorkerDaemon.Session.Server.ProviderEnvironment"},
    {"lib/symphony_worker_daemon/session/server/request.ex", "SymphonyWorkerDaemon.Session.Server.Request"},
    {"lib/symphony_worker_daemon/session/server/request_fingerprint.ex", "SymphonyWorkerDaemon.Session.Server.RequestFingerprint"},
    {"lib/symphony_worker_daemon/session/server/resource_budget.ex", "SymphonyWorkerDaemon.Session.Server.ResourceBudget"},
    {"lib/symphony_worker_daemon/session/server/status.ex", "SymphonyWorkerDaemon.Session.Server.Status"},
    {"lib/symphony_worker_daemon/session/server/timeout_policy.ex", "SymphonyWorkerDaemon.Session.Server.TimeoutPolicy"},
    {"lib/symphony_worker_daemon/session/supervisor.ex", "SymphonyWorkerDaemon.Session.Supervisor"}
  ]

  test "retired agent provider directories do not return" do
    violations =
      @retired_agent_provider_dirs
      |> Enum.flat_map(&tracked_entries/1)

    assert violations == []
  end

  test "retired agent runtime directory does not return" do
    violations =
      @retired_agent_runtime_dirs
      |> Enum.flat_map(&tracked_entries/1)

    assert violations == []
  end

  test "retired agent provider files do not return" do
    violations =
      @retired_agent_provider_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "provider-local shared app-server support files do not return" do
    violations =
      @retired_provider_app_server_support_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "retired orchestrator helper files do not return" do
    violations =
      @retired_orchestrator_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "retired tracker helper files do not return" do
    violations =
      @retired_tracker_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "retired worker daemon session files do not return" do
    violations =
      @retired_worker_daemon_session_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "bundled workspace automation flat skill directories do not return" do
    violations =
      @retired_flat_workspace_automation_skill_dirs
      |> Enum.flat_map(&tracked_entries/1)

    assert violations == []
  end

  test "retired workflow template root API files do not return" do
    violations =
      @retired_workflow_template_api_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "retired workflow extension flat runtime envelope files do not return" do
    violations =
      @retired_workflow_extension_runtime_api_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "retired workflow extension flat state-store record files do not return" do
    violations =
      @retired_workflow_extension_state_store_api_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "retired known-target registry flat admin API file does not return" do
    violations =
      @retired_known_target_registry_api_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "retired coding pr delivery reconciliation flat known-target files do not return" do
    violations =
      @retired_coding_pr_delivery_reconciliation_flat_known_target_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "retired coding pr delivery reconciliation flat candidate files do not return" do
    violations =
      @retired_coding_pr_delivery_reconciliation_flat_candidate_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "retired structured-plan review-handoff flat plan files do not return" do
    violations =
      @retired_structured_plan_review_handoff_flat_plan_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "retired coding pr delivery flat readiness evidence file does not return" do
    violations =
      @retired_coding_pr_delivery_flat_readiness_evidence_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "retired coding pr delivery structured-plan evidence binding flat contract files do not return" do
    violations =
      @retired_coding_pr_delivery_structured_plan_evidence_binding_flat_contract_files
      |> Enum.filter(&File.exists?/1)

    assert violations == []
  end

  test "workflow extension runtime envelope modules stay under runtime namespace" do
    violations =
      "lib/symphony_elixir"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_workflow_extension_flat_runtime_module_patterns))

    assert violations == []
  end

  test "workflow extension state records stay under state-store namespace" do
    violations =
      "lib/symphony_elixir"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_workflow_extension_flat_state_store_module_patterns))

    assert violations == []
  end

  test "codex production implementation stays behind agent provider boundary" do
    violations =
      "lib/symphony_elixir"
      |> source_files()
      |> Enum.reject(&codex_provider_allowed?/1)
      |> Enum.flat_map(&codex_identifier_matches/1)

    assert violations == []
  end

  test "retired agent provider display and wrapper names do not return" do
    violations =
      "lib/symphony_elixir"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_agent_provider_patterns))

    assert violations == []
  end

  test "retired bundled workspace automation path references do not return" do
    files = Enum.flat_map(@agent_automation_path_reference_files, &text_files/1)

    violations =
      Enum.flat_map(files, &retired_agent_automation_path_matches/1) ++
        Enum.flat_map(files, &forbidden_matches(&1, @forbidden_agent_automation_reference_patterns))

    assert violations == []
  end

  test "bundled workspace automation stays provider neutral" do
    violations =
      "priv/workspace_automation"
      |> text_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_agent_automation_patterns))

    assert violations == []
  end

  test "provider code consumes repo-core context instead of hardcoded git context" do
    violations =
      @provider_source_dirs
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_provider_patterns))

    assert violations == []
  end

  test "repo-provider code does not depend on concrete workflow extensions" do
    violations =
      "lib/symphony_elixir/repo_provider"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_repo_provider_workflow_extension_patterns))

    assert violations == []
  end

  test "repo-provider change proposal body fallback stays workflow-state neutral" do
    violations =
      "lib/symphony_elixir/repo_provider/change_proposal_body.ex"
      |> forbidden_matches(@forbidden_change_proposal_body_workflow_state_patterns)

    assert violations == []
  end

  test "tracker code does not depend on concrete workflow extensions" do
    violations =
      "lib/symphony_elixir/tracker"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_tracker_workflow_extension_patterns))

    assert violations == []
  end

  test "tracker does not own change proposal reference extraction" do
    violations =
      "lib/symphony_elixir/tracker"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_tracker_change_proposal_reference_patterns))

    assert violations == []
  end

  test "domain capability owners do not depend on workflow capability facade" do
    violations =
      [
        "lib/symphony_elixir/tracker",
        "lib/symphony_elixir/repo",
        "lib/symphony_elixir/repo_provider",
        "lib/symphony_elixir/agent",
        "lib/symphony_elixir/agent_provider"
      ]
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_domain_workflow_capability_facade_patterns))

    assert violations == []
  end

  test "workflow capability facade owns only workflow capability strings" do
    violations =
      "lib/symphony_elixir/workflow/capability_names.ex"
      |> forbidden_matches(@forbidden_workflow_capability_name_owner_patterns)

    assert violations == []
  end

  test "observability classifies concrete capabilities through capability registry" do
    violations =
      "lib/symphony_elixir/observability"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_observability_concrete_capability_patterns))

    assert violations == []
  end

  test "capability registry stays mechanism-only" do
    violations =
      "lib/symphony_elixir/capability"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_capability_registry_domain_source_patterns))

    assert violations == []
  end

  test "assembly capability catalog stays source-only" do
    violations =
      assembly_catalog_capability_source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_assembly_catalog_capability_patterns))

    assert violations == []
  end

  test "assembly capability catalog modules implement the source catalog behaviour" do
    violations =
      assembly_catalog_capability_source_files()
      |> Enum.flat_map(&assembly_capability_source_violations/1)

    assert violations == []
  end

  test "assembly Dynamic Tool source catalog stays source-only" do
    violations =
      assembly_catalog_dynamic_tool_source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_assembly_catalog_dynamic_tool_source_patterns))

    assert violations == []
  end

  test "assembly Dynamic Tool source catalog modules implement the source catalog behaviour" do
    violations =
      assembly_catalog_dynamic_tool_source_files()
      |> Enum.flat_map(&assembly_dynamic_tool_source_violations/1)

    assert violations == []
  end

  test "assembly catalog stays flat" do
    violations =
      assembly_catalog_source_files()
      |> Enum.reject(&(Path.dirname(&1) == "lib/symphony_elixir/assembly_catalog"))
      |> Enum.map(&"#{&1}: assembly catalog must stay a flat source-only directory")

    assert violations == []
  end

  test "root config registers capability source catalogs, not direct capability sources" do
    violations =
      "config/config.exs"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_root_config_capability_source_patterns))

    assert violations == []
  end

  test "root config registers Dynamic Tool source catalogs, not direct source modules" do
    violations =
      "config/config.exs"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_root_config_dynamic_tool_source_patterns))

    assert violations == []
  end

  test "root config uses unified assembly catalog modules" do
    violations =
      "config/config.exs"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_root_config_legacy_catalog_patterns))

    assert violations == []
  end

  test "agent provider code does not depend on platform transport or concrete tracker adapters directly" do
    violations =
      "lib/symphony_elixir/agent_provider"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_agent_provider_dependency_patterns))

    assert violations == []
  end

  test "provider-neutral app-server support keeps provider protocol code out" do
    files = source_files("lib/symphony_elixir/agent_provider/app_server")

    module_violations =
      files
      |> Enum.flat_map(&provider_app_server_support_module_violations/1)

    dependency_violations =
      files
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_provider_app_server_support_patterns))

    assert module_violations ++ dependency_violations == []
  end

  test "top-level source files stay explicitly owned" do
    expected_files =
      @top_level_source_module_files
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    violations =
      "lib/symphony_elixir/*.ex"
      |> Path.wildcard()
      |> Enum.sort()
      |> Kernel.--(expected_files)
      |> Enum.map(&"#{&1}: top-level source files must be listed in architecture ownership rules")

    assert violations == []
  end

  test "top-level source files define their owning modules" do
    violations =
      @top_level_source_module_files
      |> Enum.flat_map(fn {path, expected_module} ->
        module_name_violations(path, expected_module)
      end)

    assert violations == []
  end

  test "selected source directories use their owning module namespaces" do
    violations =
      @namespace_path_rules
      |> Enum.flat_map(fn {dir, expected_prefix} ->
        dir
        |> source_files()
        |> Enum.flat_map(&module_prefix_violations(&1, expected_prefix))
      end)

    assert violations == []
  end

  test "selected facade files keep their expected module names" do
    violations =
      @explicit_module_files
      |> Enum.flat_map(fn {path, expected_module} ->
        module_name_violations(path, expected_module)
      end)

    assert violations == []
  end

  test "agent dynamic tool core does not depend on external domain modules or legacy workflow keys" do
    violations =
      [
        "lib/symphony_elixir/agent/dynamic_tool.ex",
        "lib/symphony_elixir/agent/dynamic_tool"
      ]
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_agent_dynamic_tool_dependency_patterns))

    assert violations == []
  end

  test "agent dynamic tool core does not interpret opaque source or adoption payloads" do
    violations =
      [
        "lib/symphony_elixir/agent/dynamic_tool.ex",
        "lib/symphony_elixir/agent/dynamic_tool"
      ]
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_agent_dynamic_tool_opaque_payload_patterns))

    assert violations == []
  end

  test "orchestrator does not depend on concrete coding PR delivery modules" do
    violations =
      "lib/symphony_elixir/orchestrator"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_orchestrator_coding_pr_delivery_patterns))

    assert violations == []
  end

  test "orchestrator poll cycle invokes workflow runtime extension boundary" do
    violations =
      [
        "lib/symphony_elixir/orchestrator/poll_cycle.ex",
        "lib/symphony_elixir/orchestrator/server_options.ex"
      ]
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_orchestrator_poll_cycle_extension_bypass_patterns))

    assert violations == []
  end

  test "workflow platform core stays concrete-extension neutral" do
    violations =
      workflow_platform_source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_workflow_platform_concrete_extension_patterns))

    assert violations == []
  end

  test "workflow profile and template registries consume contributions only" do
    violations =
      workflow_profile_template_registry_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_workflow_registry_concrete_extension_patterns))

    assert violations == []
  end

  test "workflow template asset roots use OTP priv directories" do
    violations =
      workflow_template_asset_resolver_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_workflow_template_source_priv_path_patterns))

    assert violations == []
  end

  test "workflow template callers use namespaced template modules" do
    violations =
      workflow_template_legacy_api_reference_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_legacy_workflow_template_api_patterns))

    assert violations == []
  end

  test "production workflow template callers use the template facade" do
    violations =
      workflow_template_public_facade_reference_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_workflow_template_internal_api_patterns))

    assert violations == []
  end

  test "coding PR delivery extension facade stays thin" do
    violations =
      coding_pr_delivery_facade_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_facade_implementation_patterns))

    assert violations == []
  end

  test "coding PR delivery host adapters stay physically centralized" do
    violations =
      @coding_pr_delivery_dir
      |> source_files()
      |> Enum.reject(&String.starts_with?(&1, @coding_pr_delivery_host_adapters_dir))
      |> Enum.filter(fn path ->
        String.ends_with?(path, "/defaults.ex") or
          String.ends_with?(path, "/host_deps.ex") or
          String.ends_with?(path, "/state_transition_readiness_backend.ex") or
          String.ends_with?(path, "/structured_plan_reader_store_backend.ex")
      end)
      |> Enum.map(&"#{&1}: host adapter modules must live under #{@coding_pr_delivery_host_adapters_dir}")

    assert violations == []
  end

  test "coding PR delivery plugin does not reintroduce atom string key compatibility" do
    violations =
      @coding_pr_delivery_dir
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_key_compatibility_patterns))

    assert violations == []
  end

  test "concrete workflow extension references stay in extension or assembly catalog boundaries" do
    violations =
      non_extension_business_reference_source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_concrete_workflow_extension_reference_patterns))

    assert violations == []
  end

  test "legacy change-proposal runtime entrypoints do not return" do
    violations =
      non_extension_business_reference_source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_legacy_change_proposal_runtime_patterns))

    assert violations == []
  end

  test "assembly workflow extension catalog stays source-only" do
    violations =
      assembly_catalog_workflow_extension_source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_assembly_catalog_workflow_extension_patterns))

    assert violations == []
  end

  test "assembly workflow extension catalog modules implement the extension source behaviour" do
    violations =
      assembly_catalog_workflow_extension_source_files()
      |> Enum.flat_map(&assembly_workflow_extension_source_violations/1)

    assert violations == []
  end

  test "workflow extension business namespace contains only explicitly bundled extensions" do
    namespace_entries =
      @workflow_extensions_dir
      |> File.ls!()
      |> Enum.reject(&String.starts_with?(&1, "."))
      |> Enum.sort()

    unexpected_entries = namespace_entries -- @bundled_workflow_extension_namespace_entries

    assert unexpected_entries == [],
           "External workflow plugins must be independently released packages; unexpected bundled extension namespace entries: #{inspect(unexpected_entries)}"
  end

  test "bundled workflow extension catalog does not register external plugins" do
    modules = SymphonyElixir.AssemblyCatalog.WorkflowExtensions.extension_modules([])
    unexpected_modules = modules -- @bundled_workflow_extension_modules

    assert unexpected_modules == [],
           "External workflow plugins must register through their own source or manifest projection, not AssemblyCatalog.WorkflowExtensions: #{inspect(unexpected_modules)}"
  end

  test "assembly storage catalog stays source-only" do
    violations =
      assembly_catalog_storage_source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_assembly_catalog_storage_patterns))

    assert violations == []
  end

  test "assembly storage catalog modules implement the table-catalog source behaviour" do
    violations =
      assembly_catalog_storage_source_files()
      |> Enum.flat_map(&assembly_storage_source_violations/1)

    assert violations == []
  end

  test "storage table catalog facade stays domain-neutral and table-level only" do
    violations =
      storage_table_catalog_facade_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_storage_table_catalog_facade_patterns))

    assert violations == []
  end

  test "structured execution plan core keeps business evidence vocabulary extension-owned" do
    violations =
      [
        "lib/symphony_elixir/workflow/structured_execution_plan",
        "test/symphony_elixir/workflow/structured_execution_plan"
      ]
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_structured_execution_plan_business_evidence_patterns))

    assert violations == []
  end

  test "coding pr delivery structured-plan evidence binding facade stays thin" do
    violations =
      @coding_pr_delivery_structured_plan_evidence_binding_facade_path
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_structured_plan_evidence_binding_facade_patterns))

    assert violations == []
  end

  test "coding pr delivery structured-plan evidence binding contract stays evidence-kind only" do
    violations =
      @coding_pr_delivery_structured_plan_evidence_binding_evidence_kind_contract_path
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_structured_plan_evidence_binding_contract_patterns))

    assert violations == []
  end

  test "coding pr delivery completion validator facade delegates machine vocabulary to contracts" do
    violations =
      @coding_pr_delivery_completion_validator_facade_path
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_completion_validator_facade_patterns))

    assert violations == []
  end

  test "coding pr delivery completion validator keeps profile host access behind adapter" do
    evidence_reader_violations =
      @coding_pr_delivery_completion_validator_evidence_reader_path
      |> forbidden_matches([
        {~r/\bProfileRegistry\b|\bSymphonyElixir\.Workflow\.ProfileRegistry\b/,
         "CompletionValidator.EvidenceReader must resolve profile host contracts through HostAdapters.CompletionValidator.ProfileDefaults"}
      ])

    profile_defaults_violations =
      @coding_pr_delivery_completion_validator_profile_defaults_path
      |> forbidden_matches([
        {~r/\b(?:Checks|ResultBuilder|ObservedEvidence|EvidenceContract|IssueContext)\b/,
         "CompletionValidator profile defaults must stay a host profile adapter and must not own validator rules or evidence parsing"}
      ])

    assert evidence_reader_violations ++ profile_defaults_violations == []
  end

  test "coding pr delivery profile facade delegates profile internals to focused submodules" do
    violations =
      @coding_pr_delivery_profile_facade_path
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_profile_facade_patterns))

    assert violations == []
  end

  test "root config registers workflow extension sources, not concrete extension modules" do
    violations =
      "config/config.exs"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_root_config_concrete_workflow_extension_patterns))

    assert violations == []
  end

  test "platform workflow template assets stay extension-neutral" do
    retired_asset_violations =
      @retired_platform_workflow_extension_template_asset_paths
      |> Enum.filter(&File.exists?/1)
      |> Enum.map(&"#{&1}: concrete workflow template asset must live under priv/workflow_extensions/<extension>/templates")

    vocabulary_violations =
      "priv/workflow_templates"
      |> text_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_platform_workflow_template_asset_patterns))

    assert retired_asset_violations ++ vocabulary_violations == []
  end

  test "tracker skills do not name concrete workflow extensions" do
    violations =
      [
        "priv/workspace_automation/skills/tracker/linear/SKILL.md",
        "priv/workspace_automation/skills/tracker/tapd/SKILL.md"
      ]
      |> Enum.flat_map(&skill_files/1)
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_tracker_skill_concrete_extension_patterns))

    assert violations == []
  end

  test "workflow runtime extensions do not depend on physical storage APIs" do
    violations =
      "lib/symphony_elixir/workflow/extensions"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_workflow_extension_storage_patterns))

    assert violations == []
  end

  test "workflow runtime extensions do not depend on orchestrator internals" do
    violations =
      "lib/symphony_elixir/workflow/extensions"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_workflow_extension_orchestrator_patterns))

    assert violations == []
  end

  test "state-transition readiness platform code stays extension-neutral" do
    violations =
      [
        "lib/symphony_elixir/workflow/state_transition_readiness.ex",
        "lib/symphony_elixir/workflow/state_transition_readiness"
      ]
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_state_transition_readiness_concrete_extension_patterns))

    assert violations == []
  end

  test "structured-plan review-handoff policy facade stays isolated from store and rule details" do
    violations =
      "lib/symphony_elixir/workflow/extensions/coding_pr_delivery/readiness/structured_plan_review_handoff.ex"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_structured_plan_review_handoff_facade_patterns))

    assert violations == []
  end

  test "structured-plan review-handoff plan reader has no top-level store injection" do
    violations =
      @structured_plan_reader_path
      |> forbidden_matches(@forbidden_structured_plan_reader_legacy_store_patterns)

    assert violations == []
  end

  test "structured-plan review-handoff raw context normalization stays at the adapter boundary" do
    violations =
      @structured_plan_review_handoff_context_boundary_dir
      |> source_files()
      |> Enum.reject(&(&1 in @structured_plan_review_handoff_context_boundary_allowed_files))
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_structured_plan_review_handoff_raw_context_patterns))

    assert violations == []
  end

  test "review-handoff validator consumes normalized context" do
    violations =
      @review_handoff_validator_path
      |> forbidden_matches(@forbidden_review_handoff_validator_raw_context_patterns)

    assert violations == []
  end

  test "review-handoff evidence logic uses the extension-owned evidence-store port" do
    violations =
      @review_handoff_evidence_store_port_files
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_review_handoff_direct_readiness_store_patterns))

    assert violations == []
  end

  test "typed-tool failure resource identity vocabulary stays in readiness contract" do
    violations =
      @typed_tool_failure_policy_path
      |> forbidden_matches(@forbidden_typed_tool_failure_policy_resource_identity_patterns)

    assert violations == []
  end

  test "review-handoff remediation consumes capability provider boundary" do
    violations =
      @review_handoff_remediation_path
      |> forbidden_matches(@forbidden_review_handoff_remediation_patterns)

    assert violations == []
  end

  test "review-handoff remediation domain capability binding stays in bundled provider" do
    violations =
      @review_handoff_remediation_dir
      |> source_files()
      |> Enum.reject(&(&1 == @review_handoff_remediation_capabilities_file))
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_review_handoff_remediation_patterns))

    assert violations == []
  end

  test "platform CLI dispatches extension operator commands through command registry" do
    violations =
      [
        "lib/symphony_elixir/cli",
        "lib/mix/tasks/workflow.command.ex"
      ]
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_cli_concrete_extension_command_patterns))

    assert violations == []
  end

  test "workflow command Mix task remains a thin generic host" do
    violations =
      "lib/mix/tasks/workflow.command.ex"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_workflow_command_business_patterns))

    assert violations == []
  end

  test "workflow extension operator-command declarations stay static" do
    violations =
      "lib/symphony_elixir/workflow/extensions"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_workflow_extension_operator_command_declaration_patterns))

    assert violations == []
  end

  test "workflow extension registry remains a small facade" do
    line_count =
      @workflow_extension_registry_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    assert line_count <= @workflow_extension_registry_line_limit,
           "#{@workflow_extension_registry_path}: #{line_count} lines exceeds #{@workflow_extension_registry_line_limit}; extract Collector/Validator/Projection before adding more registry behavior"
  end

  test "workflow extension registry public API remains facade-only" do
    violations =
      @workflow_extension_registry_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @workflow_extension_registry_public_functions))
      |> Enum.map(&"#{@workflow_extension_registry_path}: public function #{&1}/... is outside the workflow extension registry facade API")

    assert violations == []
  end

  test "workflow extension registry stays platform-mechanism only" do
    violations =
      @workflow_extension_registry_path
      |> forbidden_matches(@forbidden_workflow_extension_registry_facade_patterns)

    assert violations == []
  end

  test "workflow extension registry internals stay platform-mechanism only" do
    violations =
      "lib/symphony_elixir/workflow/extension/registry"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_workflow_extension_registry_facade_patterns))

    assert violations == []
  end

  test "workflow extension runtime remains a small facade" do
    line_count =
      @workflow_extension_runtime_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    assert line_count <= @workflow_extension_runtime_line_limit,
           "#{@workflow_extension_runtime_path}: #{line_count} lines exceeds #{@workflow_extension_runtime_line_limit}; keep runtime orchestration in Runtime.Dispatcher/Options/ResultApplier/CommandExecutor/Error"
  end

  test "workflow extension behaviour stays a minimal runtime contract" do
    violations =
      "lib/symphony_elixir/workflow/extension.ex"
      |> forbidden_matches(@forbidden_workflow_extension_runtime_contract_callback_patterns)

    assert violations == []
  end

  test "workflow extension runtime public API remains facade-only" do
    violations =
      @workflow_extension_runtime_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @workflow_extension_runtime_public_functions))
      |> Enum.map(&"#{@workflow_extension_runtime_path}: public function #{&1}/... is outside the workflow extension runtime facade API")

    assert violations == []
  end

  test "workflow extension diagnostics public API remains bounded-type only" do
    violations =
      @workflow_extension_diagnostics_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @workflow_extension_diagnostics_public_functions))
      |> Enum.map(&"#{@workflow_extension_diagnostics_path}: public function #{&1}/... is outside the workflow extension diagnostics API")

    assert violations == []
  end

  test "workflow extension diagnostics stays generic and bounded" do
    violations =
      @workflow_extension_diagnostics_path
      |> forbidden_matches(@forbidden_workflow_extension_diagnostics_patterns)

    assert violations == []
  end

  test "workflow extension state-store public API remains facade-only" do
    violations =
      @workflow_extension_state_store_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @workflow_extension_state_store_public_functions))
      |> Enum.map(&"#{@workflow_extension_state_store_path}: public function #{&1}/... is outside the workflow extension state-store facade API")

    assert violations == []
  end

  test "workflow extension state-store remains a small facade" do
    line_count =
      @workflow_extension_state_store_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    assert line_count <= @workflow_extension_state_store_line_limit,
           "#{@workflow_extension_state_store_path}: #{line_count} lines exceeds #{@workflow_extension_state_store_line_limit}; keep opts, config, backend selection, and errors in StateStore.Options/Config/BackendSelector/Error"
  end

  test "workflow extension state-store facade avoids destructive and physical storage APIs" do
    violations =
      @workflow_extension_state_store_path
      |> forbidden_matches(@forbidden_workflow_extension_state_store_facade_patterns)

    assert violations == []
  end

  test "workflow extension state-store record stays below store-split threshold" do
    line_count =
      @workflow_extension_state_store_record_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    assert line_count <= @workflow_extension_state_store_record_line_limit,
           "#{@workflow_extension_state_store_record_path}: #{line_count} lines exceeds #{@workflow_extension_state_store_record_line_limit}; extract Record.Codec/Identity/Validation before adding revision, retention, or migration behavior"
  end

  test "workflow operator-command registry remains a small facade" do
    line_count =
      @operator_command_registry_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    assert line_count <= @operator_command_registry_line_limit,
           "#{@operator_command_registry_path}: #{line_count} lines exceeds #{@operator_command_registry_line_limit}; extract Collector/Validator/Projection before adding more registry behavior"
  end

  test "workflow operator-command registry public API remains facade-only" do
    violations =
      @operator_command_registry_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @operator_command_registry_public_functions))
      |> Enum.map(&"#{@operator_command_registry_path}: public function #{&1}/... is outside the operator-command registry facade API")

    assert violations == []
  end

  test "workflow operator-command registry stays platform-mechanism only" do
    violations =
      @operator_command_registry_path
      |> forbidden_matches(@forbidden_operator_command_registry_facade_patterns)

    assert violations == []
  end

  test "workflow tool-result-recorder registry remains a small facade" do
    line_count =
      @tool_result_recorder_registry_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    assert line_count <= @tool_result_recorder_registry_line_limit,
           "#{@tool_result_recorder_registry_path}: #{line_count} lines exceeds #{@tool_result_recorder_registry_line_limit}; extract Collector/Validator/Projection before adding more registry behavior"
  end

  test "workflow tool-result-recorder registry public API remains facade-only" do
    violations =
      @tool_result_recorder_registry_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @tool_result_recorder_registry_public_functions))
      |> Enum.map(&"#{@tool_result_recorder_registry_path}: public function #{&1}/... is outside the tool-result-recorder registry facade API")

    assert violations == []
  end

  test "workflow tool-result-recorder dispatcher remains a small facade" do
    line_count =
      @tool_result_recorder_dispatcher_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    assert line_count <= @tool_result_recorder_dispatcher_line_limit,
           "#{@tool_result_recorder_dispatcher_path}: #{line_count} lines exceeds #{@tool_result_recorder_dispatcher_line_limit}; extract Options/Error/Invoker before adding more dispatcher behavior"
  end

  test "workflow tool-result-recorder dispatcher public API remains facade-only" do
    violations =
      @tool_result_recorder_dispatcher_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @tool_result_recorder_dispatcher_public_functions))
      |> Enum.map(&"#{@tool_result_recorder_dispatcher_path}: public function #{&1}/... is outside the tool-result-recorder dispatcher facade API")

    assert violations == []
  end

  test "workflow tool-result-recorder mechanisms stay platform-mechanism only" do
    violations =
      "lib/symphony_elixir/workflow/extension/tool_result_recorder"
      |> source_files()
      |> Kernel.++(source_files("lib/symphony_elixir/workflow/extension/tool_result_recorder.ex"))
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_tool_result_recorder_mechanism_patterns))

    assert violations == []
  end

  test "coding PR delivery known target domain stays extension-owned" do
    violations =
      "lib/symphony_elixir"
      |> source_files()
      |> Enum.flat_map(
        &forbidden_matches(&1, [
          {~r/\bSymphonyElixir\.ChangeProposalReconciliation\.KnownTarget\b/, "known target domain model must stay under Workflow.Extensions.CodingPrDelivery"}
        ])
      )

    assert violations == []
  end

  test "coding PR delivery known target core avoids external runtime DTOs" do
    violations =
      @known_target_dir
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_known_target_core_dependency_patterns))

    assert violations == []
  end

  test "coding PR delivery known target registry stays a thin runtime index" do
    violations =
      @known_target_registry_path
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_known_target_registry_patterns))

    assert violations == []
  end

  test "coding PR delivery known target registry stays below store-extraction threshold" do
    line_count =
      @known_target_registry_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    assert line_count <= @known_target_registry_line_limit,
           "#{@known_target_registry_path}: #{line_count} lines exceeds #{@known_target_registry_line_limit}; keep Registry as facade/GenServer entry and extract submodules before adding more behavior"
  end

  test "coding PR delivery known target storage facade stays thin" do
    violations =
      @known_target_storage_path
      |> forbidden_matches(@forbidden_known_target_storage_patterns)

    assert violations == []
  end

  test "coding PR delivery known target StateStore backend keeps adapter boundary narrow" do
    violations =
      @known_target_state_store_backend_path
      |> forbidden_matches(@forbidden_known_target_state_store_backend_patterns)

    assert violations == []
  end

  test "coding PR delivery candidate inbox keeps runtime facade boundary explicit" do
    facade_violations =
      @candidate_inbox_path
      |> forbidden_matches(@forbidden_candidate_inbox_patterns)

    public_api_violations =
      @candidate_inbox_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @candidate_inbox_public_functions))
      |> Enum.map(&"#{@candidate_inbox_path}: public function #{&1}/... is outside the Inbox runtime facade API")

    assert facade_violations ++ public_api_violations == []
  end

  test "coding PR delivery reconciliation stays extension-owned" do
    violations =
      "lib/symphony_elixir"
      |> source_files()
      |> Enum.flat_map(
        &forbidden_matches(&1, [
          {~r/\bSymphonyElixir\.ChangeProposalReconciliation(?:\.|\b)/, "reconciliation business service must stay under Workflow.Extensions.CodingPrDelivery.Reconciliation"},
          {~r/\bSymphonyElixir\.Workflow\.ChangeProposalReconciliation(?:\.|\b)/, "reconciliation Config/Facts/Decision must stay under Workflow.Extensions.CodingPrDelivery.Reconciliation"}
        ])
      )

    assert violations == []
  end

  test "coding PR delivery reconciliation facade stays thin" do
    line_count =
      @coding_pr_delivery_reconciliation_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    facade_violations =
      @coding_pr_delivery_reconciliation_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_reconciliation_facade_patterns)

    public_api_violations =
      @coding_pr_delivery_reconciliation_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @coding_pr_delivery_reconciliation_public_functions))
      |> Enum.map(&"#{@coding_pr_delivery_reconciliation_path}: public function #{&1}/... is outside the Reconciliation facade API")

    line_violations =
      if line_count <= @coding_pr_delivery_reconciliation_line_limit do
        []
      else
        [
          "#{@coding_pr_delivery_reconciliation_path}: #{line_count} lines exceeds #{@coding_pr_delivery_reconciliation_line_limit}; keep registration, producer, event, command, and option logic in Reconciliation.* submodules"
        ]
      end

    assert line_violations ++ facade_violations ++ public_api_violations == []
  end

  test "coding PR delivery reconciliation contract remains a small facade" do
    line_count =
      @coding_pr_delivery_reconciliation_contract_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    facade_violations =
      @coding_pr_delivery_reconciliation_contract_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_reconciliation_contract_facade_patterns)

    public_api_violations =
      @coding_pr_delivery_reconciliation_contract_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @coding_pr_delivery_reconciliation_contract_public_functions))
      |> Enum.map(&"#{@coding_pr_delivery_reconciliation_contract_path}: public function #{&1}/... is outside the Reconciliation.Contract facade API")

    line_violations =
      if line_count <= @coding_pr_delivery_reconciliation_contract_line_limit do
        []
      else
        [
          "#{@coding_pr_delivery_reconciliation_contract_path}: #{line_count} lines exceeds #{@coding_pr_delivery_reconciliation_contract_line_limit}; keep events, producers, statuses, capabilities, and reasons in Contract submodules"
        ]
      end

    assert line_violations ++ facade_violations ++ public_api_violations == []
  end

  test "coding PR delivery reconciliation contract constants stay in focused submodules" do
    contract_files =
      source_files(@coding_pr_delivery_reconciliation_contract_path) ++
        source_files(@coding_pr_delivery_reconciliation_contract_dir)

    violations =
      (contract_files
       |> Enum.reject(&(&1 == @coding_pr_delivery_reconciliation_contract_capabilities_path))
       |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_reconciliation_contract_capability_patterns))) ++
        (contract_files
         |> Enum.reject(&(&1 == @coding_pr_delivery_reconciliation_contract_events_path))
         |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_reconciliation_contract_event_patterns))) ++
        (contract_files
         |> Enum.reject(&(&1 == @coding_pr_delivery_reconciliation_contract_producers_path))
         |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_reconciliation_contract_producer_patterns))) ++
        (contract_files
         |> Enum.reject(&(&1 == @coding_pr_delivery_reconciliation_contract_statuses_path))
         |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_reconciliation_contract_status_patterns)))

    assert violations == []
  end

  test "coding PR delivery reconciliation config remains a small facade" do
    line_count =
      @coding_pr_delivery_reconciliation_config_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    facade_violations =
      @coding_pr_delivery_reconciliation_config_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_reconciliation_config_facade_patterns)

    public_api_violations =
      @coding_pr_delivery_reconciliation_config_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @coding_pr_delivery_reconciliation_config_public_functions))
      |> Enum.map(&"#{@coding_pr_delivery_reconciliation_config_path}: public function #{&1}/... is outside the Reconciliation.Config facade API")

    line_violations =
      if line_count <= @coding_pr_delivery_reconciliation_config_line_limit do
        []
      else
        [
          "#{@coding_pr_delivery_reconciliation_config_path}: #{line_count} lines exceeds #{@coding_pr_delivery_reconciliation_config_line_limit}; keep source extraction, parsing, validation, route semantics, and error formatting in Config.Source/Parser/Validator/Routes/Error"
        ]
      end

    assert line_violations ++ facade_violations ++ public_api_violations == []
  end

  test "coding PR delivery reconciliation config schema strings stay centralized" do
    violations =
      @coding_pr_delivery_reconciliation_config_dir
      |> source_files()
      |> Kernel.++(source_files(@coding_pr_delivery_reconciliation_config_path))
      |> Enum.reject(&(&1 == @coding_pr_delivery_reconciliation_config_contract_path))
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_reconciliation_config_schema_literals))

    assert violations == []
  end

  test "coding PR delivery reconciliation event fields stay centralized" do
    event_field_violations =
      @coding_pr_delivery_reconciliation_events_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_reconciliation_event_field_patterns)

    events_facade_violations =
      @coding_pr_delivery_reconciliation_events_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_reconciliation_events_facade_patterns)

    fields_contract_violations =
      @coding_pr_delivery_reconciliation_events_fields_path
      |> forbidden_matches([
        {~r/^\s*(?:alias|import|require|use)\s+/m, "Reconciliation.Events.Fields must stay a narrow field-key contract without business or provider dependencies"}
      ])

    base_fields_violations =
      @coding_pr_delivery_reconciliation_events_base_fields_path
      |> forbidden_matches([
        {~r/\bObservabilityLogger\b|\bSymphonyElixir\.Observability\b/, "Reconciliation.Events.BaseFields must only project base fields and must not emit events"},
        {~r/\b(?:IssueContext|RouteRef|KnownTargetReference)\b|\bKnownTarget\.Reference\b/, "Reconciliation.Events.BaseFields must not own route or change-proposal reference projection"},
        {~r/\binspect\s*\(/, "Reconciliation.Events.BaseFields must not format public diagnostics"}
      ])

    change_proposal_fields_violations =
      @coding_pr_delivery_reconciliation_events_change_proposal_fields_path
      |> forbidden_matches([
        {~r/\bObservabilityLogger\b|\bSymphonyElixir\.Observability\b/, "Reconciliation.Events.ChangeProposalFields must only project change-proposal fields and must not emit events"},
        {~r/\b(?:IssueContext|RouteRef|TrackerConfig|RuntimeProjection|ProfileRegistry)\b/, "Reconciliation.Events.ChangeProposalFields must not own route, profile, tracker, or runtime projection"}
      ])

    route_fields_violations =
      @coding_pr_delivery_reconciliation_events_route_fields_path
      |> forbidden_matches([
        {~r/\bObservabilityLogger\b|\bSymphonyElixir\.Observability\b/, "Reconciliation.Events.RouteFields must only project route fields and must not emit events"},
        {~r/\binspect\s*\(/, "Reconciliation.Events.RouteFields must not format public diagnostics"}
      ])

    diagnostics_violations =
      @coding_pr_delivery_reconciliation_events_diagnostics_path
      |> forbidden_matches([
        {~r/\binspect\s*\(/, "Reconciliation.Events.Diagnostics must use bounded type/exception diagnostics instead of raw inspect"}
      ])

    emitter_violations =
      @coding_pr_delivery_reconciliation_events_emitter_path
      |> forbidden_matches([
        {~r/\bSymphonyElixir\.Observability\b|\bObservabilityLogger\b/,
         "Reconciliation.Events.Emitter must stay a port facade; host Observability belongs in HostAdapters.Reconciliation.EventEmitterDefaults"},
        {~r/(?:else:\s*Defaults|backend\([^)]*\),\s*do:\s*Defaults)/, "Reconciliation.Events.Emitter must fail closed for invalid opts instead of silently falling back to the default backend"}
      ])

    emitter_defaults_violations =
      @coding_pr_delivery_reconciliation_events_emitter_defaults_path
      |> forbidden_matches([
        {~r/\b(?:BaseFields|ChangeProposalFields|RouteFields|Decision|Facts|RouteFacts|Issue|Config)\b/, "Reconciliation event emitter host adapter must not own event field or business projection"}
      ])

    assert event_field_violations ++
             events_facade_violations ++
             fields_contract_violations ++
             base_fields_violations ++
             change_proposal_fields_violations ++
             route_fields_violations ++
             diagnostics_violations ++
             emitter_violations ++
             emitter_defaults_violations == []
  end

  test "coding PR delivery provider facts payload vocabulary stays centralized" do
    service_violations =
      @coding_pr_delivery_reconciliation_provider_facts_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_provider_facts_contract_literals)

    contract_violations =
      @coding_pr_delivery_reconciliation_provider_facts_contract_path
      |> forbidden_matches([
        {~r/\b(?:RepoProvider|KnownTarget|Facts|Checks|Reviews)\b/, "ProviderFacts.Contract must stay payload vocabulary only and must not depend on service, domain, or provider modules"}
      ])

    assert service_violations ++ contract_violations == []
  end

  test "coding PR delivery provider facts remains a thin facade" do
    line_count =
      @coding_pr_delivery_reconciliation_provider_facts_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    line_violations =
      if line_count <= @coding_pr_delivery_reconciliation_provider_facts_line_limit do
        []
      else
        [
          "#{@coding_pr_delivery_reconciliation_provider_facts_path}: #{line_count} lines exceeds #{@coding_pr_delivery_reconciliation_provider_facts_line_limit}; keep options, provider calls, payload extraction, summary logic, and facts building in ProviderFacts.* submodules"
        ]
      end

    facade_violations =
      @coding_pr_delivery_reconciliation_provider_facts_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_provider_facts_facade_patterns)

    public_api_violations =
      @coding_pr_delivery_reconciliation_provider_facts_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @coding_pr_delivery_reconciliation_provider_facts_public_functions))
      |> Enum.map(&"#{@coding_pr_delivery_reconciliation_provider_facts_path}: public function #{&1}/... is outside the ProviderFacts facade API")

    assert line_violations ++ facade_violations ++ public_api_violations == []
  end

  test "coding PR delivery provider facts keeps provider error protocol behind host adapter" do
    direct_provider_error_patterns = [
      {~r/\bSymphonyElixir\.RepoProvider(?:\.|\b)|\bRepoProviderError\b|\bRepoProvider\.Error\b/,
       "ProviderFacts core modules must use HostAdapters.Reconciliation.ProviderFactsDefaults for provider error protocol access"}
    ]

    core_violations =
      [
        @coding_pr_delivery_reconciliation_provider_facts_path,
        @coding_pr_delivery_reconciliation_provider_facts_builder_path
      ]
      |> Enum.flat_map(&forbidden_matches(&1, direct_provider_error_patterns))

    host_adapter_violations =
      @coding_pr_delivery_reconciliation_provider_facts_defaults_path
      |> forbidden_matches([
        {~r/\b(?:KnownTarget|Builder|Summary|Payload|Client)\b/,
         "ProviderFacts host defaults must stay a RepoProvider adapter and must not own target, facts-building, payload, client, or summary rules"}
      ])

    assert core_violations ++ host_adapter_violations == []
  end

  test "coding PR delivery provider facts provider client keeps diagnostics bounded" do
    violations =
      @coding_pr_delivery_reconciliation_provider_facts_client_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_provider_facts_client_diagnostic_patterns)

    assert violations == []
  end

  test "coding PR delivery provider facts summary does not depend on repo-provider land-watch internals" do
    line_count =
      @coding_pr_delivery_reconciliation_provider_facts_summary_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    line_violations =
      if line_count <= @coding_pr_delivery_reconciliation_provider_facts_summary_line_limit do
        []
      else
        [
          "#{@coding_pr_delivery_reconciliation_provider_facts_summary_path}: #{line_count} lines exceeds #{@coding_pr_delivery_reconciliation_provider_facts_summary_line_limit}; keep check, review, feedback, and settings rules in ProviderFacts.Summary.* submodules"
        ]
      end

    public_api_violations =
      @coding_pr_delivery_reconciliation_provider_facts_summary_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @coding_pr_delivery_reconciliation_provider_facts_summary_public_functions))
      |> Enum.map(&"#{@coding_pr_delivery_reconciliation_provider_facts_summary_path}: public function #{&1}/... is outside the ProviderFacts.Summary facade API")

    violations =
      (source_files(@coding_pr_delivery_reconciliation_provider_facts_summary_path) ++
         source_files(@coding_pr_delivery_reconciliation_provider_facts_summary_dir))
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_provider_facts_summary_patterns))

    assert line_violations ++ public_api_violations ++ violations == []
  end

  test "coding PR delivery one-shot host dependencies stay behind host adapter" do
    deps_violations =
      @coding_pr_delivery_reconciliation_one_shot_deps_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_one_shot_deps_patterns)

    host_deps_violations =
      @coding_pr_delivery_reconciliation_one_shot_host_deps_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_one_shot_host_deps_patterns)

    assert deps_violations ++ host_deps_violations == []
  end

  test "coding PR delivery reconciler remains a thin poll-cycle facade" do
    line_count =
      @coding_pr_delivery_reconciler_path
      |> File.read!()
      |> String.split("\n")
      |> length()

    line_violations =
      if line_count <= @coding_pr_delivery_reconciler_line_limit do
        []
      else
        [
          "#{@coding_pr_delivery_reconciler_path}: #{line_count} lines exceeds #{@coding_pr_delivery_reconciler_line_limit}; keep options, clients, candidates, target lookup, issue processing, and diagnostics in Reconciler.* submodules"
        ]
      end

    facade_violations =
      @coding_pr_delivery_reconciler_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_reconciler_facade_patterns)

    public_api_violations =
      @coding_pr_delivery_reconciler_path
      |> public_function_names()
      |> Enum.reject(&(&1 in @coding_pr_delivery_reconciler_public_functions))
      |> Enum.map(&"#{@coding_pr_delivery_reconciler_path}: public function #{&1}/... is outside the Reconciler facade API")

    assert line_violations ++ facade_violations ++ public_api_violations == []
  end

  test "coding PR delivery reconciler adapters keep diagnostics and defaults bounded" do
    violations =
      (@coding_pr_delivery_reconciler_clients_path
       |> forbidden_matches(@forbidden_coding_pr_delivery_reconciler_client_diagnostic_patterns)) ++
        (@coding_pr_delivery_reconciler_defaults_path
         |> forbidden_matches(@forbidden_coding_pr_delivery_reconciler_default_patterns)) ++
        (@coding_pr_delivery_reconciler_diagnostics_path
         |> forbidden_matches([
           {~r/\bException\.message\s*\(/, "Reconciler.Diagnostics must not expose exception messages"},
           {~r/\binspect\s*\(\s*(?:reason|value|payload|result)\s*\)/, "Reconciler.Diagnostics must not inspect raw callback or provider values"}
         ]))

    assert violations == []
  end

  test "coding PR delivery transition keeps tracker IO and diagnostics behind submodules" do
    violations =
      (@coding_pr_delivery_transition_path
       |> forbidden_matches(@forbidden_coding_pr_delivery_transition_facade_patterns)) ++
        (@coding_pr_delivery_transition_clients_path
         |> forbidden_matches(@forbidden_coding_pr_delivery_transition_client_diagnostic_patterns)) ++
        (@coding_pr_delivery_transition_defaults_path
         |> forbidden_matches(@forbidden_coding_pr_delivery_transition_defaults_patterns)) ++
        (@coding_pr_delivery_transition_diagnostics_path
         |> forbidden_matches([
           {~r/\bException\.message\s*\(/, "Transition.Diagnostics must not expose exception messages"},
           {~r/\binspect\s*\(\s*(?:reason|value|payload|result)\s*\)/, "Transition.Diagnostics must not inspect raw callback or provider values"}
         ]))

    assert violations == []
  end

  test "coding PR delivery route context consumes tracker lifecycle accessors" do
    violations =
      @coding_pr_delivery_route_context_path
      |> forbidden_matches(@forbidden_coding_pr_delivery_route_context_tracker_lifecycle_literals)

    assert violations == []
  end

  test "change proposal references are extracted by coding PR delivery extension adapters" do
    violations =
      "lib/symphony_elixir"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_tracker_change_proposal_reference_call_patterns))

    assert violations == []
  end

  test "coding PR delivery tool results enter through extension result recorders" do
    retired_facade_pattern = Regex.compile!("\\bReconciliation\\.record_" <> "tracker_tool_result\\s*\\(")

    violations =
      (source_files("lib/symphony_elixir") ++ test_files())
      |> Enum.flat_map(
        &forbidden_matches(&1, [
          {retired_facade_pattern, "Coding PR Delivery tool results must enter through Workflow.Extension.ToolResultRecorder, not the reconciliation facade"}
        ])
      )

    assert violations == []
  end

  test "coding PR delivery producers keep public diagnostics bounded" do
    violations =
      @coding_pr_delivery_reconciliation_producer_dir
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_producer_diagnostic_patterns))

    assert violations == []
  end

  test "coding PR delivery producer payload adapters require canonical string-key payloads" do
    violations =
      @coding_pr_delivery_reconciliation_producer_dir
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_producer_payload_compatibility_patterns))

    assert violations == []
  end

  test "coding PR delivery producer app config stays behind Producer.Config" do
    violations =
      @coding_pr_delivery_reconciliation_producer_dir
      |> source_files()
      |> Enum.reject(&(&1 == @coding_pr_delivery_reconciliation_producer_config_path))
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_producer_config_patterns))

    assert violations == []
  end

  test "coding PR delivery producer platform defaults stay behind HostAdapters" do
    violations =
      @coding_pr_delivery_reconciliation_producer_dir
      |> source_files()
      |> Enum.reject(&(&1 == @coding_pr_delivery_reconciliation_producer_defaults_path))
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_producer_default_port_patterns))

    assert violations == []
  end

  test "coding PR delivery producer facades stay small" do
    violations =
      [
        {@coding_pr_delivery_tracker_tool_result_handler_path, @coding_pr_delivery_tracker_tool_result_handler_line_limit},
        {@coding_pr_delivery_known_target_watcher_path, @coding_pr_delivery_known_target_watcher_line_limit},
        {@coding_pr_delivery_startup_backlog_bootstrap_path, @coding_pr_delivery_startup_backlog_bootstrap_line_limit}
      ]
      |> Enum.flat_map(fn {path, limit} ->
        line_count =
          path
          |> File.read!()
          |> String.split("\n")
          |> length()

        if line_count <= limit do
          []
        else
          ["#{path}: #{line_count} lines exceeds #{limit}; keep producer facades thin and move routing, events, commands, and target inspection into submodules"]
        end
      end)

    assert violations == []
  end

  test "coding PR delivery producer facades delegate external integration details" do
    violations =
      [
        @coding_pr_delivery_tracker_tool_result_handler_path,
        @coding_pr_delivery_known_target_watcher_path,
        @coding_pr_delivery_startup_backlog_bootstrap_path
      ]
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_coding_pr_delivery_producer_facade_patterns))

    assert violations == []
  end

  test "orchestrator running lifecycle stays provider-neutral and dispatch-driven" do
    files = orchestrator_running_lifecycle_files()

    provider_violations =
      files
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_orchestrator_running_lifecycle_patterns))

    state_literal_violations =
      files
      |> Enum.flat_map(&workflow_state_literal_matches/1)

    assert provider_violations ++ state_literal_violations == []
  end

  test "platform namespace only contains low-level platform modules" do
    files = source_files("lib/symphony_elixir/platform")

    module_violations =
      files
      |> Enum.flat_map(&platform_module_violations/1)

    dependency_violations =
      files
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_platform_dependency_patterns))

    filename_violations =
      files
      |> Enum.flat_map(&forbidden_filename_matches(&1, @forbidden_platform_filename_patterns))

    assert module_violations ++ dependency_violations ++ filename_violations == []
  end

  test "worker daemon server namespace stays independent of higher-level Symphony contexts" do
    violations =
      "lib/symphony_worker_daemon"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_worker_daemon_server_dependency_patterns))

    assert violations == []
  end

  test "bundled repo skills prefer repo helper for covered git operations" do
    violations =
      @runtime_skill_paths
      |> Enum.flat_map(&skill_files/1)
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_runtime_skill_patterns))

    assert violations == []
  end

  test "repo-local Codex skills stay scoped to local development" do
    violations =
      @repo_local_skill_roots
      |> Enum.flat_map(&text_files/1)
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_repo_local_skill_patterns))

    assert violations == []
  end

  test "local markdown links in operator and architecture docs point to existing paths" do
    files = ["README.md" | text_files("docs")]

    violations =
      files
      |> Enum.flat_map(&broken_local_markdown_links/1)

    assert violations == []
  end

  test "tests that touch process-wide state are not async" do
    violations =
      test_files()
      |> Enum.filter(&async_test_file?/1)
      |> Enum.flat_map(&forbidden_matches(&1, @process_wide_state_test_patterns))

    assert violations == []
  end

  test "production string normalization mappings stay centralized" do
    violations =
      "lib"
      |> source_files()
      |> Enum.flat_map(&direct_string_mapping_matches/1)

    assert violations == []
  end

  test "TestSupport-backed tests stay synchronous" do
    violations =
      test_files()
      |> Enum.filter(fn path -> uses_test_support?(path) and async_test_file?(path) end)
      |> Enum.map(&"#{&1}: TestSupport manages process-wide state and must stay synchronous")

    assert violations == []
  end

  defp source_files(dir) do
    if File.regular?(dir) do
      [dir]
    else
      dir
      |> Path.join("**/*.ex")
      |> Path.wildcard()
    end
  end

  defp test_files do
    "test/**/*_test.exs"
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp orchestrator_running_lifecycle_files do
    source_files("lib/symphony_elixir/orchestrator/running") ++
      ["lib/symphony_elixir/orchestrator/worker_exit.ex"]
  end

  defp workflow_platform_source_files do
    "lib/symphony_elixir/workflow"
    |> source_files()
    |> Enum.reject(&String.starts_with?(&1, "lib/symphony_elixir/workflow/extensions/"))
  end

  defp workflow_profile_template_registry_files do
    [
      "lib/symphony_elixir/workflow/profile_registry.ex",
      "lib/symphony_elixir/workflow/template/registry.ex"
    ]
  end

  defp non_extension_business_reference_source_files do
    "lib/symphony_elixir"
    |> source_files()
    |> Kernel.++(source_files("lib/mix/tasks"))
    |> Kernel.++(source_files("config/config.exs"))
    |> Enum.reject(
      &(String.starts_with?(&1, "lib/symphony_elixir/workflow/extensions/") or
          &1 == "lib/symphony_elixir/assembly_catalog/workflow_extensions.ex")
    )
  end

  defp assembly_catalog_source_files do
    source_files("lib/symphony_elixir/assembly_catalog")
  end

  defp assembly_catalog_storage_source_files do
    ["lib/symphony_elixir/assembly_catalog/storage_contracts.ex"]
  end

  defp assembly_catalog_workflow_extension_source_files do
    ["lib/symphony_elixir/assembly_catalog/workflow_extensions.ex"]
  end

  defp assembly_catalog_capability_source_files do
    ["lib/symphony_elixir/assembly_catalog/capability_sources.ex"]
  end

  defp assembly_catalog_dynamic_tool_source_files do
    ["lib/symphony_elixir/assembly_catalog/dynamic_tool_sources.ex"]
  end

  defp workflow_template_asset_resolver_files do
    source_files("lib/symphony_elixir/workflow/template") ++
      source_files("lib/symphony_elixir/workflow/extensions")
  end

  defp workflow_template_legacy_api_reference_files do
    (source_files("lib/symphony_elixir") ++ source_files("test"))
    |> Enum.reject(&(&1 == "test/symphony_elixir/repo_architecture_test.exs"))
  end

  defp workflow_template_public_facade_reference_files do
    "lib/symphony_elixir"
    |> source_files()
    |> Enum.reject(
      &(String.starts_with?(&1, "lib/symphony_elixir/workflow/template/") or
          &1 == "lib/symphony_elixir/workflow/template.ex")
    )
  end

  defp coding_pr_delivery_facade_files do
    ["lib/symphony_elixir/workflow/extensions/coding_pr_delivery.ex"]
  end

  defp storage_table_catalog_facade_files do
    ["lib/symphony_elixir/storage/table_catalog.ex"]
  end

  defp public_function_names(path) do
    path
    |> File.read!()
    |> then(&Regex.scan(~r/^\s{2}def\s+([a-zA-Z_][a-zA-Z0-9_?!]*)\b/m, &1))
    |> Enum.map(fn [_match, function_name] -> function_name end)
  end

  defp async_test_file?(path) do
    Regex.match?(~r/use\s+ExUnit\.Case,\s*async:\s*true/, File.read!(path))
  end

  defp uses_test_support?(path) do
    Regex.match?(~r/^\s*use\s+SymphonyElixir\.TestSupport\b/m, File.read!(path))
  end

  defp tracked_entries(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&String.ends_with?(&1, "/"))
  end

  defp skill_files(path) do
    path
    |> Path.expand(File.cwd!())
    |> case do
      expanded when is_binary(expanded) ->
        if File.exists?(expanded), do: [expanded], else: []
    end
  end

  defp text_files(path) do
    expanded = Path.expand(path, File.cwd!())

    cond do
      File.regular?(expanded) ->
        [expanded]

      File.dir?(expanded) ->
        expanded
        |> Path.join("**/*")
        |> Path.wildcard(match_dot: true)
        |> Enum.filter(&File.regular?/1)

      true ->
        []
    end
  end

  defp forbidden_matches(path, patterns) do
    contents = File.read!(path)

    patterns
    |> Enum.flat_map(fn {pattern, message} ->
      if Regex.match?(pattern, contents) do
        ["#{path}: #{message}"]
      else
        []
      end
    end)
  end

  defp direct_string_mapping_matches(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if line |> String.trim_leading() |> String.starts_with?("#") do
        []
      else
        Enum.flat_map(@direct_string_mapping_patterns, fn {pattern, message} ->
          if Regex.match?(pattern, line) do
            ["#{path}:#{line_number}: #{message}"]
          else
            []
          end
        end)
      end
    end)
  end

  defp forbidden_filename_matches(path, patterns) do
    patterns
    |> Enum.flat_map(fn {pattern, message} ->
      if Regex.match?(pattern, path) do
        ["#{path}: #{message}"]
      else
        []
      end
    end)
  end

  defp workflow_state_literal_matches(path) do
    ~r/"([^"\n]+)"/
    |> Regex.scan(File.read!(path))
    |> Enum.flat_map(fn [_match, literal] ->
      if workflow_state_literal?(literal) do
        ["#{path}: orchestrator running/exit lifecycle must use Dispatch state semantics instead of hardcoded workflow state literal #{inspect(literal)}"]
      else
        []
      end
    end)
  end

  defp workflow_state_literal?(literal) when is_binary(literal) do
    String.length(literal) <= 40 and
      not String.contains?(literal, ["\#{", "_", "-", ".", "/", ":"]) and
      Regex.match?(~r/^[A-Z][A-Za-z]*(?: [A-Z][A-Za-z]*)*$/, literal)
  end

  defp platform_module_violations(path) do
    contents = File.read!(path)

    Regex.scan(~r/defmodule\s+([A-Za-z0-9_.]+)\s+do/, contents)
    |> Enum.flat_map(fn [_match, module_name] ->
      if String.starts_with?(module_name, "SymphonyElixir.Platform.") do
        []
      else
        ["#{path}: platform modules must use the SymphonyElixir.Platform namespace, got #{module_name}"]
      end
    end)
  end

  defp provider_app_server_support_module_violations(path) do
    contents = File.read!(path)

    Regex.scan(~r/defmodule\s+([A-Za-z0-9_.]+)\s+do/, contents)
    |> Enum.flat_map(fn [_match, module_name] ->
      if String.starts_with?(module_name, "SymphonyElixir.AgentProvider.AppServer.") do
        []
      else
        ["#{path}: shared app-server support modules must use the SymphonyElixir.AgentProvider.AppServer namespace, got #{module_name}"]
      end
    end)
  end

  defp assembly_workflow_extension_source_violations(path) do
    Enum.flat_map(module_names(path), fn module_name ->
      module = module_name_to_atom(module_name)

      cond do
        not Code.ensure_loaded?(module) ->
          ["#{path}: workflow extension assembly catalog module #{module_name} could not be loaded"]

        not module_implements_behaviour?(module, SymphonyElixir.Workflow.Extension.Registry.Source) ->
          [
            "#{path}: workflow extension assembly catalog module #{module_name} must implement SymphonyElixir.Workflow.Extension.Registry.Source"
          ]

        true ->
          []
      end
    end)
  end

  defp assembly_storage_source_violations(path) do
    Enum.flat_map(module_names(path), fn module_name ->
      module = module_name_to_atom(module_name)

      cond do
        not Code.ensure_loaded?(module) ->
          ["#{path}: storage assembly catalog module #{module_name} could not be loaded"]

        not module_implements_behaviour?(module, SymphonyElixir.Storage.TableCatalog.Source) ->
          [
            "#{path}: storage assembly catalog module #{module_name} must implement SymphonyElixir.Storage.TableCatalog.Source"
          ]

        true ->
          []
      end
    end)
  end

  defp assembly_capability_source_violations(path) do
    Enum.flat_map(module_names(path), fn module_name ->
      module = module_name_to_atom(module_name)

      cond do
        not Code.ensure_loaded?(module) ->
          ["#{path}: capability assembly catalog module #{module_name} could not be loaded"]

        not module_implements_behaviour?(module, SymphonyElixir.Capability.SourceCatalog) ->
          [
            "#{path}: capability assembly catalog module #{module_name} must implement SymphonyElixir.Capability.SourceCatalog"
          ]

        true ->
          []
      end
    end)
  end

  defp assembly_dynamic_tool_source_violations(path) do
    Enum.flat_map(module_names(path), fn module_name ->
      module = module_name_to_atom(module_name)

      cond do
        not Code.ensure_loaded?(module) ->
          ["#{path}: Dynamic Tool source assembly catalog module #{module_name} could not be loaded"]

        not module_implements_behaviour?(module, SymphonyElixir.Agent.DynamicTool.SourceCatalog) ->
          [
            "#{path}: Dynamic Tool source assembly catalog module #{module_name} must implement SymphonyElixir.Agent.DynamicTool.SourceCatalog"
          ]

        true ->
          []
      end
    end)
  end

  defp module_prefix_violations(path, expected_prefix) do
    path
    |> module_names()
    |> Enum.flat_map(fn module_name ->
      if module_name == expected_prefix or String.starts_with?(module_name, expected_prefix <> ".") do
        []
      else
        ["#{path}: module #{module_name} must use the #{expected_prefix} namespace"]
      end
    end)
  end

  defp module_name_violations(path, expected_module) do
    case module_names(path) do
      [^expected_module] ->
        []

      module_names ->
        ["#{path}: expected module #{expected_module}, got #{Enum.join(module_names, ", ")}"]
    end
  end

  defp module_names(path) do
    path
    |> File.read!()
    |> then(&Regex.scan(~r/^defmodule\s+([A-Za-z0-9_.]+)\s+do/m, &1))
    |> Enum.map(fn [_match, module_name] -> module_name end)
  end

  defp module_name_to_atom(module_name) do
    module_name
    |> String.split(".")
    |> Module.safe_concat()
  end

  defp module_implements_behaviour?(module, behaviour) do
    module
    |> module_behaviours()
    |> Enum.member?(behaviour)
  end

  defp module_behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.take([:behaviour, :behavior])
    |> Keyword.values()
    |> List.flatten()
  end

  defp broken_local_markdown_links(path) do
    contents = File.read!(path)
    base_dir = Path.dirname(path)

    ~r/\[[^\]]+\]\(([^)]+)\)/
    |> Regex.scan(contents)
    |> Enum.flat_map(fn [_match, raw_target] ->
      target = normalize_markdown_link_target(raw_target)

      cond do
        skip_markdown_link_target?(target) ->
          []

        true ->
          resolved = Path.expand(target, base_dir)

          if File.exists?(resolved) do
            []
          else
            ["#{path}: markdown link target does not exist: #{raw_target}"]
          end
      end
    end)
  end

  defp normalize_markdown_link_target(raw_target) when is_binary(raw_target) do
    raw_target
    |> String.trim()
    |> String.trim_leading("<")
    |> String.trim_trailing(">")
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
    |> String.split("#", parts: 2)
    |> List.first()
  end

  defp skip_markdown_link_target?(""), do: true
  defp skip_markdown_link_target?("#" <> _anchor), do: true

  defp skip_markdown_link_target?(target) when is_binary(target) do
    String.starts_with?(target, ["http://", "https://", "mailto:"])
  end

  defp codex_identifier_matches(path) do
    contents = File.read!(path)

    if Regex.match?(@codex_identifier_pattern, contents) do
      ["#{path}: Codex-specific production code must stay under #{@codex_provider_source_dir}"]
    else
      []
    end
  end

  defp retired_agent_automation_path_matches(path) do
    contents = File.read!(path)

    @retired_agent_automation_paths
    |> Enum.filter(&String.contains?(contents, &1))
    |> Enum.map(&"#{path}: bundled workspace automation must use priv/workspace_automation, not #{&1}")
  end

  defp codex_provider_allowed?(path) do
    String.starts_with?(path, @codex_provider_source_dir <> "/") or path in @codex_provider_allowlist
  end
end

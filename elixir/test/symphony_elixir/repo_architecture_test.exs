defmodule SymphonyElixir.RepoArchitectureTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Platform.CommandEnv

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
    "lib/symphony_elixir/agent_provider/registry.ex"
  ]

  @codex_identifier_pattern ~r/\b(?:Codex|codex|CODEX)\b/

  @source_design_asset_dir "spe" <> "cs"
  @source_design_asset_entrypoint "SP" <> "EC.md"
  @source_design_asset_reference_patterns [
    {Regex.compile!("(?:^|[^[:alnum:]_])(?:\\.\\./)*" <> @source_design_asset_dir <> "/"), "source-only design asset directory reference"},
    {Regex.compile!("\\b" <> @source_design_asset_entrypoint <> "\\b"), "source-only design asset entrypoint reference"}
  ]
  @source_design_asset_reference_exclusions [
    ".secrets.baseline",
    "elixir/lib/mix/tasks/specs.check.ex",
    "elixir/lib/symphony_elixir/specs_check.ex",
    "elixir/test/mix/tasks/specs_check_task_test.exs",
    "elixir/test/symphony_elixir/specs_check_test.exs"
  ]

  @forbidden_provider_patterns [
    {~r/TargetRepo\.(current_branch|head_sha|remote_url|base_branch)\(\s*"\."/, "provider code must not hardcode the current directory for repo-core reads"},
    {~r/TargetRepo\.remote_url\([^)]*"origin"/, "provider code must not hardcode origin for repo-core remote lookups"},
    {~r/Repo\.(current_branch|head_sha|remote_url|base_branch)\(\s*"\."/, "provider code must not bypass Repo.Context with hardcoded current-directory reads"},
    {~r/System\.cmd\(\s*"git"/, "provider code must use SymphonyElixir.Repo instead of direct git commands"},
    {~r/(Shell|CLI)\.run_command\(\s*"git"/, "provider code must use SymphonyElixir.Repo instead of direct git commands"},
    {~r/MuonTrap\.cmd\(\s*"git"/, "provider code must use SymphonyElixir.Repo instead of direct git commands"},
    {~r/Port\.open\([^)]*"git"/, "provider code must use SymphonyElixir.Repo instead of direct git commands"}
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
     "Agent.DynamicTool core must depend on Source abstractions, not the Tracker facade directly"}
  ]

  @forbidden_orchestrator_change_proposal_reconciliation_patterns [
    {~r/\bSymphonyElixir\.ChangeProposalReconciliation\.(?:Reconciler|RouteContext|Transition|Counters|Events)\b/,
     "orchestrator must depend on the ChangeProposalReconciliation facade, not its internal modules"},
    {~r/\bSymphonyElixir\.ChangeProposalReconciliation\.\{[^}]*\b(?:Reconciler|RouteContext|Transition|Counters|Events)\b/,
     "orchestrator must depend on the ChangeProposalReconciliation facade, not its internal modules"},
    {~r/\bChangeProposalReconciliation\.(?:Reconciler|RouteContext|Transition|Counters|Events)\b/, "orchestrator must depend on the ChangeProposalReconciliation facade, not its internal modules"}
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

  @top_level_source_module_files [
    {"lib/symphony_elixir/agent.ex", "SymphonyElixir.Agent"},
    {"lib/symphony_elixir/agent_provider.ex", "SymphonyElixir.AgentProvider"},
    {"lib/symphony_elixir/application.ex", "SymphonyElixir.Application"},
    {"lib/symphony_elixir/change_proposal_reconciliation.ex", "SymphonyElixir.ChangeProposalReconciliation"},
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
    {"lib/symphony_elixir/change_proposal_reconciliation", "SymphonyElixir.ChangeProposalReconciliation"},
    {"lib/symphony_elixir/config/schema", "SymphonyElixir.Config.Schema"},
    {"lib/symphony_elixir/workflow", "SymphonyElixir.Workflow"},
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
    {"lib/symphony_worker_daemon", "SymphonyWorkerDaemon"},
    {"lib/symphony_worker_daemon/api", "SymphonyWorkerDaemon.Api"},
    {"lib/symphony_worker_daemon/protocol", "SymphonyWorkerDaemon.Protocol"},
    {"lib/symphony_worker_daemon/session", "SymphonyWorkerDaemon.Session"}
  ]

  @explicit_module_files [
    {"lib/symphony_elixir/config/schema.ex", "SymphonyElixir.Config.Schema"},
    {"lib/symphony_elixir/workflow/execution_profile_registry.ex", "SymphonyElixir.Workflow.ExecutionProfileRegistry"},
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

  test "agent dynamic tool core does not depend on tracker facade directly" do
    violations =
      "lib/symphony_elixir/agent/dynamic_tool"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_agent_dynamic_tool_dependency_patterns))

    assert violations == []
  end

  test "orchestrator only depends on change proposal reconciliation facade" do
    violations =
      "lib/symphony_elixir/orchestrator"
      |> source_files()
      |> Enum.flat_map(&forbidden_matches(&1, @forbidden_orchestrator_change_proposal_reconciliation_patterns))

    assert violations == []
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

  test "runtime files do not depend on source-only design assets" do
    root = Path.expand("..", File.cwd!())
    tracked_files = git_tracked_files(root)

    runtime_references =
      tracked_files
      |> Enum.reject(fn path ->
        String.starts_with?(path, @source_design_asset_dir <> "/") or
          path in @source_design_asset_reference_exclusions
      end)
      |> Enum.map(&Path.join(root, &1))
      |> Enum.filter(&File.regular?/1)
      |> Enum.flat_map(&forbidden_matches(&1, @source_design_asset_reference_patterns))

    assert runtime_references == []
  end

  test "source-only design assets only link within their own corpus" do
    root = Path.expand("..", File.cwd!())
    specs_root = Path.join(root, @source_design_asset_dir)

    violations =
      specs_root
      |> text_files()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.flat_map(&source_design_asset_link_violations(&1, specs_root))

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

  test "TestSupport-backed tests stay synchronous" do
    violations =
      test_files()
      |> Enum.filter(fn path -> uses_test_support?(path) and async_test_file?(path) end)
      |> Enum.map(&"#{&1}: TestSupport manages process-wide state and must stay synchronous")

    assert violations == []
  end

  defp source_files(dir) do
    dir
    |> Path.join("**/*.ex")
    |> Path.wildcard()
  end

  defp test_files do
    "test/**/*_test.exs"
    |> Path.wildcard()
    |> Enum.sort()
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

  defp git_tracked_files(root) do
    case CommandEnv.system_cmd("git", ["ls-files"], cd: root, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.sort()

      {output, status} ->
        flunk("git ls-files failed with status #{status}: #{output}")
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

  defp source_design_asset_link_violations(path, specs_root) do
    contents = File.read!(path)
    base_dir = Path.dirname(path)
    specs_root = Path.expand(specs_root)

    contents
    |> markdown_link_targets()
    |> Enum.flat_map(fn raw_target ->
      target = normalize_markdown_link_target(raw_target)

      cond do
        target == "" or String.starts_with?(target, "#") ->
          []

        String.starts_with?(target, ["http://", "https://", "mailto:"]) ->
          ["#{path}: source-only design asset link must not use external target: #{raw_target}"]

        true ->
          resolved = Path.expand(target, base_dir)

          cond do
            not String.starts_with?(resolved, specs_root <> "/") and resolved != specs_root ->
              ["#{path}: source-only design asset link leaves #{@source_design_asset_dir}/: #{raw_target}"]

            not File.exists?(resolved) ->
              ["#{path}: source-only design asset link target does not exist: #{raw_target}"]

            true ->
              []
          end
      end
    end)
  end

  defp markdown_link_targets(contents) do
    inline_targets =
      ~r/\[[^\]]+\]\(([^)]+)\)/
      |> Regex.scan(contents)
      |> Enum.map(fn [_match, target] -> target end)

    reference_targets =
      ~r/^\[[^\]]+\]:\s+(\S+)/m
      |> Regex.scan(contents)
      |> Enum.map(fn [_match, target] -> target end)

    inline_targets ++ reference_targets
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

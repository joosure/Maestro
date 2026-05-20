# Architecture Conventions

This guide defines the current module-placement and responsibility boundaries for
`elixir/lib/symphony_elixir/`.

It is normative for both human contributors and AI agents. Use it when adding,
moving, or splitting modules. It describes the current implementation baseline,
not a speculative target architecture.

Public documentation uses Maestro as the product name. Current implementation
identifiers still use compatibility names such as `SymphonyElixir`, `symphony`,
`.symphony`, and `SYMPHONY_*`; keep those literal names when documenting concrete
modules, CLI commands, paths, or environment variables.

It complements:

- [`../README.md`](../README.md): operator-facing runtime behavior and project layout
- [`./logging.md`](./logging.md): observability and status-surface implementation contract
- [`./agent_providers/README.md`](./agent_providers/README.md): provider-specific runtime and protocol guides

## Maintenance Notes

- Workflow capability names are external protocol strings and must be added
  through `SymphonyElixir.Workflow.CapabilityNames` before being referenced by
  profiles, provider adapters, readiness checks, Dynamic Tool inventory, or
  observability projections.
- Dynamic Tool bridge paths, environment variable names, and transport labels
  are shared process contract strings. Keep the canonical definitions in
  `SymphonyElixir.Platform.DynamicToolBridgeContract` so the worker daemon can
  consume them without depending on higher-level agent modules.
- Dynamic Tool bridge response envelope keys are owned by
  `SymphonyElixir.Platform.DynamicToolBridgeContract.Response`. Main-process
  bridge handlers, Web controllers, worker-daemon proxies, and provider-facing
  clients should use that owner instead of duplicating `"success"`, `"payload"`,
  `"error"`, `"code"`, or `"message"`.
- Dynamic Tool observability metric keys are owned by
  `SymphonyElixir.Observability.DynamicToolMetrics`; operator alert envelope
  keys and severity/status values are owned by
  `SymphonyElixir.Observability.AlertContract`. Event-store projections and
  dashboards should consume those owners instead of duplicating alert keys such
  as `"severity"`, `"metric"`, `"count"`, or severity values such as
  `"critical"`, `"warning"`, and `"info"`.
- Worker daemon session status labels are owned by
  `SymphonyWorkerDaemon.Session.Status`. Server, protocol, ledger, API, and
  sweeper code should call that module instead of duplicating status strings or
  terminal-status lists.
- Worker daemon health status labels are owned by
  `SymphonyWorkerDaemon.Protocol.HealthStatus`; non-session mutation response
  status labels, such as accepted input acknowledgements, are owned by
  `SymphonyWorkerDaemon.Protocol.ResponseStatus`.
- Worker daemon HTTP API paths are owned by
  `SymphonyWorkerDaemon.Protocol.Paths`; Web browser paths and static-asset
  paths are owned by `SymphonyElixirWeb.BrowserPaths`; Web observability API
  paths are owned by `SymphonyElixirWeb.Observability.Paths`, with dashboard
  PubSub and display-status helpers under the same Web observability namespace.
- Orchestrator retry status payload labels are owned by
  `SymphonyElixir.Orchestrator.Retry.Status`; retry result-summary labels are
  owned by `SymphonyElixir.Orchestrator.Retry.ResultSummary`.
- Workflow readiness and completion-validation payload labels are owned by
  `SymphonyElixir.Workflow.ReadinessContract`. Orchestrator dispatch code
  should read readiness facts through that contract instead of duplicating
  `"status"`, `"gate"`, or evidence-field strings.
- State-transition readiness policy interfaces are owned by
  `SymphonyElixir.Workflow.StateTransitionReadiness.Policy`; policy dispatch
  and recorder registration are owned by
  `SymphonyElixir.Workflow.StateTransitionReadiness.PolicyRegistry`. Shared
  state-transition readiness envelope, evidence, result, and enum-like strings
  are owned by the `SymphonyElixir.Workflow.StateTransitionReadiness.Contract`
  namespace. Policy-specific check keys, reason codes, observed-evidence codes,
  and tool-name mappings should stay under the owning policy namespace such as
  `SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery`.
- Provider-neutral operation lifecycle status labels for observability events
  are owned by `SymphonyElixir.Observability.OperationStatus`. Turn terminal
  statuses remain owned by `SymphonyElixir.AgentProvider.TurnStatus`.
- Repo-core runtime environment variable names are owned by
  `SymphonyElixir.Repo.RuntimeEnv`; repo-provider runtime environment variable
  names and fallback lookup order are owned by
  `SymphonyElixir.RepoProvider.RuntimeEnv`.
- CNB provider runtime environment variable names are owned by
  `SymphonyElixir.RepoProvider.CNB.RuntimeEnv`.
- Worker-daemon client runtime environment variable names are owned by
  `SymphonyElixir.Agent.Runtime.WorkerDaemon.RuntimeEnv`.
- AGPL source metadata runtime environment lookup is owned by
  `SymphonyElixir.LegalSourceInfo.RuntimeEnv`; Web and Worker Daemon surfaces
  must pass their own notice path explicitly when rendering
  `SymphonyElixir.LegalSourceInfo.payload/1`.
- Provider-neutral agent turn status labels are owned by
  `SymphonyElixir.AgentProvider.TurnStatus`.
- Agent provider kind strings and supported aliases are owned by
  `SymphonyElixir.AgentProvider.Kinds`; registries, defaults, app-server
  metadata, and managed-credential code should use that module.
- Provider-specific managed-credential environment contracts are owned by the
  concrete provider namespace, such as
  `SymphonyElixir.AgentProvider.ClaudeCode.CredentialEnv` and
  `SymphonyElixir.AgentProvider.Codex.CredentialEnv`. Account environment
  generation and adapter materialization should consume those modules instead
  of duplicating credential-kind or environment-variable names.
- Tracker kind strings for bundled adapters are owned by
  `SymphonyElixir.Tracker.Kinds`; tracker registries, adapters, validation
  errors, and observability defaults should use that owner.
- Repo provider kind strings and labels are owned by
  `SymphonyElixir.RepoProvider.Kinds`; registries, adapters, command rendering,
  smoke validation, and config schema code should use that owner.
- Repo provider defaults are owned by `SymphonyElixir.RepoProvider.Defaults`.
  Config schema defaults, runtime env fallbacks, and facade defaults should use
  that module instead of hardcoding the default provider kind.
- Repo-provider normalized check-run status and conclusion helpers are owned by
  `SymphonyElixir.RepoProvider.CheckRun`. Repo-provider command output and
  land-watch logic should use that owner instead of duplicating completed or
  successful-conclusion literals.
- Repo-provider land-watch review environment variable names and defaults are
  owned by `SymphonyElixir.RepoProvider.LandWatch.RuntimeEnv`.
- `SymphonyElixir.Workflow.ExecutionProfile` is a boot-registered descriptor
  contract. Handlers declare supported actions and required capabilities; they
  must explicitly declare the behaviour so the registry can reject accidental
  duck-typed modules. They are not an execution callback surface and should not
  define or rely on `run/1` unless a future orchestrator execution path is
  introduced with tests.

## Goals

- Keep public entry modules stable even as internals grow.
- Organize code by domain ownership and runtime responsibility.
- Keep stateful orchestration paths explicit and easy to audit.
- Isolate tracker-specific and transport-specific behavior.
- Make file placement predictable enough that humans and AI make the same choice.

## Current Layout Model

`lib/symphony_elixir/` currently uses a mixed model with a small number of
top-level files plus responsibility-specific namespaces.

Top-level files are reserved for a small set of shapes:

- OTP and runtime entrypoints:
  - `application.ex`
  - `cli.ex`
- Public facade modules that delegate into same-domain submodules:
  - `agent.ex`
  - `agent_provider.ex`
  - `config.ex`
  - `workflow.ex`
  - `tracker.ex`
  - `repo.ex`
  - `repo_provider.ex`
  - `workspace.ex`
  - `orchestrator.ex`
- Stable data or boundary primitives with narrow ownership:
  - `issue.ex`
  - `path_safety.ex`
- Boundary entrypoints:
  - `http_server.ex`
  - `specs_check.ex`

Responsibility-specific logic lives under matching namespaces:

- `cli/`: CLI subcommand facades, command parsers, option resolution, command routing, token source handling, and output rendering
- `config/`: config entrypoints, schema aggregation, normalization, defaults, and config error formatting
- `config/schema/`: domain-specific embedded config schemas for tracker, repo, agent, runtime, provider, observability, hooks, and server settings
- `workflow/`: workflow store, prompt building, route policy, workflow profiles, and execution-profile registry internals
- `issue/`: issue lifecycle helpers
- `workspace/`: context, paths, git-exclude editing, bootstrap, hooks, cleanup, and remote workspace operations
- `orchestrator/`: poll-cycle coordination, server callback options, issue dispatch execution, polling timers, runtime state construction, agent update integration, worker exit message handling, ignored-message logging, snapshots, launch flow, and cleanup
- `orchestrator/dispatch/`: dispatch context, issue ordering, eligibility, skip reasons, runtime slot view, revalidation, and route preparation
- `orchestrator/retry/`: retry scheduling, retry timer message handling, attempt metadata, retry events, retry issue lookup, and deferred redispatch flow
- `orchestrator/running/`: running issue reconciliation, inactive completion grace, stall detection, termination cleanup, and running-state views
- `tracker/`: provider-neutral tracker config, registry, errors, serialization, and shared adapter support
- `tracker/<kind>/`: tracker-specific adapters, clients, query definitions, transport helpers, pagination, normalizers, codecs and codec internals, dynamic-tool executor internals, workspace preparation, and workflow helpers
- `repo/`: provider-neutral repository model, Git facade, branch/path/status helpers, preflight checks, and repo errors
- `repo/git/`: Git implementation internals for command execution, argument building, repository inspection, remote operations, branch operations, commit operations, status parsing, reference parsing, validation, and error classification
- `repo_provider/`: provider-neutral repo-provider config, registry, command dispatch, errors, and adapter support
- `repo_provider/invocation/`: repo-provider CLI invocation parsing for command routing, option groups, body files, and field projection
- `repo_provider/smoke/`: repo-provider smoke orchestration, probe execution, and CNB auto-provision workflow internals
- `repo_provider/<kind>/`: repo-provider-specific adapters, clients, handlers, and normalizers
- `agent/`: provider-neutral Agent run lifecycle, continuation, runtime context, and failure classification
- `agent/dynamic_tool/`: provider-neutral Dynamic Tool context capture, workflow-required tool planning, inventory rendering, bridge execution, policy, usage classification, source aggregation, and spec normalization
- `agent/credential/accounts/`: managed account login, import, verification, lifecycle, environment, and provider callback internals
- `agent/runner/`: Agent runner internals for run execution, worker workspace attempts, provider session loops, turn loops, run context shaping, prompt construction, worker update forwarding, event fields, turn event mapping, run terminal events, provider session cleanup, and provider-option projection
- `agent/runtime.ex`: provider-neutral runtime target resolution and runtime context facade
- `agent/runtime/`: runtime target data, command contracts, dynamic-tool runtime bridges, and execution-environment helpers
- `agent/runtime/executor/`: executor behaviour implementations for local, SSH, and worker-daemon placements
- `agent/runtime/worker_daemon/`: worker-daemon runtime subsystem for endpoint safety, pool resolution, client calls, supervised event streams, and session handles
- `agent/runtime/worker_daemon/client/`: worker-daemon client implementation for connection resolution, HTTP transport, health/preflight checks, session creation, and session operations
- `agent_provider/`: AI coding-agent provider facade, registry, adapter contract, config resolution, shared provider settings normalization and validation, session lifecycle, runtime-start validation, event/session/usage shapes, message routing, and workspace preparation
- `agent_provider/app_server/`: provider-neutral app-server support for callback message emission, structured event-field assembly, and provider process metadata
- `agent_provider/event_summary_mapper/`: provider-neutral event-summary mapping primitives for nested payload access and compact text formatting
- `agent_provider/<kind>/`: one concrete AI coding-agent integration, including provider-specific message summary mapping
- `platform/`: low-level process and SSH transport primitives
- `observability/event_store/`: bounded event-store config, state, index, query, input normalization, and mailbox pressure internals
- `observability/log_file/`: log sink path, runtime config, handler, formatter, and sink-event implementation
- `observability/status_dashboard/`: dashboard presentation, throughput, rate, and drill-down logic

The intent is simple: keep the public API surface easy to find, and keep the
implementation logic close to the owning domain.

## Directory Responsibility Map

The table below is the quickest way to decide where code belongs.

| Path | Owns | Good fit | Keep out | Current examples |
| --- | --- | --- | --- | --- |
| `application.ex` | OTP application boot | supervisor startup wiring | domain logic, parsing, transport details | `SymphonyElixir.Application` |
| `cli.ex` | escript entrypoint | top-level CLI argument flow and boot handoff | subcommand parsing, orchestration internals, tracker client code | `SymphonyElixir.CLI` |
| `cli/` | CLI subcommand implementation | subcommand facades, command parsing, option resolution, command routing, token source handling, output rendering | domain execution internals, tracker transport, provider protocol handling | `CLI.Accounts`, `CLI.Accounts.Parser`, `CLI.Accounts.TokenSource`, `CLI.Accounts.Renderer`, `CLI.Repo.Runner` |
| `config.ex` | public config facade | stable config API, high-level validation entrypoints | schema helpers, normalization internals, formatting helpers | `SymphonyElixir.Config` |
| `config/` | config implementation | schema aggregation, defaults, finalization, normalization, error shaping | workflow loading, tracker HTTP, runtime orchestration | `Schema`, `InputNormalizer`, `SettingsFinalizer`, `SandboxPolicy` |
| `config/schema/` | embedded config schema internals | domain-specific schema casting and validation for tracker, repo, agent, runtime, provider, observability, hooks, server settings, and state limits | workflow profile resolution, provider runtime clients, tracker HTTP | `Tracker`, `AgentRuntime`, `Repo`, `AgentProvider`, `Observability`, `StateLimits` |
| `workflow.ex` | public workflow facade | workflow access entrypoints | prompt rendering internals, route policy internals, store lifecycle details | `SymphonyElixir.Workflow` |
| `workflow/` | workflow implementation | prompt builder, route policy, workflow store, workflow-profile resolution, execution-profile registry loading, entry matching, selection, and validation | config schema logic, tracker vendor code | `PromptBuilder`, `RoutePolicy`, `Store`, `ExecutionProfileRegistry.Selection` |
| `issue.ex` | core issue model | normalized issue struct and issue-level accessors | tracker API code, lifecycle coordination | `SymphonyElixir.Issue` |
| `issue/` | issue domain helpers | issue lifecycle interpretation or issue-specific policy | orchestrator loop control, tracker HTTP | `Lifecycle` |
| `tracker.ex` | tracker boundary facade | behaviour, adapter lookup, shared facade calls | vendor-specific request building, response normalization | `SymphonyElixir.Tracker` |
| `tracker/` | provider-neutral tracker internals | config access, registry, kind identifiers, normalized errors, serialization, project refs, smoke validation, memory adapter | tracker-vendor transport details, repo-provider behavior | `Config`, `ConfigAccess`, `Kinds`, `Registry`, `Error`, `ProjectRef`, `Smoke` |
| `tracker/<kind>/` | one tracker integration | adapter, client facade, query definitions, transport helpers, pagination, provider-option extraction, payload decoding, ID lookup, relation enrichment, error classification, normalizer, codecs and codec internals, dynamic-tool executor internals, tracker-specific workspace preparation, tracker-specific workflow helpers | orchestrator state machine code, generic workspace logic, test-only client forwarding APIs for internal reader or pagination modules | `Linear.Adapter`, `Linear.GraphQL`, `Linear.IssueReader`, `Tapd.Client.Reader`, `Tapd.Client.Request`, `Tapd.WorkspacePreparation`, `Tapd.CommentCodec`, `Tapd.CommentCodec.DescriptionEncoder`, `Tapd.ToolExecutor.TypedTools` |
| `repo.ex` | repository boundary facade | stable repository API for branch, status, preflight, and Git-backed operations | Git command mechanics, repo-provider API calls, tracker behavior | `SymphonyElixir.Repo` |
| `repo/` | provider-neutral repository internals | branch/status/error data, preflight checks, Git facade, repository context helpers, Dynamic Tool repo context resolution | raw Git command execution, repo-provider transport details, tracker workflow behavior, orchestration state | `Branch`, `Status`, `Error`, `Preflight`, `Git`, `DynamicToolContext` |
| `repo/git/` | Git implementation internals | command execution, scoped arguments, Git config projection, argument builders, repository inspection, remote/clone/push operations, branch/merge operations, commit/stage operations, status parsing, reference parsing, error classification, invocation validation | public repository API expansion, repo-provider adapter behavior, workflow/orchestrator policy | `Command`, `Arguments`, `Inspection`, `Remote`, `Branches`, `Commits`, `StatusParser`, `References`, `Errors`, `Validation` |
| `repo_provider.ex` | repo-provider boundary facade | adapter lookup, capability checks, public repo-provider operations | provider-specific API calls, workflow text, CLI parsing details | `SymphonyElixir.RepoProvider` |
| `repo_provider/` | provider-neutral repo-provider internals | config access, registry, kind identifiers, normalized check-run helpers, command dispatch, result/output shaping, errors, land-watch orchestration, smoke orchestration | tracker behavior, provider-specific API details | `Config`, `ConfigAccess`, `Kinds`, `CheckRun`, `Registry`, `Command`, `LandWatch`, `Error` |
| `repo_provider/cli/` | repo-provider CLI runtime adapter internals | environment loading, runtime config resolution, invocation evaluation, observability events, and CLI result tuples | argv option parsing, command execution internals, provider-specific transport | `CLI.Evaluator` |
| `repo_provider/command/` | repo-provider command execution internals | parsed invocation option projection, command-specific result rendering, watch loops, and exit-code policy | argv parsing, provider-specific transport, shell command execution | `Command.Options`, `Command.Checks` |
| `repo_provider/invocation/` | repo-provider CLI invocation parser internals | provider override parsing, command routing, PR/API/run option parsing, body-file reads, JSON field lists | provider adapter execution, output rendering, shell command execution | `CommandParser`, `PullRequest`, `Reviews`, `Api`, `Runs`, `Options` |
| `repo_provider/smoke/` | repo-provider smoke test implementation | probe construction/execution, mode selection, smoke report rendering, event emission, destructive smoke flows, CNB auto-provision context, git setup, PR flow, run polling, and cleanup | provider adapter API clients, generic CLI parsing, tracker behavior | `Smoke.ProbeRunner`, `Smoke.ReadOnly`, `Smoke.Destructive`, `Smoke.Report`, `Smoke.CNBProvisioner.Context`, `Smoke.CNBProvisioner.PRFlow` |
| `repo_provider/<kind>/` | one repo-provider integration | adapter, client, handler facades and focused handler submodules, base branch resolution, normalizer facade and focused normalizer submodules, provider-specific command execution, runtime HTTP option parsing | tracker transport, generic orchestrator policy | `GitHub.Adapter`, `CNB.HttpClient`, `CNB.PullRequestHandler.Resolution`, `CNB.ApiHandler.Router`, `CNB.Normalizer.Pull` |
| `agent.ex` | provider-neutral Agent facade | stable run entrypoint | provider-specific CLI/app-server code, orchestrator GenServer state | `SymphonyElixir.Agent` |
| `agent/` | provider-neutral Agent run lifecycle | workspace run flow, continuation, runtime context, generic failure classification | concrete AI agent protocol handling, tracker adapters, test-only wrappers around runner internals | `Runner`, `Continuation`, `FailureClassifier`, `DynamicTool.Context` |
| `agent/dynamic_tool/` | provider-neutral Dynamic Tool implementation | source context capture, workflow-required tool allowlist planning, provider-facing inventory rendering, side-effect policy, bridge execution, usage classification, source aggregation, spec normalization | tracker/repo-provider business semantics, provider-native tool registration details | `Context`, `WorkflowPlan`, `Inventory`, `Bridge`, `Policy`, `Usage`, `CompositeSource`, `Spec` |
| `agent/credential/accounts.ex` | managed account facade | public account login/import/list/verify/lifecycle API and provider-kind normalization entrypoint | provider command execution, file import mechanics, adapter callback dispatch | `SymphonyElixir.Agent.Credential.Accounts` |
| `agent/credential/accounts/` | managed account implementation | provider-kind normalization, account login/import, verification command execution, lifecycle Store calls, credential environment shaping, secret file operations, provider callback dispatch | CLI parsing, provider session protocol clients, orchestrator policy | `Login`, `Import`, `Verification`, `Lifecycle`, `Environment`, `Command`, `Secret`, `ProviderKind`, `ProviderCallbacks`, `Options` |
| `agent/runner/` | Agent runner implementation internals | run execution, worker workspace attempts, provider session loops, turn loops, run context shaping, prompt construction, worker update forwarding, event field projection, turn event/error mapping, run terminal event emission, provider session cleanup, provider-option projection | provider protocol clients, orchestrator GenServer state, tracker adapters | `Execution`, `WorkerAttempt`, `SessionLoop`, `TurnLoop`, `RunContext`, `Prompts`, `WorkerUpdates`, `EventFields`, `TurnEvents`, `RunEvents`, `SessionCleanup`, `ProviderOptions` |
| `agent/runtime.ex` | runtime target facade | target resolution, runtime context shaping, worker-daemon endpoint selection handoff | executor implementation details, daemon HTTP calls, provider protocol logic | `SymphonyElixir.Agent.Runtime` |
| `agent/runtime/` | provider-neutral runtime implementation | target structs, command specs, runtime environment, dynamic-tool bridge entrypoint | concrete provider protocol parsing, tracker/repo-provider adapters, daemon server code | `Target`, `CommandSpec`, `Environment`, `DynamicToolBridge` |
| `agent/runtime/dynamic_tool_bridge/` | Dynamic Tool bridge runtime implementation | captured source env extraction, bridge transport selection, SSH tunnel lifecycle, worker-daemon bridge spec construction | Dynamic Tool core execution, provider-specific tool registration, daemon server proxy implementation | `Environment`, `Transport` |
| `agent/runtime/executor/` | executor adapters | implementations of `Agent.Runtime.Executor` for one placement | endpoint pool state, daemon client internals, provider command generation | `Local`, `SSH`, `WorkerDaemon` |
| `agent/runtime/worker_daemon/` | worker-daemon runtime subsystem | endpoint validation, safe endpoint display, pool resolution, health/circuit state, daemon client API, session handles, supervised event polling | provider-specific behavior, daemon server implementation, tracker/repo-provider/workflow logic | `Endpoint`, `PoolResolver`, `EndpointState`, `Client`, `SessionHandle`, `EventStream` |
| `agent/runtime/worker_daemon/client/` | worker-daemon client implementation | endpoint/token resolution, request transport, health/preflight validation, session creation/reconciliation, session filtering, session status/events/input/stop/cleanup calls | executor placement policy, pool failover, daemon server behavior, provider-specific protocol mapping | `Connection`, `Transport`, `Health`, `SessionCreate`, `Session`, `Filters` |
| `agent_provider.ex` | AI agent-provider facade | adapter lookup and public provider operations | provider protocol details, workspace creation, orchestration state | `SymphonyElixir.AgentProvider` |
| `agent_provider/` | provider-neutral AI agent-provider internals | adapter contract, registry, config resolution, shared provider settings normalization and validation, capabilities, session lifecycle, runtime-start validation, event/session/usage data shapes, event-summary shape, shared message presentation, message routing, workspace preparation, provider-owned workspace automation destination selection | concrete provider protocol parsing, execution loop control, bundled automation source resolution, provider-specific settings semantics | `Adapter`, `Registry`, `ConfigResolver`, `SettingsNormalizer`, `Capabilities`, `SessionLifecycle`, `RuntimeStart`, `EventFields`, `MessageRouting`, `WorkspacePreparation`, `Session`, `Usage` |
| `agent_provider/app_server/` | provider-neutral app-server support | callback message emission, issue-title formatting, structured event-field assembly, prompt/stream summaries, provider process metadata, turn-context metadata merging | provider protocol parsing, process startup, provider-specific message redaction, provider-specific lifecycle events | `Messages`, `EventFields`, `PortMetadata` |
| `agent_provider/event_summary_mapper/` | event-summary mapping primitives | nested payload access, reason/usage formatting, compact text normalization shared by provider mappers | provider-specific event taxonomy, provider protocol parsing, dashboard rendering | `Access`, `Text` |
| `agent_provider/<kind>/` | one AI coding-agent integration | adapter, CLI/app-server client, event mapping, provider-specific credential environment contracts, provider-specific failure classification, provider-specific message summary mapping | provider-neutral execution lifecycle, orchestrator state machine | `Codex.Adapter`, `Codex.CredentialEnv`, `Codex.EventSummaryMapper`, `ClaudeCode.CredentialEnv`, `ClaudeCode.EventSummaryMapper`, `OpenCode.EventSummaryMapper` |
| `agent_provider/<kind>/app_server/` | provider app-server/client internals | command launch, protocol writes/reads, turn request handling, usage extraction, provider event-field base context, provider-specific callback payload shaping, process cleanup | adapter option finalization, provider-neutral runtime target selection policy, shared dashboard rendering, shared callback/metadata helpers | `Codex.AppServer.Launcher`, `ClaudeCode.AppServer.StreamProtocol`, `OpenCode.AppServer.EventStream` |
| `agent_provider/<kind>/tooling/` | provider workspace tooling internals | provider-owned config rendering, generated source rendering, remote bootstrap scripts, tool file manifests, provider-visible tool spec shaping | provider-neutral Dynamic Tool execution, credential materialization, workspace lifecycle policy | `ClaudeCode.Tooling.McpConfig`, `AgentProvider.PlannedToolMcpServer.Protocol`, `OpenCode.Tooling.Manifest`, `OpenCode.Tooling.PlannedToolPlugin.SchemaRenderer` |
| `workspace.ex` | workspace facade | public create/remove entrypoints | path helpers, hook execution details, remote shell composition | `SymphonyElixir.Workspace` |
| `workspace/` | workspace lifecycle implementation | path derivation, remote boundary validation, repo-local git-exclude editing, bundled automation source resolution, bootstrap, hook execution, remote operations, cleanup | tracker-specific API logic, generic orchestrator retry policy, concrete provider protocol handling | `Paths`, `GitExclude`, `AutomationPack`, `Bootstrap`, `Hooks`, `Remote`, `Cleanup` |
| `platform/` | low-level platform primitives | process metadata and termination, SSH host normalization, SSH command execution, remote port forwarding, shell quoting | workspace lifecycle policy, tracker/repo/provider behavior, observability formatting | `Platform.Process`, `Platform.SSH` |
| `orchestrator.ex` | orchestrator public/stateful entry | GenServer callbacks, API boundary, thin coordination | large helper clusters for polling, issue dispatch execution, retry, running-state mutation, test-only wrappers around internals | `SymphonyElixir.Orchestrator` |
| `orchestrator/` | orchestration internals | poll-cycle coordination, server callback option assembly, polling timers, issue dispatch execution, launch, snapshots, worker-host policy, runtime context, agent update integration, worker exit message handling, ignored-message logging, runtime state construction, usage accounting, cleanup | tracker-specific transport code, dashboard rendering, large dispatch-policy, retry, or running-state helper clusters | `PollCycle`, `Polling`, `ServerOptions`, `AgentUpdates`, `IgnoredMessage`, `Dispatch`, `IssueDispatch`, `Retry`, `Running`, `Runtime`, `WorkerExit`, `State`, `AgentUsage`, `TerminalCleanup` |
| `orchestrator/dispatch/` | dispatch policy implementation | dispatch context construction, candidate ordering, eligibility and skip-reason checks, runtime slot projection, pre-dispatch issue revalidation, route preparation | GenServer state mutation, tracker transport, agent execution, dashboard rendering | `Dispatch.Context`, `Dispatch.Ordering`, `Dispatch.Eligibility`, `Dispatch.RuntimeView`, `Dispatch.Revalidation`, `Dispatch.RoutePreparation` |
| `orchestrator/retry/` | retry implementation | retry timer scheduling, retry timer message handling, retry attempt metadata shaping, retry event emission, retry candidate lookup, retry release/defer decisions, and redispatch handoff | dispatch eligibility policy, worker-exit classification, running-entry lifecycle state, tracker transport | `Retry.Scheduler`, `Retry.MessageHandler`, `Retry.Metadata`, `Retry.Events`, `Retry.IssueHandler` |
| `orchestrator/running/` | running issue lifecycle implementation | issue-state reconciliation, inactive completion grace decisions, stalled-run detection, task termination and claim cleanup, running/claimed/retry state access, and reconcile event emission | dispatch eligibility policy, retry scheduling policy, worker-exit classification, tracker transport | `Running.Reconciliation`, `Running.InactiveGrace`, `Running.StallDetection`, `Running.Termination`, `Running.StateView`, `Running.Events` |
| `observability/` | shared observability infrastructure | event envelope, shared field registry, event store, formatter, redaction, generic logging | dashboard-specific rendering rules, tracker business logic | `Fields`, `Logger`, `EventStore`, `Formatter`, `Redaction` |
| `observability/event_store.ex` | structured event-store facade | public event recording/query API and GenServer boundary | state struct details, index mutation, input normalization, query projection, mailbox pressure accounting | `SymphonyElixir.Observability.EventStore` |
| `observability/event_store/` | bounded event-store implementation | event-store config normalization, state construction/resizing, bounded indexes, query projection, input normalization, mailbox pressure accounting | generic logger emission, dashboard rendering, provider protocol semantics | `Config`, `State`, `Index`, `Query`, `InputNormalizer`, `PendingQueue` |
| `observability/log_file.ex` | log sink facade | public log-file path and logger sink configuration entrypoints | console/file handler mechanics, formatter template construction, sink event assembly | `SymphonyElixir.Observability.LogFile` |
| `observability/log_file/` | log sink runtime implementation | default path construction, runtime config loading, console handler capture/update, rotating file handler orchestration, file formatter config, sink lifecycle events | generic event envelope, event-store retention, dashboard rendering, provider protocol details | `PathConfig`, `RuntimeConfig`, `ConsoleHandler`, `FileHandler`, `FormatterConfig`, `SinkEvent` |
| `observability/status_dashboard.ex` | status dashboard facade | public dashboard entrypoints and GenServer boundary | snapshot collection, render queue mechanics, terminal rendering, link option assembly, provider protocol parsing, test-only forwarding APIs for dashboard internals | `SymphonyElixir.Observability.StatusDashboard` |
| `observability/status_dashboard/` | dashboard presentation and runtime implementation | presenter logic, drill-down, throughput, rate-limit summaries, snapshot payload shaping, render queue, terminal renderer, runtime config, dashboard link options, render failure events | generic logger infrastructure, tracker adapters | `Presenter`, `Drilldown`, `Throughput`, `RateLimits`, `Snapshot`, `RenderQueue`, `Terminal`, `RuntimeConfig`, `PresenterOptions`, `RenderFailure` |
| `http_server.ex` | web server boundary | endpoint boot and config handoff | controller/view logic, dashboard presentation details | `SymphonyElixir.HttpServer` |
| `path_safety.ex` | focused shared primitive | path canonicalization and safety logic | workspace lifecycle policy, tracker integration | `SymphonyElixir.PathSafety` |
| `specs_check.ex` | repository-specific tooling boundary | spec-check support code | runtime orchestration or business logic | `SymphonyElixir.SpecsCheck` |

## Placement Rules

- If a change belongs to an existing domain, put it under that domain's namespace first.
- Do not create a new top-level file when a matching namespace already exists for that concern.
- Keep root facade modules small enough that their role stays obvious:
  - public API
  - lightweight coordination
  - delegation
  - minimal validation or result shaping when it clarifies the API
- Test coverage should call the owning internal module directly or use
  test-source helpers; do not add test-only wrapper functions to production
  facades.
- Move parsing, formatting, rendering, state mutation helpers, remote execution helpers, and vendor-specific code out of facades and into submodules.
- Tracker-specific code belongs under `tracker/<kind>/`, never in `orchestrator/`, `workspace/`, or generic top-level files.
- Tracker-specific workspace preparation belongs under `tracker/<kind>/`; generic workspace primitives such as git-exclude editing may stay under `workspace/`.
- Provider-neutral tracker support belongs under `tracker/` with responsibility names such as `ConfigAccess`; do not move it into a top-level shared helper module.
- Provider-neutral repository API and data shapes belong under `repo/`; Git command mechanics belong under `repo/git/`.
- Repo-provider-neutral support belongs under `repo_provider/`; provider-specific code belongs under `repo_provider/<kind>/`.
- Repo-provider command-line handling is layered:
  - `repo_provider/invocation/` parses argv into `%RepoProvider.Invocation{}`.
  - `repo_provider/command.ex` and `repo_provider/command/` execute parsed
    command semantics and shape command-specific results.
  - `repo_provider/cli/` adapts that execution to a CLI runtime by loading env,
    resolving runtime config, emitting evaluator-level observability events, and
    returning stdout/stderr/exit-code tuples.
  Keep these layers separate so parser code does not execute provider actions,
  command execution does not own process IO, and CLI adapters stay reusable by
  smoke runners or future non-escript entrypoints.
- Provider-neutral AI agent run lifecycle belongs under `agent/`.
- Provider-neutral AI agent adapter contracts and registry logic belong under `agent_provider/`.
- Provider settings normalization and validation that is identical across at
  least two concrete providers belongs under `agent_provider/`; provider-specific
  options stay in `agent_provider/<kind>/settings.ex`.
- Provider app-server support that is identical across at least two concrete
  providers belongs under `agent_provider/app_server/`; provider protocol
  parsing, startup, and provider-specific payload shaping stay under
  `agent_provider/<kind>/app_server/`.
- Provider-neutral event-summary mapper primitives belong under
  `agent_provider/event_summary_mapper/` only when they have no provider event
  taxonomy, no provider protocol semantics, and at least two provider mappers
  use them.
- Concrete AI coding-agent integrations belong under `agent_provider/<kind>/`.
- Provider-neutral runtime target selection, command contracts, and execution
  environment logic belong under `agent/runtime/`.
- Executor behaviour implementations belong under `agent/runtime/executor/`.
- Worker-daemon endpoint safety, pool resolution, daemon client calls, session
  handles, and event-stream lifecycle belong under `agent/runtime/worker_daemon/`.
- Do not move `agent/runtime/worker_daemon/` under `agent/runtime/executor/`.
  The executor module is a thin adapter; the worker-daemon subsystem owns
  shared runtime concerns used before and after executor start.
- Dispatch context, issue ordering, eligibility checks, skip reasons, runtime
  slot projection, revalidation, and route-preparation policy belong under
  `orchestrator/dispatch/`; keep `orchestrator/dispatch.ex` as the facade used
  by orchestration callers.
- Retry timer scheduling, retry timer message handling, attempt metadata
  shaping, retry events, retry issue lookup, retry release/defer decisions, and
  redispatch handoff belong under `orchestrator/retry/`; keep
  `orchestrator/retry.ex` as the facade used by orchestration callers.
- Running issue reconciliation, inactive completion grace, stalled-run
  detection, task termination, claim cleanup, running/retry state access, and
  reconcile events belong under `orchestrator/running/`; keep
  `orchestrator/running.ex` as the facade used by orchestration callers.
- Complete poll-cycle coordination belongs in `orchestrator/poll_cycle.ex`.
  Polling timer mechanics and refresh requests stay in
  `orchestrator/polling.ex`.
- GenServer callback option assembly, agent-update option sets, retry-message
  option sets, retry-issue option sets, running option sets, terminal-cleanup
  option sets, dashboard notification callbacks, issue-claim release callbacks,
  and workspace cleanup callbacks belong in `orchestrator/server_options.ex`.
- Worker runtime info updates, agent worker update integration, token/rate-limit
  state application, and the resulting dashboard notification hook belong in
  `orchestrator/agent_updates.ex`.
- Worker `:DOWN` message handling, running-entry removal, session completion
  accounting, exit classification, continuation/retry scheduling, and the
  resulting dashboard notification hook belong in `orchestrator/worker_exit.ex`.
- Ignored GenServer message logging and payload summary construction belong in
  `orchestrator/ignored_message.ex`.
- Orchestrator state struct defaults and initial runtime state construction
  belong in `orchestrator/state.ex`.
- Event-store state, bounded index, query projection, input normalization, and
  mailbox pressure mechanics belong under `observability/event_store/`; keep
  `observability/event_store.ex` as the public GenServer facade.
- Log sink path, handler, formatter, and sink lifecycle-event mechanics belong
  under `observability/log_file/`; keep `observability/log_file.ex` as the
  public facade.
- Dashboard rendering belongs under `observability/status_dashboard/`; provider-neutral agent-message presentation belongs under `agent_provider/message_presenter.ex`.
- Workflow prompt building, workflow parsing, and route policy belong under `workflow/`.
- Runtime config schema, defaulting, normalization, and semantic validation belong under `config/`.
- SSH host normalization, target composition, and remote-shell details belong under `platform/ssh.ex`.
- Generic workspace lifecycle logic belongs under `workspace/`, even when it calls SSH or tracker adapters.
- Generic shared infrastructure belongs in a broad namespace only when at least two domains genuinely need the same abstraction.
- Do not move domain logic into `observability/`, `agent_provider/<kind>/`, or other cross-cutting namespaces just because those paths are already present in the call chain.

## Test Isolation Rules

Use `async: true` only for tests that stay within local data, temporary paths,
pure functions, or isolated processes owned by the test. Keep a test synchronous
when it mutates process-wide runtime state or depends on named application
processes.

In practice, tests must stay synchronous when they:

- call `Application.put_env/3` or `Application.delete_env/2`
- terminate or restart supervised children under `SymphonyElixir.Supervisor`
- inspect named application processes such as the orchestrator, PubSub, root
  supervisor, or workflow runtime store
- reserve a TCP port before starting a server with that port
- use `SymphonyElixir.TestSupport`, because that helper manages process-wide
  application env and supervised runtime processes

These rules are enforced by
[`test/symphony_elixir/repo_architecture_test.exs`](../test/symphony_elixir/repo_architecture_test.exs).

## What May Stay At The Top Level

A top-level file in `lib/symphony_elixir/` is acceptable when it is one of these:

- A stable public facade for a larger namespace
- A small OTP or CLI entry module
- A narrow shared primitive with clear ownership, such as a core struct or a focused safety utility
- A boundary module that integrates an external framework or repository-specific tool

Top-level files are not the right place for:

- domain-specific helper clusters
- formatting and rendering helpers
- vendor-specific adapters
- remote/local execution branches
- modules whose only purpose is to hold code extracted from an oversized facade

If logic is growing because a domain is becoming richer, that is a signal to
expand the domain namespace, not the top level.

## Worker Daemon Runtime Boundary

The worker-daemon runtime has two related but different code locations:

- `agent/runtime/executor/worker_daemon.ex` implements the
  `Agent.Runtime.Executor` behaviour for `:worker_daemon` placement. It starts,
  stops, and checks liveness for an already resolved worker-daemon target.
- `agent/runtime/worker_daemon/` is the runtime subsystem shared by target
  resolution, executor start, session lifecycle, event forwarding, and
  administrative client calls.

Keep these responsibilities separate. Endpoint normalization, safe endpoint
display, pool candidate collection, health cache/circuit state, daemon HTTP
client calls, session handles, and supervised event streams are not private
helpers of one executor callback. They may be used before the executor starts
and after it stops, so they belong in `agent/runtime/worker_daemon/`.
`agent/runtime/worker_daemon/pool_resolver/` owns worker-daemon pool candidate
collection, de-duplication, target metadata projection, selection payloads, and
rejection reason shaping. Keep `PoolResolver` focused on the candidate
selection flow and health-state coordination.

`agent/runtime/worker_daemon/client.ex` is the Maestro-side daemon client
entrypoint. Its implementation modules live under
`agent/runtime/worker_daemon/client/` and are organized by responsibility:
connection resolution, request transport, health/preflight validation, session
creation, filters, and session operations. Code outside that client boundary
should call `WorkerDaemon.Client` instead of reaching into those implementation
modules.

Do not split the worker-daemon client by file length alone. `SessionCreate`,
`Health`, `Session`, `Connection`, `Transport`, `SessionRequest`, and `Filters`
should stay aligned with stable client responsibilities. Extract a new module
only when it owns an independent contract, state lifecycle, or policy used by
more than one caller. When a client responsibility is cohesive, prefer targeted
tests, explicit guards, and boundary documentation over adding smaller modules.

Worker-daemon event streams are part of the provider-facing runtime boundary,
not just daemon transport plumbing. When they forward daemon output into
provider app-server mailbox messages, they must preserve local Port `:line`
semantics: complete lines use `{:eol, line}` without the newline terminator, and
unfinished chunks use `{:noeol, chunk}` until later output completes the line.

The worker-daemon server implementation remains separate in the
`SymphonyWorkerDaemon` namespace under `lib/symphony_worker_daemon/`. Agent
providers continue to own provider-specific command generation, environment
assembly, prompt protocol, app-server behavior, and provider event mapping.
The worker-daemon runtime must stay provider-neutral.

`lib/symphony_worker_daemon/` owns the daemon server OTP application boundary:
Plug API routing, daemon auth, request and event protocol validation, session
supervision, session state, process execution, workspace validation and cleanup,
capacity and rate limiting, orphan cleanup, and dynamic-tool bridge proxying.
It must not own the Maestro-side daemon client, provider-specific protocol
mapping, tracker policy, repository policy, workflow policy, or orchestrator
dispatch policy.

Root daemon modules remain entrypoints for their subdomains. Focused support
belongs under matching namespaces: `application/` owns daemon supervision child
assembly; `auth/` owns authorization policy, client principal normalization,
bearer-token parsing, safe token comparison, and shared value normalization;
`capacity_manager/` owns lease state helpers, capacity option normalization,
capacity status projection, and tenant key derivation; `cli/` owns daemon CLI
argument parsing, startup output, and server child specs; `command_policy/`
owns executable allowlist preparation, executable validation, and capability
payloads; `config/` owns listen address resolution, worker identity resolution,
CLI option parsing, authentication option resolution, policy projection, and
workspace-root normalization; `workspace_manager/` owns workspace path
normalization and cleanup target guards; `orphan_sweeper/` owns restart orphan
candidate checks, ledger recording, process-control wrappers, and sweep result
aggregation; `process_runner/` owns provider process environment and stop-option
projection; and `rate_limiter/` owns bucket state calculations, pruning, and
request limit option projection.

Dynamic-tool bridge proxy internals belong under
`lib/symphony_worker_daemon/bridge_proxy/` in the
`SymphonyWorkerDaemon.BridgeProxy` namespace. `BridgeProxy` owns the proxy
process lifecycle, loopback server startup, provider environment projection,
and request-to-proxy startup flow. `BridgeProxy.RouterPlug` owns the loopback
HTTP API, provider authentication, request size guards, and upstream forwarding.
`BridgeProxy.UpstreamPolicy` owns upstream base URL normalization, allowlist
projection, DNS/IP resolution, and address class policy. `BridgeProxy.ProxyOptions`
owns startup option projection, provider environment variables, and upstream
token validation. `BridgeProxy.PortReservation` owns loopback port allocation.
`BridgeProxy.Requester` owns outbound upstream HTTP requests and final request
URL shape validation before transport.

Session modules belong under `lib/symphony_worker_daemon/session/` in the
`SymphonyWorkerDaemon.Session` namespace. `Session.Supervisor` owns dynamic
session supervision, session creation, live lookup, and live-plus-ledger list
aggregation. `Session.Server` remains the GenServer owner for a single session
lifecycle, process control, timeout handling, capacity release, bridge proxy
shutdown, and ledger recording. It tracks released resources in session state so
stop, cleanup, and terminate paths do not repeat resource actions.
`Session.Ledger` owns session summary storage,
persistence health, and ledger-backed session lookup. `Session.Filters` owns
shared list filtering for live and ledger-backed session summaries. Focused
ledger support belongs under `session/ledger/`: `Session.Ledger.Summary` owns
summary normalization and status projection; `Session.Ledger.Persistence` owns
ledger file loading and persistence writes; and `Session.Ledger.Health` owns
persistence health payload shaping. Focused state helpers belong under
`session/server/`: `Session.Server.Events` owns output event
buffering, redaction, event ids, and bounded event-window projection;
`Session.Server.Payloads` owns status and summary payload projection;
`Session.Server.RequestFingerprint` owns stable request fingerprinting; and
`Session.Server.ResourceBudget` owns output buffer limit resolution from daemon
options and request resource budgets. `Session.Server.TimeoutPolicy` owns
timeout policy parsing while timer scheduling stays in `Session.Server`.
`Session.Server.ProviderEnvironment` owns provider environment assembly, and
`Session.Server.Options` owns daemon option projection for runner, command
policy, and bridge proxy calls. `Session.Server.Request` owns request shape
projection for workspace and command payloads, and `Session.Server.Status` owns
terminal status name and stop-reason projection. Keep these support modules free
of process ownership and external side effects.

The daemon API router remains the `SymphonyWorkerDaemon.Api` entrypoint.
Responsibility-specific API support belongs under `lib/symphony_worker_daemon/api/`.
`SymphonyWorkerDaemon.Api.Response` owns JSON response shaping, redacted error
payloads, and mutation error-to-status mapping. `SymphonyWorkerDaemon.Api.Health`
owns daemon health payload assembly and feature advertisement.
`SymphonyWorkerDaemon.Api.Audit` owns daemon API audit fields and event
emission. `SymphonyWorkerDaemon.Api.RateLimit` owns API request rate-limit
decisions and responses. `SymphonyWorkerDaemon.Api.SessionAccess` owns
session lookup, session authorization, and ledger-backed session lookup.
`SymphonyWorkerDaemon.Api.RequestLimits` owns request header and body size
guards. `SymphonyWorkerDaemon.Api.RequestParams` owns API request parameter
projection for body, filter, and protocol limit inputs.
`SymphonyWorkerDaemon.Api.SessionOptions` owns daemon option projection for
session startup. `SymphonyWorkerDaemon.Api.SessionCreate` owns create-session
error response mapping and audit emission for denied create attempts.
`SymphonyWorkerDaemon.Api.SessionCleanup` owns ledger-backed cleanup handling.
Keep route matching, request authorization, and session dispatch in the router
or in explicitly named API support modules; do not hide those behaviors in
broad generic helpers.

Create-session request construction from
`SymphonyElixir.Agent.Runtime.CommandSpec` and
`SymphonyElixir.Agent.Runtime.Target` belongs under the runtime client namespace,
for example `agent/runtime/worker_daemon/client/session_request.ex`. The
`SymphonyWorkerDaemon.Protocol` module is the shared wire contract surface for
protocol constants, endpoint paths, server-side request validation, response
normalization, and protocol error shaping. It must not depend on
`SymphonyElixir.Agent.Runtime` structs or other high-level Maestro contexts.
Protocol implementation details belong under `lib/symphony_worker_daemon/protocol/`:
`SymphonyWorkerDaemon.Protocol.Paths` owns endpoint path construction,
`SymphonyWorkerDaemon.Protocol.QueryParams` owns query-string construction,
`SymphonyWorkerDaemon.Protocol.Request` owns client request payload construction,
`SymphonyWorkerDaemon.Protocol.Response` owns daemon response normalization,
terminal status checks, and protocol error shaping, and
`SymphonyWorkerDaemon.Protocol.Validation` owns server-side request validation
for create, input, stop, and cleanup operations. Validation support modules
under `protocol/validation/` own field-shape checks and payload size
calculation. Keep `SymphonyWorkerDaemon.Protocol` as the stable wire contract
entrypoint.

When this area grows, add explicitly named modules under
`agent/runtime/worker_daemon/`. Do not turn the executor adapter into a
subsystem owner, and do not move daemon server code into the
`SymphonyElixir.Agent.Runtime` namespace.

## Refactor Triggers

Treat these as practical triggers to split or relocate code:

- A root facade starts carrying long private helper sections.
- A module needs comments just to explain which part is parsing, which part is rendering, and which part is state mutation.
- One file owns both policy decisions and execution mechanics.
- Local and remote execution paths are intertwined in the same helper chain.
- One domain starts knowing too much about another domain's vendor-specific payload shape.
- Tests would become clearer if one cluster of helpers had a direct module name.
- A review comment says "this feels like it belongs elsewhere" and the answer requires more than one sentence.

These are especially strong signals in:

- `orchestrator.ex`
- `workspace.ex`
- `observability/status_dashboard.ex`
- any tracker adapter file

## When To Split A Module

Split a module into a namespace when one or more of these are true:

- The file mixes multiple responsibilities.
- The private helper section is large enough to name coherent sub-responsibilities.
- The code has clear execution modes such as local/remote, polling/dispatch, render/present, or adapter/client/normalizer.
- The module is accumulating unrelated conditionals just to keep one public API file alive.
- A new area would be easier to test in isolation as a dedicated module.

When splitting:

- Preserve the existing public API when it already acts as the stable entrypoint.
- Move responsibility-specific logic into modules with names that describe the behavior directly.
- Keep module names aligned with their path.
- Update docs and tests in the same change when the structure meaningfully changes.

Prefer extracting by responsibility, not by arbitrary size. A split such as
`Workspace.Paths`, `Workspace.Hooks`, and `Workspace.Cleanup` is good because
each module answers a distinct question. A split such as `Workspace.Part1` and
`Workspace.Part2` is not acceptable.

## Naming Rules

- Prefer explicit names such as `RuntimeState`, `RoutePolicy`, `InputNormalizer`, `TerminalCleanup`, or `CommentCodec`.
- Avoid vague catch-all names such as `Utils`, `Helpers`, `Common`, `Shared`, `Manager`, or `Service`.
- Generic catch-all modules are especially discouraged at the top level.
- File paths and module names should mirror each other:
  - `config/schema/tracker.ex` -> `SymphonyElixir.Config.Schema.Tracker`
  - `workflow/route_policy/validator.ex` -> `SymphonyElixir.Workflow.RoutePolicy.Validator`
  - `workspace/cleanup.ex` -> `SymphonyElixir.Workspace.Cleanup`
  - `repo/git/remote.ex` -> `SymphonyElixir.Repo.Git.Remote`
  - `repo_provider/invocation/command_parser.ex` -> `SymphonyElixir.RepoProvider.Invocation.CommandParser`
  - `orchestrator/dispatch/revalidation.ex` -> `SymphonyElixir.Orchestrator.Dispatch.Revalidation`
  - `orchestrator/retry/scheduler.ex` -> `SymphonyElixir.Orchestrator.Retry.Scheduler`
  - `orchestrator/running/reconciliation.ex` -> `SymphonyElixir.Orchestrator.Running.Reconciliation`
  - `observability/event_store/query.ex` -> `SymphonyElixir.Observability.EventStore.Query`
  - `observability/log_file/file_handler.ex` -> `SymphonyElixir.Observability.LogFile.FileHandler`
  - `observability/status_dashboard/presenter.ex` -> `SymphonyElixir.Observability.StatusDashboard.Presenter`
  - `agent/runner/execution.ex` -> `SymphonyElixir.Agent.Runner.Execution`
  - `agent/runtime/executor/local.ex` -> `SymphonyElixir.Agent.Runtime.Executor.Local`
  - `agent/credential/accounts/login.ex` -> `SymphonyElixir.Agent.Credential.Accounts.Login`
  - `tracker/config_access.ex` -> `SymphonyElixir.Tracker.ConfigAccess`
  - `tracker/tapd/comment_codec.ex` -> `SymphonyElixir.Tracker.Tapd.CommentCodec`
  - `repo_provider/config_access.ex` -> `SymphonyElixir.RepoProvider.ConfigAccess`
  - `repo_provider/cnb/api_handler/router.ex` -> `SymphonyElixir.RepoProvider.CNB.ApiHandler.Router`
  - `agent_provider/codex/app_server/launcher.ex` -> `SymphonyElixir.AgentProvider.Codex.AppServer.Launcher`
- New tracker integrations should follow the existing tracker shape:
  - `tracker/<kind>/adapter.ex`
  - `tracker/<kind>/client.ex`
  - `tracker/<kind>/normalizer.ex`
  - plus any clearly named tracker-specific helpers
- New repo-provider integrations should follow the existing repo-provider shape:
  - `repo_provider/<kind>/adapter.ex`
  - provider-specific handlers, clients, and normalizers named by responsibility
- Dynamic Tool sources that consume target-repository facts should use
  `repo/dynamic_tool_context.ex` to resolve relative repo paths from the
  captured workspace context before invoking repo or repo-provider executors.
- Agent-provider session startup should use `agent/dynamic_tool/workflow_plan.ex`
  to restrict provider-visible tools to current workflow-required capabilities.
  Provider adapters should consume that restricted context for native allowlists,
  MCP/tool files, prompt inventory, and bridge execution.
- Agent-provider workspace preparation should only prepare provider bootstrap
  artifacts or consume an explicitly supplied workflow-planned `tool_context`.
  It should not inspect issue state, workflow routes, or Dynamic Tool sources to
  decide tool exposure.

## Quick Placement Guide

- New generic workspace bootstrap, cleanup, path, git-exclude, or remote-execution code:
  `workspace/`
- New SSH host normalization or SSH command-building logic:
  `platform/ssh.ex`
- New poll-cycle coordination, server callback options, polling timers, issue dispatch execution, worker-host, worker-exit, runtime-context, or runtime-state logic:
  `orchestrator/`
- New dispatch context, candidate ordering, eligibility, skip-reason, runtime-slot, revalidation, or route-preparation logic:
  `orchestrator/dispatch/`
- New retry scheduling, attempt metadata, retry-event, retry-lookup, retry-release, retry-defer, or redispatch-handoff logic:
  `orchestrator/retry/`
- New running issue reconciliation, inactive grace, stalled-run detection, termination cleanup, claim cleanup, running-state view, or reconcile-event logic:
  `orchestrator/running/`
- New tracker-vendor HTTP, query, pagination, provider-option, normalization, codec, workspace-preparation, or workflow mapping logic:
  `tracker/<kind>/`
- New tracker-vendor codec parsing, rendering, or payload-shaping internals:
  `tracker/<kind>/<codec_name>/`
- New tracker-vendor dynamic-tool schema, argument, allow-list, parameter
  injection, or error-payload internals:
  `tracker/<kind>/tool_executor/`
- New provider-neutral tracker config/access/registry/error logic:
  `tracker/`
- New repository branch, status, preflight, context, or error logic:
  `repo/`
- New Git command execution, argument construction, repository inspection, remote operation, branch operation, commit operation, parsing, validation, or error classification logic:
  `repo/git/`
- New repo-provider facade, config, registry, command, output, or provider-neutral adapter support:
  `repo_provider/`
- New repo-provider CLI runtime adapter behavior such as environment loading,
  runtime config resolution, evaluator-level observability, or stdout/stderr
  tuple shaping:
  `repo_provider/cli/`
- New repo-provider command execution helper, result rendering, watch-loop, or
  provider-option projection from a parsed invocation:
  `repo_provider/command/`
- New repo-provider CLI command-line option parsing:
  `repo_provider/invocation/`
- New repo-provider-specific API, CLI, handler, or normalization logic:
  `repo_provider/<kind>/`
- New provider-neutral agent run lifecycle logic:
  `agent/`
- New provider-neutral runtime target, command, environment, or dynamic-tool runtime logic:
  `agent/runtime/`
- New executor implementation for one placement:
  `agent/runtime/executor/`
- New worker-daemon endpoint, pool, health/circuit, daemon-client, session-handle, or event-stream logic:
  `agent/runtime/worker_daemon/`
- New bounded event-store config, index, state, query, input normalization, or mailbox pressure logic:
  `observability/event_store/`
- New log sink default path, runtime config, console/file handler, formatter-template, or sink lifecycle-event logic:
  `observability/log_file/`
- New provider-neutral AI agent adapter contract, registry, config resolution,
  capability projection, session lifecycle, runtime-start validation, event,
  event-summary, presentation, message-routing, workspace-preparation, or usage
  logic:
  `agent_provider/`
- New provider-neutral event-summary payload access or compact text formatting
  primitives used by more than one provider:
  `agent_provider/event_summary_mapper/`
- New workspace automation source lookup, override handling, bundled `priv/` extraction, copy/install, or bootstrap logic:
  `workspace/`
- New Codex, Claude Code, OpenCode, or other concrete AI coding-agent protocol code:
  `agent_provider/<kind>/`
- New provider app-server/client internals for command launch, stream parsing,
  HTTP requests, callback message construction, usage extraction, event fields,
  port metadata, or process cleanup:
  `agent_provider/<kind>/app_server/`
- New provider workspace tooling internals for generated config, generated
  source files, remote bootstrap scripts, tool file manifests, or
  provider-visible tool spec shaping:
  `agent_provider/<kind>/tooling/`
- New provider-specific event wording or event-to-summary mapping:
  `agent_provider/<kind>/event_summary_mapper.ex` for small providers, or
  `agent_provider/<kind>/event_summary_mapper/` when the mapper needs helper
  modules.
- New workflow parsing, prompt, or route-selection logic:
  `workflow/`
- New config schema/default/finalization logic:
  `config/`
- New dashboard rendering, throughput, or drill-down logic:
  `observability/status_dashboard/`
- New shared observability event fields:
  extend `observability/fields.ex` first, then let the event, logger, and formatter projections use
  that registry.

## Anti-Patterns

Avoid these structural moves:

- Adding new business logic directly to a root facade because "the file already exists".
- Creating a top-level `helpers.ex`, `utils.ex`, `shared.ex`, or `service.ex`.
- Putting tracker-vendor conditionals in `orchestrator/` or `workspace/`.
- Putting concrete AI agent protocol conditionals in `agent/` or `orchestrator/`.
- Putting dashboard-specific string formatting in generic `observability/` modules.
- Adding parallel observability field lists in `Event`, `Logger`, `Formatter`, or dashboard code.
- Putting SSH target parsing inside workspace modules.
- Creating a `common/` directory when the real domain owner is already known.
- Extracting one-off helpers into a shared module before there is a demonstrated second caller.
- Creating a namespace that contains only one vague module and no clear ownership boundary.

## Refactor Decision Checklist

Use this checklist before introducing a new file or moving code:

- What is the owning domain?
- Is there already a namespace for that domain?
- Is the intended module part of the public API surface or only an implementation detail?
- Would this code still make sense if the caller changed but the domain stayed the same?
- Is the module named after a real responsibility rather than a generic bucket?
- Does the proposed location reduce coupling, or does it only hide file size?
- Will a future contributor know where to add the next related change?

If any of the first three answers are unclear, stop and resolve the ownership
question before writing the new file.

## AI Placement Decision Tree

When an AI agent needs to place new code, use this flow:

1. Classify the change.
   Is it config, workflow, issue model, repository core, repo provider,
   workspace lifecycle, SSH support, orchestration, tracker integration,
   agent-provider integration, observability infrastructure, or dashboard
   presentation?
2. Choose the narrowest owning namespace.
   If the change clearly belongs to one existing namespace, place it there.
3. Decide whether the root module should change.
   Only touch the root facade when the public API, GenServer boundary, or top-level
   entry behavior changes.
4. Check for a more specific sub-area.
   Inside a namespace, prefer `Paths`, `Hooks`, `Retry`, `Presenter`, `Normalizer`,
   or another explicit responsibility over a generic bucket.
5. Reject vague names.
   If the proposed name could fit almost anything, it is probably wrong.
6. Re-check cross-domain leakage.
   If the new module needs tracker-vendor details, it should not live in
   `orchestrator/`. If it needs dashboard rendering details, it should not live in
   generic `observability/`.
7. Update docs when the structural rule changes.

## AI Placement Examples

- "Add workspace path hashing and safe-name derivation":
  extend `workspace/paths.ex`, not `workspace.ex`.
- "Add SSH host entry parsing for a new address form":
  extend `platform/ssh.ex`, not `workspace/remote.ex`.
- "Add a new retry backoff rule for stalled runs":
  extend `orchestrator/retry.ex`, not `tracker.ex`.
- "Add a TAPD-specific comment formatting workaround":
  extend `tracker/tapd/comment_codec.ex` or another `tracker/tapd/` module, not `orchestrator/events.ex`.
- "Add parsing for another Git porcelain output shape":
  extend `repo/git/status_parser.ex` or another focused module under
  `repo/git/`, not `repo/git.ex`.
- "Add another Git commit or staging operation":
  extend `repo/git/commits.ex`, not `repo/git.ex`.
- "Add a new repo-provider helper command option":
  extend the matching parser under `repo_provider/invocation/`, not
  `repo_provider/invocation.ex` or a provider adapter.
- "Change land watcher policy for checks, review comments, agent reviews, PR
  head updates, or merge-conflict blocking":
  extend `repo_provider/land_watch/` or `repo_provider/land_watch.ex`, not the
  workspace automation skill.
- "Change repository-root `.codex/skills` used while developing Maestro":
  keep those skills scoped to the local checkout and developer tools. Do not
  introduce runtime workspace assumptions such as
  `SYMPHONY_WORKSPACE_AUTOMATION_DIR` or bundled helper paths there.
- "Add a new dashboard section summarizing throughput":
  extend `observability/status_dashboard/presenter.ex` or `throughput.ex`, not generic `observability/logger.ex`.
- "Change how recent structured events are retained or queried":
  extend `observability/event_store/`, not `observability/event_store.ex`.
- "Add provider-specific event wording for a new agent event":
  extend that provider's `event_summary_mapper` module or namespace, not the
  provider app-server/client module, unless the transport contract itself changed.
- "Add nested-map access or usage text formatting needed by multiple provider
  event mappers":
  extend `agent_provider/event_summary_mapper/`, but keep provider event names,
  provider categories, and provider payload meanings in each provider's mapper.
- "Change how agent summaries are rendered consistently across providers":
  extend `agent_provider/message_presenter.ex`, not a provider-specific mapper.
- "Add worker-daemon endpoint failover or health-cache behavior":
  extend `agent/runtime/worker_daemon/`, not `agent/runtime/executor/worker_daemon.ex`.
- "Add a new runtime executor placement":
  add a focused module under `agent/runtime/executor/`, and keep shared runtime
  selection logic under `agent/runtime/`.
- "Add workflow prompt rendering behavior":
  extend `workflow/prompt_builder.ex`, not `config/schema.ex`.
- "Add a second caller for reusable config normalization":
  extract or extend a clearly named module under `config/`, not a new top-level shared helper.

## AI Execution Rules

When an AI agent changes this codebase, follow this decision order:

1. Identify the owning domain first.
2. Check whether that domain already has a namespace directory.
3. Prefer extending that namespace over adding a new root file.
4. Preserve existing root facades as public entrypoints unless the change explicitly redesigns the public API.
5. Do not introduce new top-level catch-all modules such as `helpers.ex`, `utils.ex`, `shared.ex`, or `service.ex`.
6. If splitting a large module, keep the old entry module thin and move new behavior into named submodules.
7. Use the directory responsibility map and the decision tree above before creating a new file.
8. If a structural change affects how future contributors should place code, update this document, `README.md`, and `AGENTS.md` in the same change.

If two placements both seem plausible, prefer the more local namespace with the
clearer domain owner. Only create a new top-level module when the concern is
truly cross-cutting and does not belong to an existing namespace.

## Review Checklist

Before merging a structural change, check:

- Is the owning domain obvious from the path?
- Did the change extend an existing namespace where possible?
- Is the root facade still readable and responsibility-focused?
- Did we avoid introducing a vague catch-all helper module?
- Are public APIs, docs, and tests still aligned with the new structure?

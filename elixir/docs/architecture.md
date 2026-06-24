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

- Boundary normalization is a project-wide rule: raw external inputs may accept
  the shapes native to their source, but they must be normalized at the owning
  boundary before business/runtime code consumes them. Internal runtime
  contracts should use one stable shape and must not scatter fallback lookups
  such as atom/string double reads. If both raw and effective data are needed,
  expose separate APIs whose names make the boundary explicit.
- Capability names are external protocol strings owned by the domain that
  provides the capability. Tracker strings belong in
  `SymphonyElixir.Tracker.Capabilities`, repo-core strings in
  `SymphonyElixir.Repo.Capabilities`, repo-provider strings in
  `SymphonyElixir.RepoProvider.Capabilities`, agent strings in
  `SymphonyElixir.Agent.Capabilities`, and workflow-plan strings in
  `SymphonyElixir.Workflow.CapabilityNames`. Platform consumers aggregate
  domain-owned sources through `SymphonyElixir.Capability.Registry`; the
  registry receives built-in sources from assembly-only modules under
  `SymphonyElixir.AssemblyCatalog`. Provider adapters, observability
  projections, and workflow profiles must not add cross-domain capability
  strings to the Workflow namespace.
  This boundary is guarded in three layers:
  boundary rules keep `capability/` mechanism-only and `assembly_catalog/`
  assembly-only; code structure keeps source contracts, catalog assembly, and
  domain capability owners in separate namespaces; architecture tests reject
  concrete capability strings or built-in domain source modules in the platform
  mechanism layer and reject direct source registration from root config.
- Agent execution-plan public boundaries use canonical string-key maps for
  external compatibility, while Store commands, guards, mutations, and
  persistence reads must normalize through
  `SymphonyElixir.Agent.ExecutionPlan.Schema.normalize/1` and operate on
  `SymphonyElixir.Agent.ExecutionPlan.Record` structs internally. Convert back
  to maps only at public snapshot, workflow projection, or storage-write
  boundaries.
- Agent execution-plan Store facades split client routing options from
  command/domain options before constructing internal command structs; `server:`
  selects a process and must not leak into mutation policy opts.
- Agent execution-plan context refs are bounded identity records. Runtime code
  must not pass raw provider payloads, full workflow envelopes, prompt text, or
  Workpad Markdown through `context.workflow_ref`, `context.repo_ref`, or
  `context.tracker_ref`.
- Agent execution-plan source-plan refs, rendering metadata, status reasons,
  matchers, and namespaced extensions normalize into explicit internal Record
  wrappers. `source_plan_ref` is bounded by `artifact_id` and `hash`; blocked,
  skipped, and failed item states require a bounded `status_reason.reason_code`.
- Agent execution-plan typed tools follow the focused-owner rule:
  `ToolExecutor` remains the dispatch/Store orchestration facade,
  `Tool.Contract` owns stable tool names, argument/result keys, capabilities,
  source kind, and risk flags; `Tool.Specs` owns Dynamic Tool specs and JSON
  Schema fragments; `Tool.Arguments` owns raw argument parsing into
  `Tool.Command` structs; `Tool.Payload` owns Record-backed plan/evidence
  payload wrappers and item-set wrappers for Store-owned merge normalization;
  `Tool.Options` owns source/runtime option parsing; `Tool.Guards` owns
  tool-surface policy checks over canonical plan snapshots; and `Tool.Result`
  owns typed envelopes and bounded summaries.
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
- Observability event envelope keys, default component/event labels, service
  name, and the logger metadata key used to carry canonical events are owned by
  `SymphonyElixir.Observability.EventContract`. `Event`, `Logger`, `Formatter`,
  event-store projections, and dashboards should consume that owner instead of
  duplicating `"timestamp"`, `"level"`, `"event"`, `"message"`, `"service"`,
  `"component"`, `result_summary`, `payload_summary`, or
  `:observability_event`.
- Module-specific observability `component` values that are repeated inside one
  emitter module should be centralized as a module-local constant such as
  `@component`. Promote component values into a shared contract only when they
  become a cross-module taxonomy consumed by dashboards, event-store queries, or
  external integrations.
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
- Observability operation labels are owned by
  `SymphonyElixir.Observability.OperationName`; lifecycle status labels are
  owned by `SymphonyElixir.Observability.OperationStatus`.
- Platform durable-storage infrastructure is owned by
  `SymphonyElixir.Storage`. `Storage.Repo`, `Storage.Migrator`,
  `Storage.TableCatalog`, `Storage.TableCatalog.Entry`,
  `Storage.TableCatalog.Source`, `Storage.Backend`, `Storage.ErrorCodes`, and
  storage-governance boundaries such as backup, retention, and redaction define
  shared physical storage mechanics. Domain stores and workflow plugins may
  register table-level catalog entries through trusted catalog sources or
  manifests and use storage adapters, but they must not
  make Repo or migration startup conditional on one domain's durable setting.
  Platform storage must not compile-depend on concrete domain modules or
  interpret domain/plugin payload semantics. Catalog entries stay table-level
  only and reject schema details such as columns, indexes, projections, and
  upsert metadata. Application configuration uses catalog sources only; direct
  entry-module injection is reserved for function-level test or explicit
  assembly opts. Catalog entry external field names are derived from the
  entry field contract; string-keyed entry maps are accepted only at that
  normalization boundary and unknown fields fail closed. `Storage.Config` owns
  backend-value normalization from external values such as `"memory"` and
  `"sqlite"` into stable platform identifiers such as `:memory` and `:sqlite`.
  SQLite DSN syntax such as `:memory:` and `file::memory:` belongs inside
  `Storage.Repo` and must not leak into domain storage logic.
- Application assembly catalogs are owned by `SymphonyElixir.AssemblyCatalog`,
  not by the individual mechanism layers. `AssemblyCatalog.StorageContracts`
  may reference concrete built-in domain or plugin storage contracts,
  `AssemblyCatalog.WorkflowExtensions` may reference bundled workflow runtime
  extensions, `AssemblyCatalog.CapabilitySources` may reference built-in
  domain capability sources, and `AssemblyCatalog.DynamicToolSources` may
  reference bundled Dynamic Tool source modules. These modules stay source-only
  so `Storage`, `Workflow.Extension`, `Capability`, and `Agent.DynamicTool`
  remain stable mechanism layers while application composition declares which
  built-ins are enabled.
- External workflow plugins are not bundled application code. They must be
  independently released OTP applications or equivalent release dependencies,
  and they must enter the platform through their own trusted source module or a
  future validated manifest projection. `SymphonyElixir.Workflow.Extensions.*`
  and `priv/workflow_extensions/` are reserved for explicitly bundled
  extensions such as Coding PR Delivery; adding a new external plugin under
  those namespaces is not an allowed integration path.
  Bundled extensions should still model their metadata as a manifest projection:
  the extension facade reads id/version from the bundled manifest module, while
  future external plugins provide equivalent metadata through their package
  manifest or registry source. Host integration code for bundled extensions must
  live under an explicit `HostAdapters` namespace. Modules there may call host
  facades such as Workflow, Tracker, RepoProvider, Observability, or platform
  stores; core plugin rule modules should consume injected deps, ports, or
  plugin-owned contracts instead of owning those host calls directly. Examples
  include CompletionValidator profile lookup through
  `HostAdapters.CompletionValidator.ProfileDefaults`, ProviderFacts provider
  calls and provider-error protocol through
  `HostAdapters.Reconciliation.ProviderFactsDefaults`, and reconciliation event
  emission through `HostAdapters.Reconciliation.EventEmitterDefaults`.
- Workflow runtime extensions are the current pre-plugin boundary. Platform
  orchestration should invoke `SymphonyElixir.Workflow.Extension.Runtime` and
  `Workflow.Extension` contracts instead of concrete workflow business
  contexts. Extension callbacks receive `Workflow.Extension.Runtime.Context`
  and return `Workflow.Extension.Runtime.Result`, so the dispatcher owns the
  runtime call shape and error normalization. Runtime result external field
  names are derived from the output field contract; string-keyed callback result
  maps normalize at the runtime boundary and unsupported fields fail closed.
  Generic type labels used in runtime, registry, operator-command, and
  tool-result-recorder error maps are centralized in
  `Workflow.Extension.Diagnostics`; compact type labels serve registry-style
  diagnostics, while detailed type labels serve runtime scope and JSON-boundary
  diagnostics. Registry source diagnostics, command vocabulary, schema ids,
  provider/tracker/repo facts, and extension-owned payload codecs remain in
  their owning modules. `Diagnostics` stays a pure helper with no
  aliases/imports/use and a small approved public API; architecture tests reject
  concrete extension names, provider/tracker/repo or storage dependencies,
  source/tool/schema vocabulary, exception messages, and raw value inspection.
  Extension platform registries, dispatchers, contribution aggregation, and
  storage adapters must use bounded exception/type diagnostics; public errors
  must not expose exception messages, thrown payloads, provider payloads,
  command arguments, or extension business payloads.
  Runtime context exposes `Workflow.Extension.Runtime.Projection`, not the
  Orchestrator state struct/map itself. Extensions may read stable facts such
  as running issue ids, claimed issue ids, slot counts, and their own
  extension-state projection, but they must not depend on Orchestrator-internal
  fields. Runtime results contain extension-owned state plus typed
  `Workflow.Extension.Runtime.Command` values; the dispatcher writes the
  extension state back into the platform runtime envelope and delegates command
  execution to platform-owned command handlers. Runtime command handlers must
  return stable bounded error maps using workflow extension error codes and
  command diagnostics such as command type and payload shape; they must not
  include full command payloads in errors or logs. Handlers stay owned by the
  platform domain that performs the side effect: Orchestrator resource changes
  belong to Orchestrator handlers, while future Storage, Tracker, or Repo side
  effects must use their own facade/handler instead of being added to the
  Orchestrator handler.
  `Workflow.Extension.Runtime.Context` is a thin input value object with
  `new/3` and `new!/3`; it must not own workflow-scope codec details.
  `Workflow.Extension.Runtime.Scope` owns default workflow-scope derivation,
  scope field names, canonical workflow-config hashing, and strict
  JSON-compatible validation for explicit scopes. Invalid metadata,
  non-keyword context opts, non-map explicit scopes, unsupported scope keys, and
  non-JSON scope values fail closed with
  `invalid_workflow_extension_runtime_context` before any extension runs.
  Runtime scope must project config schema structs into stable maps before
  calling durable identity encoders; runtime-only terms such as pids,
  references, functions, tuples, and arbitrary structs must not enter the
  workflow-config hash.
  `Workflow.Extension.Canonical` owns versioned durable identity codecs and
  includes the codec id in the hash input. Runtime workflow-config hashes and
  state-store scope keys use separate codec ids and must not be treated as
  interchangeable. Canonical public APIs return `{:ok, hash}` or bounded
  errors; callers such as `Runtime.Scope` and `StateStore.Record` translate
  those errors into their own boundary error codes instead of hashing invalid
  values or leaking raw payloads.
  `Workflow.Extension.Runtime` is the small public facade for `run_poll_cycle/3`.
  Keep runtime implementation details in focused internals:
  `Runtime.Dispatcher` for sequential extension execution, `Runtime.Options`
  for `runtime_extension_opts` validation and shared option keys such as
  `:common` / `"common"`, `Runtime.ResultApplier` for writing extension state
  back into the runtime envelope, `Runtime.CommandExecutor` for invoking
  platform command handlers, and `Runtime.Error` for bounded runtime error
  envelopes. Do not grow `runtime.ex` with registry collection, option parsing,
  command execution, provider integration, physical storage, or plugin
  lifecycle logic.
  Built-in modules under
  `Workflow.Extensions` own concrete business services such as Coding PR
  Delivery reconciliation, but they must not depend on physical storage APIs or
  Orchestrator resource registries directly.
  Extension-owned durable state goes through `Workflow.Extension.StateStore`
  and `Workflow.Extension.StateStore.Record`; the platform stores
  JSON-compatible opaque envelopes such as `workflow_extension_state_records`
  and does not interpret extension payload semantics. State-record external
  field names are derived from the input-key contract; adapter aliases such as
  `payload_json` normalize into the internal `payload` field instead of becoming
  business fields. State-record validation errors use bounded type diagnostics
  and must not return raw payload or scope values. The `StateStore` facade
  stays limited to behaviour callbacks and public `put/get/list/delete`
  dispatch. `StateStore.Options` rejects non-keyword call options,
  `StateStore.Config` validates `:workflow_extension_state_store` app config,
  `StateStore.BackendSelector` selects and validates the backend, and
  `StateStore.Error` owns bounded state-store error envelopes. `backend:` and
  backend-local options remain test/admin/assembly overrides, not extension
  business API. The `StateStore` facade does not expose destructive reset
  operations to extensions. Orchestrator-facing options must stay generic, such as
  `runtime_extension_opts`; concrete extension options must be scoped before
  reaching the extension. Invalid extension option shapes, unknown scoped
  option keys, and non-keyword scoped option values fail closed at the runtime
  boundary before any extension is executed.
  `Workflow.Extension.Registry` must load trusted source modules from root
  config, ask those sources for extension modules, and normalize them into
  stable entries containing normalized id, module, and source before execution.
  Root config must register application-assembly source modules such as
  `AssemblyCatalog.WorkflowExtensions`, not modules under the
  concrete workflow extension business namespace; `:workflow_runtime_extensions,
  entries: [...]` is not a supported production configuration shape.
  Production `:workflow_runtime_extensions` config is source-only and accepts
  only `sources: [...]`; direct `entries`, `extra_entries`, `extra_sources`,
  `source_opts`, non-keyword config, unknown keys, and non-list source lists fail
  closed. Function-level opts may inject `entries` or `extra_entries` for tests
  and explicit in-process assembly, but all extension and source module
  collections must be lists. Duplicate extension modules and duplicate extension
  ids fail closed with source diagnostics instead of being silently
  de-duplicated.
  `Workflow.Extension.Registry` is the facade for `entries/1`, `validate/1`, and
  `validate!/1` only. `Registry.Config` owns production application config
  shape validation, `Registry.Collector` owns opts/config/source collection,
  `Registry.Validator` owns source and duplicate validation, `Registry.Entry`
  owns normalized entry construction, and `Registry.Error` owns bounded registry
  error envelopes. The facade must not own CLI parsing, provider integration,
  physical storage access, audit, permission, manifest-file loading, or plugin
  enable/disable lifecycle. If future manifest projection becomes real, add a
  focused `Registry.Projection` instead of growing `registry.ex`.
  Extension `operator_commands/0` callbacks must stay static module-list
  declarations; the platform operator-command registry rejects non-list
  declarations, duplicate command modules, duplicate command ids, missing
  command behaviours, unloaded modules, and raised callbacks instead of
  silently dropping or discovering commands. Operator-command dispatch accepts
  only keyword options; `registry_opts` and `command_opts` must also be keyword
  lists, and invalid option shapes fail closed before command lookup or
  execution. Dispatcher stderr reports reason codes and value types, not raw
  option payloads or command payloads.
  `assembly_catalog/` is assembly-only: modules there may implement mechanism
  source callbacks and list trusted storage contracts, extension modules,
  capability sources, Dynamic Tool sources, or future manifest projections, but
  must not contain
  business services, readiness rules, operator-command handling,
  tool-result handling, storage adapters, provider logic, or Orchestrator
  dependencies.
  Workflow template assets use the same ownership rule. Platform-owned
  templates may live under `priv/workflow_templates/`, while concrete built-in
  extension templates and prompt partials live under an extension-owned asset
  root such as `priv/workflow_extensions/<extension>/templates/`.
  `priv/workflow_extensions/` is an OTP/release asset location for built-in
  extensions, not a platform business context. It must contain static assets
  only; extension execution logic, registry sources, readiness rules,
  operator-command handling, provider adapters, and storage adapters remain in
  their owning Elixir contexts. If an extension becomes an external plugin app,
  its assets should move to that app's own `priv/` directory and be declared
  through the plugin manifest or registry source.
  `Workflow.Template` is the stable facade for template consumers and template
  contributors. `Workflow.Template.Entry` is the public contribution record for
  extension-owned template refs; concrete extensions should construct entries
  through `Workflow.Template.entry!/1`, not by constructing registry internals.
  Extension-owned template catalogs should keep their own contract matrix,
  asset-root resolver, and credential-default policy in focused modules. Built-in
  extensions may resolve assets from `:symphony_elixir` `priv/`; external plugin
  apps should pass their own `otp_app`, explicit `asset_root`, or manifest
  projection while still returning the same public `Workflow.Template.Entry`
  shape.
  Internally, `Workflow.Template.Registry` stores explicit template entries with
  asset root and asset path; `Workflow.Template.Resolver` resolves templates and
  `_partials/` relative to those registered roots; `Workflow.Template.Assets`
  resolves built-in asset roots from the owning OTP application `priv/`
  directory instead of source-relative paths or one global scan; and
  `Workflow.Template.PathRules` centralizes stable path vocabulary such as the
  Markdown suffix, reserved relative segments, documentation basenames, the
  platform template asset directory, and the partials directory.
  Dynamic Tool result consumption uses the same pre-plugin shape:
  provider-neutral Dynamic Tool sources publish results through
  `Agent.DynamicTool.ResultRecorder`; the workflow assembly adapter
  `Workflow.DynamicToolResultRecorder` forwards those results to readiness
  evidence recorders and to `Workflow.Extension.ToolResultRecorder.Dispatcher`.
  Dynamic Tool result-envelope type labels such as success, failure, and error
  are owned by `Agent.DynamicTool.ResultRecorder.result_type/1`; workflow
  extension dispatchers consume that diagnostic instead of duplicating result
  vocabulary.
  Concrete result interpretation, such as Coding PR Delivery known-target
  registration from tracker attach-tool results, must live in extension-owned
  tool-result recorder modules registered by the owning extension. Tracker,
  repo, and repo-provider sources must not alias concrete
  `Workflow.Extensions.*` business modules to consume tool results.
  Tool-result-recorder registry inputs and extension declarations must use
  explicit lists; duplicate recorder module contributions and duplicate recorder
  ids fail closed. The dispatcher accepts only keyword options, passes only
  explicit `tool_result_recorder_opts` to recorder callbacks, and reports
  callback failures with bounded exception/type diagnostics instead of exception
  messages or raw Dynamic Tool payloads. Workflow assembly may keep Dynamic Tool
  execution non-blocking, but recorder failures must emit bounded observability
  events rather than disappearing silently.
  Extension-owned recorder adapters must stay thin: they may route only source
  kinds they own, must fail closed on non-keyword callback options for owned
  source kinds, and should delegate payload interpretation to extension-owned
  producer/use-case modules rather than embedding provider or tracker rules in
  the recorder facade.
  Operator-facing extension commands use
  `Workflow.Extension.OperatorCommand` and
  `Workflow.Extension.OperatorCommand.Registry`; platform CLI/Mix entrypoints
  dispatch through `Workflow.Extension.OperatorCommand.Dispatcher` by command id
  instead of aliasing concrete extension business modules. Built-in operator
  command implementations belong under their owning `Workflow.Extensions.*`
  namespace. Generic platform entrypoints such as `mix workflow.command` may
  expose the dispatcher, but platform code must not add per-extension business
  Mix tasks as the plugin command model. `Mix.Tasks.Workflow.Command` is a thin
  host only: it may parse the command id and `--` argument separator, start
  required runtime dependencies, call the operator-command dispatcher, and relay
  stdout/stderr/exit code. It must not parse extension-specific arguments,
  mention concrete workflow business vocabulary, or depend on tracker,
  repo-provider, orchestrator, physical storage, or concrete extension modules.
  `Workflow.ProfileRegistry` and `Workflow.Template` follow the same rule: they
  own platform profile/template lookup mechanics, may enumerate only
  platform-owned profiles or quickstart templates directly, and must receive
  concrete extension profile/template entries through
  `Workflow.Extension.Contributions` or a future manifest projection.
  Built-in extension root modules such as
  `Workflow.Extensions.CodingPrDelivery` must stay thin manifest/facade modules:
  they expose the platform `Workflow.Extension` callbacks and delegate template
  catalogs, runtime adapters, supervision children, configuration validation,
  readiness rules, and business services to extension-owned submodules. Root
  extension facades must not grow private helpers, template construction,
  poll-cycle algorithms, producer/registry child specs, physical storage access,
  or storage-oriented credential APIs.
  A future plugin system should replace the registry source, not the
  orchestrator or operator-command dispatch shape.
  The remaining compatibility surface is intentionally narrow: operator
  one-shot helpers may build a minimal platform runtime input for the extension
  dispatcher, but the one-shot facade must stay thin. Extension-owned
  one-shot execution belongs behind focused modules for sequencing, default
  dependencies, workflow/template resolution, stable probe ids/modes, reports,
  and bounded probes. One-shot option bags must be keyword lists and invalid
  inputs must return bounded reports rather than raising or inspecting raw
  values. Probe diagnostics must not expose exception messages, provider
  payloads, or arbitrary inspected terms. Extension callbacks must not receive
  or return raw platform runtime state. Compatibility must not reintroduce old
  extension callback arities, direct Orchestrator-to-business-context calls,
  concrete Orchestrator option names, or extension access to state-store backend
  modules.
  Built-in Coding PR Delivery known-target records are stored as extension
  state with `state_type`/`payload_schema` equal to
  `change_proposal.known_target.v1`; they must not become a platform table or
  workflow-local JSON file source. Durable known-target storage requires an
  explicit workflow scope supplied by the runtime/application assembly; the
  extension StateStore backend must not infer scope from global workflow file
  configuration. Known-target storage options must be keyword lists, invalid
  `put_many/2` targets fail closed instead of being skipped, storage callers
  cannot override the extension namespace, and the StateStore `extension_version`
  is read from Coding PR Delivery extension metadata rather than hardcoded in
  the backend. Workflow-scope JSON validation is delegated to the
  extension-owned `KnownTarget.Storage.Scope` helper so the StateStore adapter
  stays a narrow mapping layer. The known-target model, fields,
  observation signature, registry, payload codec, and storage port live under
  `Workflow.Extensions.CodingPrDelivery.KnownTarget.*` so the
  extension-owned reconciliation service consumes the extension-owned model
  instead of platform workflow owning it. `KnownTarget.Registry` is intentionally
  only a runtime index and light business entrypoint; it may call the
  `KnownTarget.Storage` port but must not own StateStore/Repo/Ecto/SQLite access,
  reconciliation/readiness/producer rules, Orchestrator side effects, revision
  control, or state-machine semantics. If KnownTarget gains command objects,
  optimistic revision checks, multi-record transactions, or an independent state
  machine, introduce an extension-owned `KnownTarget.Store` instead of growing
  the registry. `KnownTarget.Registry` stays the runtime facade and GenServer
  entry; `KnownTarget.Registry.Admin` owns destructive admin/test operations,
  `KnownTarget.Registry.Options` owns options/storage-backend selection,
  `KnownTarget.Registry.Retention` owns TTL and max-target retention, and
  `KnownTarget.Registry.StorageSync` owns calls through the extension-owned
  storage port. `KnownTarget.Storage` is the extension-owned ordinary storage
  port and facade: backend selection/callback validation lives in
  `KnownTarget.Storage.BackendSelector`, input validation lives in
  `KnownTarget.Storage.Validator`, and destructive reset lives in
  `KnownTarget.Storage.Admin` plus the separate `KnownTarget.Storage.AdminBackend`
  contract. `KnownTarget.Observation` is a map codec; reconciliation facts are
  projected by the reconciliation-owned `ObservationProjection` adapter, and
  known-target reference extraction accepts issue-like maps/structs without
  compile-time dependency on platform `Issue` structs. Known-target registration
  as a runtime use case belongs to
  `Reconciliation.KnownTarget.Registration`: it composes the KnownTarget registry,
  Candidate.Inbox enqueue, candidate-drop observability, and typed runtime
  blocked-resource release commands. The `Reconciliation` facade must delegate
  this use case instead of owning registry/inbox/event/command orchestration,
  and the KnownTarget subdomain must not grow reconciliation producer logic.
  Coding PR Delivery reconciliation, including config validation, decision/facts structs, provider-fact
  normalization, runtime producers, one-shot execution, and dispatch readiness
  evidence, lives under `Workflow.Extensions.CodingPrDelivery.*`; platform
  Config and Orchestrator reach it only through extension registry/configured
  provider hooks. Provider-fact normalization belongs to the extension-owned
  `Reconciliation.ProviderFacts` service. The service calls injected provider
  callbacks and uses `HostAdapters.Reconciliation.ProviderFactsDefaults` for the
  bundled RepoProvider adapter and provider-error protocol; `RepoProvider` must
  not depend on Coding PR Delivery fact structs or other concrete workflow
  extension business models.
  `Reconciliation.ProviderFacts.Contract` owns repo-provider payload keys,
  provider-state, review-state, mergeability, and timestamp token vocabulary
  consumed by `ProviderFacts`; the service must not re-declare those machine
  strings inline.
  `Reconciliation.ProviderFacts` must remain a thin facade over focused
  internals: `ProviderFacts.Options` validates keyword option bags and injected
  provider callbacks, `ProviderFacts.Client` owns bounded provider callback
  invocation and result-shape diagnostics, `ProviderFacts.Payload` owns payload
  and target field extraction, `ProviderFacts.Summary` is the summary facade,
  `ProviderFacts.Summary.Checks` owns check-run summarization,
  `ProviderFacts.Summary.Reviews` owns review summarization,
  `ProviderFacts.Summary.Feedback` owns actionable-feedback summarization,
  `ProviderFacts.Summary.Settings` owns feedback setting extraction, and
  `ProviderFacts.Builder` owns `Facts` construction. Summary logic must not
  depend on RepoProvider LandWatch internals; it may depend only on public
  provider-neutral contracts such as normalized check-run helpers or
  extension-owned summary rules.
  Provider callback failures and invalid provider payloads must produce bounded
  fact errors without raw payloads or exception messages.
  `Reconciliation.Reconciler` must remain a thin poll-cycle application-service
  facade. Reconciler option validation and dependency arity checks belong in
  `Reconciler.Options`; default calls into platform facades belong in
  `HostAdapters.Reconciliation.ReconcilerDefaults`; callback invocation, callback exceptions, and
  result-shape validation belong in `Reconciler.Clients`; candidate discovery,
  targeted issue normalization, running/claimed filtering, and targeted defer
  behavior belong in `Reconciler.Candidates`; issue metadata and known-target
  fallback lookup belong in `Reconciler.TargetReference`; per-issue route,
  provider-fact, decision, counter, and transition sequencing belongs in
  `Reconciler.IssueRunner`; targeted-candidate suspension events belong in
  `Reconciler.EventEmitter`; and public error string construction belongs in
  `Reconciler.Diagnostics`. The Reconciler facade must not directly alias
  Tracker, Observability, RepoProvider, KnownTarget, ProviderFacts, Decision,
  Transition, or other lower-level business adapters. Injected dependency
  failures must produce bounded diagnostics and public events must not expose
  raw inspected provider, tracker, callback, or exception payloads.
  `Reconciliation.Contract` is the stable facade for reconciliation runtime
  protocol identifiers. It delegates event ids/names to `Contract.Events`,
  component and producer names to `Contract.Producers`, status strings to
  `Contract.Statuses`, tracker capability bindings to `Contract.Capabilities`,
  and bounded reason stringification to `Contract.Reasons`. The facade must not
  grow private helpers or own protocol constants directly.
  `Reconciliation.Events.Fields` owns the structured observability event field
  key vocabulary for this extension. `Reconciliation.Events` remains the event
  field-construction facade and must consume `Events.Fields` rather than
  re-declaring atom or string field keys inline. Host observability writes
  belong behind `Reconciliation.Events.Emitter` and the built-in
  `HostAdapters.Reconciliation.EventEmitterDefaults` adapter, not inside the event facade.
  `Reconciliation.Events.Emitter` must reject invalid option bags with bounded
  diagnostics instead of silently falling back to the default host backend, and
  injected emitter backends must implement the `emit/3` contract. Base event
  field projection belongs in `Reconciliation.Events.BaseFields`, change-proposal
  facts/reference projection belongs in
  `Reconciliation.Events.ChangeProposalFields`, route field projection belongs
  in `Reconciliation.Events.RouteFields`, and public event error formatting
  belongs in `Reconciliation.Events.Diagnostics`; `Events` must not grow route,
  runtime, profile, provider, change-proposal reference, or raw diagnostic
  helpers.
  `Reconciliation.Config.Contract` owns the extension reconciliation config
  schema vocabulary: config path segments, section keys, field keys, field
  paths, discovery mode strings, defaults, limits, and outcome-route
  requirements. `Reconciliation.Config` is the facade/value object only:
  `Config.Source` extracts settings input, `Config.Parser` assembles
  `%Config{}`, `Config.Validator` owns field and enabled-config validation,
  `Config.Routes` owns route parsing and route-policy semantics, and
  `Config.Error` owns error formatting. These modules consume `Config.Contract`
  and `Config.Diagnostics`; public config errors must expose bounded codes,
  field paths, and value types rather than raw inspected reason terms. Parser
  and validator branches must not re-declare schema strings.
  `Reconciliation.RouteContext` may resolve tracker lifecycle route maps, but
  tracker lifecycle field names such as raw-state maps, policy maps, and
  workflow-type maps belong to `Tracker.Config` accessors; RouteContext must not
  hard-code those raw configuration keys.
  `Reconciliation.Transition` must remain a focused transition sequencing
  service. Transition option validation and canonical dry-run handling belong in
  `Transition.Options`; default Tracker facade calls belong in
  `HostAdapters.Reconciliation.TransitionDefaults`; injected tracker fetch/update callback invocation,
  callback exception handling, and result-shape validation belong in
  `Transition.Clients`; and public transition failure diagnostics belong in
  `Transition.Diagnostics`. Transition event field keys must be consumed through
  `Reconciliation.Events.Fields`, and public transition events must not expose
  inspected tracker callback results, route-ref structs, exception messages, or
  arbitrary provider/tracker payloads.
  Coding PR Delivery input boundaries use three explicit shapes only:
  extension-owned typed structs for internal domain values, keyword option bags
  for Elixir API configuration, and canonical string-key maps for external
  payloads. Adapter modules must not add dynamic atom/string key compatibility
  such as `String.to_existing_atom/1`, `map_get_existing_atom`, or generic
  `Map.get(atom) || Map.get(string)` fallbacks. When a platform DTO such as
  `Issue` or settings is consumed, the adapter must use explicit typed selectors
  rather than treating atom-key maps as an alternate external payload shape.
  Coding PR Delivery runtime producers stay extension-owned. Producer entry
  points must accept only keyword option bags; invalid option/config shapes must
  fail closed as bounded no-op or error results. Producer observability must use
  bounded diagnostics from the producer boundary and must not write inspected
  provider payloads, registry errors, runtime command results, exception
  messages, or stack traces into public event fields. Invalid tracker
  tool-result option bags still emit bounded ignored-result diagnostics instead
  of silently returning `:ok`. App config keys for producer children are owned
  by `Reconciliation.Producer.Config` and use `coding_pr_delivery_*` names, while
  default platform facade calls for Config, Tracker, RepoProvider,
  Observability, ProviderFacts, and Candidate.Inbox are owned by
  `HostAdapters.Reconciliation.ProducerDefaults`. Producer-private reason formatting is owned by
  `Reconciliation.Producer.Diagnostics`. Tracker tool-result raw payload keys
  belong behind `TrackerToolResultHandler.Payload`, not in the handler facade;
  producer raw payload adapters consume canonical string-key payloads and must
  not add atom/string compatibility. Runtime dependency injection is validated
  at the producer options boundary by expected function arity; invalid deps fail
  closed before external platform calls. `Candidate.Inbox` is the in-process
  runtime candidate queue facade: public calls accept keyword opts only, invalid
  issue ids are reported as bounded `invalid_count`, missing inbox processes
  return bounded errors instead of default empty snapshots/drains, and
  numeric options such as queue limits, drain limits, and defer thresholds fail
  closed when present but invalid instead of falling back to defaults.
  `Candidate.Lifecycle` owns the pure defer/suspend policy and must not silently
  replace invalid numeric policy options with defaults. Tracker fetch/write
  option forwarding is centralized in `Reconciliation.TrackerCallOptions`;
  non-keyword option bags are rejected at that boundary instead of being treated
  as empty options. Destructive reset belongs to `Candidate.Inbox.Admin`. `TrackerToolResultHandler`, `Watcher`,
  and `StartupBacklogBootstrap` are thin producer facades: capability routing,
  attach/move target projection, target registration, startup scanning, target
  inspection, event construction, runtime command emission, and option/state
  normalization must stay in focused producer submodules.
  Platform workflow config schema validates only generic extension containers
  such as `workflow.reconciliation`; concrete keys such as `change_proposal`
  are validated by the owning extension through the extension registry.
- Workflow readiness and completion-validation payload labels are owned by
  `SymphonyElixir.Workflow.ReadinessContract`. Orchestrator dispatch code
  should read readiness facts through that contract instead of duplicating
  `"status"`, `"gate"`, or evidence-field strings.
- State-transition readiness policy interfaces are owned by
  `SymphonyElixir.Workflow.StateTransitionReadiness.Policy`; policy dispatch
  and recorder aggregation are owned by
  `SymphonyElixir.Workflow.StateTransitionReadiness.PolicyRegistry`, which
  derives concrete policies and evidence recorders from registered workflow
  extension contributions. Shared state-transition readiness envelope, generic
  evidence scalar keys, result, and enum-like status/source strings are owned by
  the focused
  `SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Envelope`,
  `.Evidence`, `.Result`, and `.Values` modules. Policy-specific check keys,
  reason codes, observed-evidence codes, evidence bucket names, profile-specific
  evidence fields, and tool-name mappings should stay under the owning policy
  namespace such as `SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness`.
  Extension-owned typed-failure resource identity vocabulary should likewise
  stay under the owning readiness contract, for example
  `CodingPrDelivery.Readiness.ResourceIdentityContract`, instead of being
  embedded in retry-policy modules.
  Structured-plan evidence payload keys are owned by
  `SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceContract`, not by
  transition-readiness platform contracts.
- Structured-plan evidence binding is a platform mechanism plus
  extension-owned business providers. `Workflow.StructuredExecutionPlan`
  owns generic repo/tracker binding mechanics such as repository commit/push/diff
  and tracker workpad/state evidence. Workflow extensions contribute
  business-specific binding providers through
  `Workflow.StructuredExecutionPlan.EvidenceBinding.Provider`; payload
  normalization, evidence identity fields, validity policy, and freshness classes
  for PR/change-proposal delivery stay under
  `Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.*`. Within
  Coding PR Delivery, `StructuredExecutionPlan.EvidenceBinding` remains the
  provider facade; evidence kinds live in `EvidenceBinding.Contract.EvidenceKind`,
  normalized payload keys live in `Contract.Payload`, raw typed-tool payload keys
  live in `Contract.RawPayload`, local status values live in `Contract.Status`,
  URL markers live in `Contract.Url`, capability/tool mapping lives in
  `Contract.Tool`, payload extraction lives in `Payload`, identity fields live in
  `Identity`, and URL policy lives in `UrlPolicy`. Structured-plan evidence binding
  option boundaries are keyword-only; non-keyword option lists fail closed before
  capability lookup.
  Extension-owned payload normalizers must return `:unknown` for missing
  critical raw payload sections, and the platform provider aggregator must not
  convert that into an empty evidence ref.
- Extension-owned contributions are assembled through
  `SymphonyElixir.Workflow.Extension.Contributions`. Platform contexts such as
  `Application`, `ProfileRegistry`, `Workflow.Template`,
  `CompletionValidator`, and `Orchestrator.Dispatch.RoutePreparation` may ask
  for registered extension profiles, template entries, completion validators,
  readiness evidence providers, and runtime children, but they MUST NOT alias
  concrete extension modules. Concrete modules such as
  `Workflow.Extensions.CodingPrDelivery.Profile` and
  `Workflow.Extensions.CodingPrDelivery.CompletionValidator` stay under the
  owning extension namespace. Contribution callbacks fail closed: invalid
  options, registry errors, callback exceptions, and non-list callback returns
  produce bounded error maps instead of silently returning an empty list. Bang
  helpers are allowed only for existing platform facades that intentionally fail
  startup/configuration when contribution assembly is invalid.
- Extension-owned completion validators should stay orchestration facades. For
  Coding PR Delivery, `CompletionValidator` is only the registered behaviour
  implementation. Option validation belongs in `CompletionValidator.Options`,
  raw input and atom/string key normalization in `CompletionValidator.EvidenceReader`,
  check predicates in `CompletionValidator.Checks`, check envelope assembly in
  `CompletionValidator.CheckSet`, observed labels in
  `CompletionValidator.ObservedEvidence`, and result envelopes in
  `CompletionValidator.ResultBuilder`. Machine check ids and required-evidence
  strings belong in `CompletionValidator.Contract`, raw evidence keys and
  observed-evidence labels in `CompletionValidator.EvidenceContract`, and status
  aliases or provider capability bindings in `CompletionValidator.Values`. The
  facade must not re-own raw evidence vocabulary, observed-label strings,
  repo-provider capability constants, private helper logic, profile/route parsing,
  lifecycle predicates, or atom/string compatibility helpers. Profile lookup and
  completion-contract host access belong in
  `HostAdapters.CompletionValidator.ProfileDefaults`; evidence readers should
  consume that adapter rather than directly aliasing `Workflow.ProfileRegistry`.
- Generic execution-plan schema, statuses, criticalities, owners, sources,
  trust classes, storage behaviour, memory test backend, local SQLite durable
  backend, typed-tool contracts, and immutable evidence-ref behavior are owned by
  `SymphonyElixir.Agent.ExecutionPlan`. Workflow structured-plan modules are an
  adoption layer: they may add workflow envelope fields, gates, Workpad
  rendering, route/profile readiness integration, active workflow indexes, and
  profile-specific enum extensions, but they must delegate generic plan storage
  semantics through an explicit projection instead of becoming a second
  execution-plan core. Workflow structured-plan contract values are split by
  responsibility: `Contract.Values` owns schema ids and workflow enum
  extensions, `Contract.Gates` owns rollout gate keys/defaults, and
  `Contract.Projection` owns workflow-to-Agent projection identifiers; callers
  should use the `Contract` facade or the focused owner instead of repeating
  literals. Workflow evidence binding follows the same focused-owner rule:
  provider-neutral repo tool/evidence mapping, Dynamic Tool capability-to-
  evidence-kind mapping, domain payload normalization, check-status
  normalization, raw tool-result boundary reads, and binding error codes should
  live in focused evidence-binding modules rather than the binding facade.
  Tracker provider-facing tool names such as `<tracker>_move_issue` must not be
  hard-coded in workflow structured-plan core; tracker evidence is bound through
  Dynamic Tool `workflowCapability` metadata.
  Workflow evidence recording should likewise keep raw option parsing in
  recorder options, target plan lookup in a plan resolver, and best-effort write
  failure diagnostics in the recorder facade. Workflow provider adapters should
  keep raw gate/store option parsing in `ProviderAdapter.Options`, machine codes
  in `ProviderAdapter.ErrorCodes`, skip/recorded/typed-failure result envelopes
  in `ProviderAdapter.Result`, and task-completed missing-evidence summaries in
  `ProviderAdapter.Guard`; `ProviderAdapter` itself should remain an
  orchestration facade. Provider-session events should keep canonical fields in
  `ProviderSessionEvent.Contract`, enum and warning values in
  `ProviderSessionEvent.Values`, raw provider aliases and atom/string reads in
  `ProviderSessionEvent.RawInput`, canonical event construction in
  `ProviderSessionEvent.Normalizer`, canonical-only validation in
  `ProviderSessionEvent.Validator`, machine codes in
  `ProviderSessionEvent.ErrorCodes`, redaction/truncation in
  `ProviderSessionEvent.Sanitizer`, and fallback/generated id contracts in
  `ProviderSessionEvent.Identifiers`; `ProviderSessionEvent` itself should remain
  a non-authoritative facade.
  Workflow structured-plan provider-facing tool aliases are also boundary-only:
  `DynamicToolSource.Options` selects the current provider/tracker context
  sources, `DynamicToolSource.ProviderContext` owns raw provider context key
  parsing and canonical `%{provider_key: ...}` normalization, `Tool.Aliases`
  consumes only normalized provider contexts to generate presentation names and
  `toolAliasOf` metadata, and `DynamicToolSource` normalizes alias calls to
  canonical `workflow_plan_*` tools before execution.
  `Inventory.resolve_required/2` remains canonical-only; alias-only tools do
  not satisfy workflow-required capabilities.
  Profile-specific structured execution-plan adoption belongs under the owning
  `Workflow.Profiles.<Profile>` namespace, not under
  `Workflow.StructuredExecutionPlan`. The structured-plan core owns mechanism;
  concrete profiles own their business item templates, evidence requirements,
  and completion contracts.
  Workflow structured-plan code must also remain prompt-independent: prompt
  builders and workflow template text may guide an agent's order of operations,
  but they must not define or mutate structured-plan schema, status-machine,
  evidence contracts, Workpad identity, or readiness decisions. Rendered Workpad
  Markdown remains a one-way projection from canonical plan facts; tracker
  Workpad/comment bodies must not be parsed back into authoritative plan state.
  Extension-owned structured-plan readiness consumers should also keep canonical
  store access behind an extension-owned reader port. For example,
  `Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff`
  is a policy facade; it reads plans through
  `StructuredPlanReviewHandoff.Plan.Reader`, while the bundled
  `HostAdapters.Readiness.StructuredPlanReaderStoreBackend` adapts
  `Workflow.StructuredExecutionPlan.Store`.
  The `StructuredPlanReviewHandoff.Plan.*` namespace is the only place for this
  policy's structured-plan selectors, scope checks, and reader port/adapters;
  flat helper modules such as `PlanReader`, `PlanScope`, or `PlanEvidence` must
  not be reintroduced.
  Store process/server injection is a reader-backend option, not part of the
  policy context projection; top-level store fallback keys are not supported.
  Extension-owned readiness evidence consumers should also use a plugin-owned
  evidence-store port. For example, Coding PR Delivery review-handoff evidence
  reads and writes go through `CodingPrDelivery.Readiness.EvidenceStore`; only
  the bundled `HostAdapters.Readiness.StateTransitionReadinessBackend` adapts the
  platform `Workflow.StateTransitionReadiness.Store`. Evidence-store calls may
  remain non-blocking for readiness side channels, but invalid options, invalid
  backends, backend exceptions, and invalid backend returns must emit bounded
  observability diagnostics and must not expose raw evidence payloads or
  exception messages.
  Scope checks, category readiness rules, observed-evidence diagnostics, and
  context projection live in focused extension-owned submodules so the policy
  facade does not become a store adapter or rule aggregate. Raw workflow,
  issue, and option inputs are normalized once at the extension context and
  options adapter boundary: keyword opts stay keyword opts, platform DTOs use
  explicit typed selectors, and raw external maps must use canonical string
  keys. Check/rule modules should receive normalized context instead of
  re-reading raw maps or keyword options. Coding PR Delivery review handoff
  projects target-state options through `ReviewHandoff.Context`;
  structured-plan review handoff projects gate state through
  `StructuredPlanReviewHandoff.Context`.
  Review-handoff evidence recorders stay non-blocking, but invalid recorder
  options must emit bounded observability/audit diagnostics instead of being
  silently swallowed. Remediation rules describe capability categories, while a
  `ReviewHandoff.Remediation.CapabilityProvider` boundary maps those categories
  to concrete capability ids. Only the bundled provider module may bind built-in
  Tracker/Repo/RepoProvider capability modules; external plugin packages should
  replace the provider through that contract instead of changing remediation
  rules.
  Keep boundary tests such as
  `workflow/structured_execution_plan/prompt_boundary_test.exs` in place when
  adding prompt, Workpad, rendering, or readiness integrations.
  Workflow structured-plan canonical tool execution follows the same focused
  owner rule: `ToolExecutor` remains the root dispatch/orchestration facade,
  while the focused `Tool.*` namespace owns the internal tool surface:
  `Tool.Contract` owns tool names, argument/result keys, side-effect metadata,
  risk flags, and mode values; `Tool.Specs` owns Dynamic Tool specs, JSON
  Schema fragments, and descriptions; `Tool.Arguments` owns raw Dynamic Tool
  input parsing; `Tool.Guards` owns revision, item, and evidence-bound
  completion guards; `Tool.Result` owns typed result envelopes and bounded
  summaries; and `Tool.ErrorCodes` owns workflow tool machine codes.
  Workflow Workpad projection also follows this focused-owner rule:
  `Workpad.Renderer` remains the deterministic rendering facade,
  `Workpad.Contract` owns render schema, marker keys, result keys,
  modes, and display limits; `Workpad.Marker` owns marker
  construction, fingerprinting, and canonical-plan validation;
  `Workpad.Labels` owns human-facing presentation labels and messages;
  `Workpad.Markdown` owns Markdown body assembly only;
  `Workpad.Markdown.Projector` owns canonical plan/item/evidence
  summaries for rendering; `Workpad.Markdown.Text` owns bounded
  redacted text normalization; `Workpad.Markdown.Syntax` owns Markdown
  syntax tokens and line/detail assembly; and `Workpad.ErrorCodes`
  owns rendering machine codes while delegating generic validation codes.
  Backend Workpad writing shares this Workpad projection subdomain:
  `Workpad.Writer` is only the public orchestration facade;
  `Workpad.Writer.Options` owns caller option normalization;
  `Workpad.Writer.Guards` owns render gates and plan mutability checks;
  `Workpad.Writer.Decision` owns persisted Workpad identity decisions;
  `Workpad.Writer.TrackerTool` owns the tracker typed-tool boundary and
  resolves default tracker write tools by the `tracker.upsert_workpad`
  capability; and `Workpad.Writer.Result` / `ErrorCodes` own writer
  envelopes and machine codes. Structured-plan core must not branch on concrete
  tracker names such as Linear or TAPD to choose writer tools.
  SQLite storage is the default non-test local/single-node durable storage, not
  a multi-node production cluster store; memory storage is reserved for tests
  and explicitly non-durable runs. Agent-owned plan tools remain explicit
  opt-in surfaces and must not be added to the default Dynamic Tool inventory
  until authorization, operator inspection, retention/redaction, and production
  rollout evidence are implemented.
- Review-handoff and other readiness bars follow a fixed layering rule:
  workflow templates guide agent order, typed tools and evidence recorders write
  structured evidence, structured execution-plan state models durable ordered
  steps when needed, readiness policies make fail-closed transition decisions,
  and tool-error diagnostics explain missing or stale facts with remediation
  actions. Do not make prompt text authoritative, and do not let tool errors
  become hidden workflow engines.
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
- `orchestrator/running/`: running issue reconciliation, bounded completion grace, stall detection, termination cleanup, and running-state views
- `tracker/`: provider-neutral tracker config, registry, errors, serialization, and shared adapter support
- `tracker/<kind>/`: tracker-specific adapters, clients, query definitions, transport helpers, pagination, normalizers, codecs and codec internals, dynamic-tool executor internals, workspace preparation, and workflow helpers
- `repo/`: provider-neutral repository model, Git facade, branch/path/status helpers, preflight checks, and repo errors
- `repo/git/`: Git implementation internals for command execution, argument building, repository inspection, remote operations, branch operations, commit operations, status parsing, reference parsing, validation, and error classification
- `repo_provider/`: provider-neutral repo-provider config, registry, command dispatch, errors, and adapter support
- `repo_provider/invocation/`: repo-provider CLI invocation parsing for command routing, option groups, body files, and field projection
- `repo_provider/smoke/`: repo-provider smoke orchestration, probe execution, and CNB auto-provision workflow internals
- `repo_provider/<kind>/`: repo-provider-specific adapters, clients, handlers, and normalizers
- `storage/`: platform durable-storage infrastructure, configuration normalization, Ecto Repo, migration runner, table catalog, shared storage error codes, and storage-governance boundaries
- `agent/`: provider-neutral Agent run lifecycle, continuation, runtime context, and failure classification
- `agent/dynamic_tool/`: provider-neutral Dynamic Tool context capture, workflow-required tool planning, inventory rendering, bridge execution, policy, usage classification, source aggregation, and spec normalization
- `agent/execution_plan/`: provider-neutral execution-plan contract, schema, record normalization, status machine, storage-backed Store boundary, typed Store commands, immutable evidence-ref helpers, and explicit opt-in typed-tool surface
- `agent/credential/ref.ex`: stable managed credential reference formatter for `credential://provider/id`
- `agent/credential/accounts/`: managed account login, import, verification, lifecycle, environment, and provider callback internals
- `agent/runner/`: Agent runner internals for run execution, worker workspace attempts, provider session loops, turn loops, run context shaping, prompt construction, worker update forwarding, event fields, turn event mapping, run terminal events, provider session cleanup, cleanup arbitration, and provider-option projection
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
| `assembly_catalog/` | application assembly catalog | flat, source-only modules that list built-in storage contracts, workflow runtime extensions, capability source modules, Dynamic Tool source modules, or future plugin manifest projections | storage/workflow/capability/Dynamic Tool mechanism logic, concrete capability string definitions, workflow profile business rules, provider transport calls, Dynamic Tool planning or execution, physical storage runtime APIs | `AssemblyCatalog.StorageContracts`, `AssemblyCatalog.WorkflowExtensions`, `AssemblyCatalog.CapabilitySources`, `AssemblyCatalog.DynamicToolSources` |
| `capability/` | platform capability-source aggregation | domain-owned capability source behaviour, capability source-catalog behaviour, trusted capability source registry, typed-tool/merge-gate/diagnostic/known-unavailable aggregation, fail-closed source payload validation | concrete provider capability string ownership, built-in source lists, workflow profile business rules, Dynamic Tool core interpretation of capability semantics | `Capability.Source`, `Capability.SourceCatalog`, `Capability.Registry` |
| `cli.ex` | escript entrypoint | top-level CLI argument flow and boot handoff | subcommand parsing, orchestration internals, tracker client code | `SymphonyElixir.CLI` |
| `cli/` | CLI subcommand implementation | subcommand facades, command parsing, option resolution, command routing, token source handling, output rendering | domain execution internals, tracker transport, provider protocol handling, workflow extension operator-command dispatcher mechanics, concrete extension business command modules | `CLI.Accounts`, `CLI.Accounts.Parser`, `CLI.Accounts.TokenSource`, `CLI.Accounts.Renderer`, `CLI.Repo.Runner` |
| `mix/tasks/` | Mix task entrypoints | stable platform task entrypoints and thin adapters to platform facades | concrete workflow extension business commands, plugin internals, provider payload interpretation | `Mix.Tasks.Workflow.Command` |
| `config.ex` | public config facade | stable config API, high-level validation entrypoints | schema helpers, normalization internals, formatting helpers | `SymphonyElixir.Config` |
| `config/` | config implementation | schema aggregation, defaults, finalization, normalization, error shaping | workflow loading, tracker HTTP, runtime orchestration | `Schema`, `InputNormalizer`, `SettingsFinalizer`, `SandboxPolicy` |
| `config/schema/` | embedded config schema internals | domain-specific schema casting and validation for tracker, repo, agent, runtime, provider, observability, hooks, server settings, and state limits | workflow profile resolution, provider runtime clients, tracker HTTP | `Tracker`, `Runtime`, `Repo`, `AgentProvider`, `Observability`, `StateLimits` |
| `storage/` | platform durable-storage infrastructure | platform backend normalization, Ecto Repo ownership, migration runner, table-level catalog inventory, catalog source protocol, shared storage error codes, governance backend validation, backup/retention/redaction boundaries | concrete catalog assembly, subsystem schemas, workflow/plugin payload semantics, domain state-machine rules, provider payload interpretation | `Storage.Config`, `Storage.Repo`, `Storage.Migrator`, `Storage.TableCatalog`, `Storage.TableCatalog.Entry`, `Storage.TableCatalog.Source`, `Storage.Backend`, `Storage.ErrorCodes`, `Storage.Backup`, `Storage.Retention`, `Storage.Redaction` |
| `workflow.ex` | public workflow facade | workflow access entrypoints | prompt rendering internals, route policy internals, store lifecycle details | `SymphonyElixir.Workflow` |
| `workflow/` | workflow implementation and workflow-platform contracts | prompt builder, route policy, workflow store, workflow-profile resolution, extension contribution aggregation for profiles/templates/validators/readiness evidence, execution-profile registry loading, entry matching, selection, validation, workflow-required Dynamic Tool planning, workflow Dynamic Tool result recording adapter, and workflow extension platform mechanisms | config schema logic, tracker vendor code, concrete extension business rules, physical storage adapter internals, extension-owned template Markdown assets, built-in Dynamic Tool source lists | `PromptBuilder`, `RoutePolicy`, `Store`, `ProfileRegistry`, `CompletionValidator`, `ExecutionProfileRegistry.Selection`, `DynamicToolPlan`, `DynamicToolResultRecorder`, `Extension`, `Extension.Runtime`, `Extension.Registry`, `Extension.StateStore` |
| `workflow/template.ex` | public workflow template facade | stable lookup, resolution, asset-root, and template-entry construction API for template consumers and contributors | concrete extension business rules, template Markdown contents, registry internals, asset-root mechanics | `Workflow.Template` |
| `workflow/template/` | workflow template platform contract and mechanism internals | public template-entry record, OTP `priv/` asset-root resolution, template-entry registry and contribution aggregation, template alias/path validation, registered template resolution, centralized path vocabulary, and `_partials/` root checks | concrete extension business rules, provider/tracker adapters, template Markdown contents, global directory scanning, source-relative `priv/` path discovery, ordinary caller API ownership | `Template.Entry`, `Template.Assets`, `Template.Registry`, `Template.Resolver`, `Template.PathRules` |
| `workflow/extension/` | workflow extension platform boundary | extension behaviour contract, trusted registry source behaviour, contribution aggregator, runtime context/projection/result envelopes, workflow-scope contract, typed runtime commands, bounded platform diagnostic type labels, versioned canonical durable identity codecs, operator-command contract, tool-result-recorder contract, completion-validator contract, registries, and dispatchers, normalized registry entries, and extension-owned state facade | concrete extension business rules, plugin installation lifecycle, tracker/repo provider logic, direct Orchestrator poll-cycle logic, extension-owned payload codecs, arbitrary runtime-term hashing | `Extension`, `Extension.Contributions`, `Extension.Diagnostics`, `Extension.Canonical`, `Extension.Registry`, `Extension.Registry.Config`, `Extension.Registry.Collector`, `Extension.Registry.Validator`, `Extension.Registry.Error`, `Extension.Registry.Entry`, `Extension.Registry.Source`, `Extension.Runtime`, `Extension.Runtime.Dispatcher`, `Extension.Runtime.Options`, `Extension.Runtime.Context`, `Extension.Runtime.Projection`, `Extension.Runtime.Result`, `Extension.Runtime.ResultApplier`, `Extension.Runtime.Command`, `Extension.Runtime.CommandExecutor`, `Extension.Runtime.Error`, `Extension.Runtime.Scope`, `Extension.OperatorCommand`, `Extension.CompletionValidator`, `Extension.OperatorCommand.Registry`, `Extension.OperatorCommand.Dispatcher`, `Extension.ToolResultRecorder`, `Extension.ToolResultRecorder.Registry`, `Extension.ToolResultRecorder.Dispatcher`, `Extension.StateStore` |
| `workflow/extension/runtime/` | workflow extension runtime internals | callback input context, workflow-scope construction and validation, approved runtime fact projection, callback output result, typed platform command values, runtime option normalization, sequential dispatch, result application, command execution handoff, and bounded runtime error envelopes | concrete extension business rules, registry source loading internals, operator commands, tool-result recorder dispatch, state-store adapters, Orchestrator-owned side effects | `Runtime.Dispatcher`, `Runtime.Options`, `Runtime.Context`, `Runtime.Scope`, `Runtime.Projection`, `Runtime.Result`, `Runtime.ResultApplier`, `Runtime.Command`, `Runtime.CommandExecutor`, `Runtime.Error` |
| `workflow/extensions/` | built-in workflow runtime extensions | thin extension facades, bundled manifest projections, extension-owned template catalogs built on public template contracts with focused contract/assets/credential-policy modules, runtime adapters, supervision declarations, profiles, completion validators with focused option/input/check/observation/result/value contracts, readiness policies/evidence providers, structured-plan reader ports and readiness helpers, structured-plan evidence binding providers, runtime children, business services, tool-result recorders, operator command implementations, config validators, business models, registries, payload codecs, reference extractors, and storage ports behind platform extension contracts | plugin installation lifecycle, application extension-catalog assembly, physical storage APIs, generic extension registry/dispatcher mechanics, platform Orchestrator state-machine ownership and resource registries, workflow template registry internals, bundled host facade adapter implementations outside `host_adapters/` | `Extensions.CodingPrDelivery`, `Extensions.CodingPrDelivery.Manifest`, `Extensions.CodingPrDelivery.TemplateCatalog`, `Extensions.CodingPrDelivery.TemplateCatalog.Contract`, `Extensions.CodingPrDelivery.TemplateCatalog.Assets`, `Extensions.CodingPrDelivery.TemplateCatalog.CredentialPolicy`, `Extensions.CodingPrDelivery.Runtime`, `Extensions.CodingPrDelivery.Supervision`, `Extensions.CodingPrDelivery.Profile`, `Extensions.CodingPrDelivery.CompletionValidator`, `Extensions.CodingPrDelivery.CompletionValidator.Options`, `Extensions.CodingPrDelivery.CompletionValidator.EvidenceReader`, `Extensions.CodingPrDelivery.CompletionValidator.Checks`, `Extensions.CodingPrDelivery.CompletionValidator.CheckSet`, `Extensions.CodingPrDelivery.CompletionValidator.ObservedEvidence`, `Extensions.CodingPrDelivery.CompletionValidator.ResultBuilder`, `Extensions.CodingPrDelivery.CompletionValidator.Contract`, `Extensions.CodingPrDelivery.CompletionValidator.EvidenceContract`, `Extensions.CodingPrDelivery.CompletionValidator.Values`, `Extensions.CodingPrDelivery.ToolResultRecorder`, `Extensions.CodingPrDelivery.OperatorCommands.ChangeProposalReconcile`, `Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding`, `Extensions.CodingPrDelivery.Reconciliation`, `Extensions.CodingPrDelivery.Reconciliation.ProviderFacts`, `Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.*`, `Extensions.CodingPrDelivery.Readiness.EvidenceProvider`, `Extensions.CodingPrDelivery.Readiness.EvidenceProvider.*`, `Extensions.CodingPrDelivery.Readiness.ReviewHandoff`, `Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff`, `Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Plan.Reader`, `Extensions.CodingPrDelivery.KnownTarget`, `Extensions.CodingPrDelivery.KnownTarget.ReferenceExtractor`, `Extensions.CodingPrDelivery.KnownTarget.Storage` |
| `workflow/extensions/*/host_adapters/` | bundled workflow extension host adapters | explicit adapters from an extension-owned port/default-deps contract to host platform facades such as Workflow, Tracker, RepoProvider, Observability, StateTransitionReadiness, ProfileRegistry, or StructuredExecutionPlan stores | extension domain rules, payload interpretation, reconciliation decisions, readiness checks, registry/state mutation rules, generic platform mechanisms | `Extensions.CodingPrDelivery.HostAdapters.CompletionValidator.ProfileDefaults`, `Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ConfigSourceDefaults`, `Extensions.CodingPrDelivery.HostAdapters.Reconciliation.EventBaseFieldDefaults`, `Extensions.CodingPrDelivery.HostAdapters.Reconciliation.EventEmitterDefaults`, `Extensions.CodingPrDelivery.HostAdapters.Reconciliation.OneShotHostDeps`, `Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProducerDefaults`, `Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProviderFactsDefaults`, `Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ReconcilerDefaults`, `Extensions.CodingPrDelivery.HostAdapters.Reconciliation.RouteContextDefaults`, `Extensions.CodingPrDelivery.HostAdapters.Reconciliation.TransitionDefaults`, `Extensions.CodingPrDelivery.HostAdapters.Readiness.EventEmitterDefaults`, `Extensions.CodingPrDelivery.HostAdapters.Readiness.StateTransitionReadinessBackend`, `Extensions.CodingPrDelivery.HostAdapters.Readiness.StructuredPlanReaderStoreBackend` |
| `priv/workflow_extensions/` | built-in workflow extension runtime assets | Markdown templates, prompt partials, and static assets registered by the owning built-in extension through template entries | Elixir modules, extension execution logic, plugin registry sources, provider adapters, storage adapters, platform mechanisms, external plugin package assets after split-out | `priv/workflow_extensions/coding_pr_delivery/templates/` |
| `workflow/extension/state_store/` | workflow extension-owned state envelope and adapters | option validation, app-config validation, backend selection, bounded state-store error envelopes, JSON-compatible opaque state envelope, bounded validation diagnostics, memory backend, durable adapter, and storage-specific mapping | extension business rules, plugin discovery, Orchestrator poll-cycle logic, public destructive reset API, physical Repo/Ecto ownership in the facade, backend selection inside `state_store.ex` | `Extension.StateStore.Options`, `Extension.StateStore.Config`, `Extension.StateStore.BackendSelector`, `Extension.StateStore.Error`, `Extension.StateStore.Record`, `Extension.StateStore.MemoryBackend`, `Extension.StateStore.Storage.SQLiteBackend` |
| `workflow/profiles/` | platform-owned workflow profile contracts | platform-owned profile modules, route vocabulary, profile-owned options, capability requirements, and profile-owned structured-plan adoption entrypoints | structured execution-plan core schema/store/tool/evidence mechanisms, tracker vendor code, concrete extension-owned profiles | `RequirementAnalysis`, `RequirementRefinement`, `ReviewRouting`, `Triage` |
| `workflow/profiles/<profile>/` | one profile's extension modules | profile-specific structured-plan adoption templates, profile-owned readiness adapters, and profile-local business mappings | generic structured-plan core mechanisms, other profiles' business steps | `RequirementAnalysis.StructuredExecutionPlan` |
| `issue.ex` | core issue model | normalized issue struct and issue-level accessors | tracker API code, lifecycle coordination | `SymphonyElixir.Issue` |
| `issue/` | issue domain helpers | issue lifecycle interpretation or issue-specific policy | orchestrator loop control, tracker HTTP | `Lifecycle` |
| `tracker.ex` | tracker boundary facade | behaviour, adapter lookup, shared facade calls | vendor-specific request building, response normalization | `SymphonyElixir.Tracker` |
| `tracker/` | provider-neutral tracker internals | tracker-owned capabilities, config access, registry, kind identifiers, normalized errors, serialization, project refs, smoke validation, memory adapter, tracker Dynamic Tool source adapter | tracker-vendor transport details, repo-provider behavior, concrete workflow extension result consumption, change-proposal-specific reference value objects or extraction semantics | `Capabilities`, `Config`, `ConfigAccess`, `Kinds`, `Registry`, `Error`, `ProjectRef`, `Smoke`, `DynamicToolSource` |
| `tracker/<kind>/` | one tracker integration | adapter, client facade, query definitions, transport helpers, pagination, provider-option extraction, payload decoding, ID lookup, relation enrichment, error classification, normalizer, codecs and codec internals, dynamic-tool executor internals, tracker-specific workspace preparation, tracker-specific workflow helpers | orchestrator state machine code, generic workspace logic, test-only client forwarding APIs for internal reader or pagination modules | `Linear.Adapter`, `Linear.GraphQL`, `Linear.IssueReader`, `Tapd.Client.Reader`, `Tapd.Client.Request`, `Tapd.WorkspacePreparation`, `Tapd.CommentCodec`, `Tapd.CommentCodec.DescriptionEncoder`, `Tapd.ToolExecutor.TypedTools` |
| `repo.ex` | repository boundary facade | stable repository API for branch, status, preflight, and Git-backed operations | Git command mechanics, repo-provider API calls, tracker behavior | `SymphonyElixir.Repo` |
| `repo/` | provider-neutral repository internals | repo-owned capabilities, branch/status/error data, preflight checks, Git facade, repository context helpers, Dynamic Tool repo context resolution | raw Git command execution, repo-provider transport details, tracker workflow behavior, orchestration state | `Capabilities`, `Branch`, `Status`, `Error`, `Preflight`, `Git`, `DynamicToolContext` |
| `repo/git/` | Git implementation internals | command execution, scoped arguments, Git config projection, argument builders, repository inspection, remote/clone/push operations, branch/merge operations, commit/stage operations, status parsing, reference parsing, error classification, invocation validation | public repository API expansion, repo-provider adapter behavior, workflow/orchestrator policy | `Command`, `Arguments`, `Inspection`, `Remote`, `Branches`, `Commits`, `StatusParser`, `References`, `Errors`, `Validation` |
| `repo_provider.ex` | repo-provider boundary facade | adapter lookup, capability checks, public repo-provider operations | provider-specific API calls, workflow text, concrete workflow extension business models, CLI parsing details | `SymphonyElixir.RepoProvider` |
| `repo_provider/` | provider-neutral repo-provider internals | repo-provider-owned capabilities, config access, registry, kind identifiers, normalized check-run helpers, command dispatch, result/output shaping, errors, land-watch orchestration, smoke orchestration | tracker behavior, provider-specific API details, concrete workflow extension business semantics | `Capabilities`, `Config`, `ConfigAccess`, `Kinds`, `CheckRun`, `Registry`, `Command`, `LandWatch`, `Error` |
| `repo_provider/cli/` | repo-provider CLI runtime adapter internals | environment loading, runtime config resolution, invocation evaluation, observability events, and CLI result tuples | argv option parsing, command execution internals, provider-specific transport | `CLI.Evaluator` |
| `repo_provider/command/` | repo-provider command execution internals | parsed invocation option projection, command-specific result rendering, watch loops, and exit-code policy | argv parsing, provider-specific transport, shell command execution | `Command.Options`, `Command.Checks` |
| `repo_provider/invocation/` | repo-provider CLI invocation parser internals | provider override parsing, command routing, PR/API/run option parsing, body-file reads, JSON field lists | provider adapter execution, output rendering, shell command execution | `CommandParser`, `PullRequest`, `Reviews`, `Api`, `Runs`, `Options` |
| `repo_provider/smoke/` | repo-provider smoke test implementation | probe construction/execution, mode selection, smoke report rendering, event emission, destructive smoke flows, CNB auto-provision context, git setup, PR flow, run polling, and cleanup | provider adapter API clients, generic CLI parsing, tracker behavior | `Smoke.ProbeRunner`, `Smoke.ReadOnly`, `Smoke.Destructive`, `Smoke.Report`, `Smoke.CNBProvisioner.Context`, `Smoke.CNBProvisioner.PRFlow` |
| `repo_provider/<kind>/` | one repo-provider integration | adapter, client, handler facades and focused handler submodules, base branch resolution, normalizer facade and focused normalizer submodules, provider-specific command execution, runtime HTTP option parsing | tracker transport, generic orchestrator policy | `GitHub.Adapter`, `CNB.HttpClient`, `CNB.PullRequestHandler.Resolution`, `CNB.ApiHandler.Router`, `CNB.Normalizer.Pull` |
| `agent.ex` | provider-neutral Agent facade | stable run entrypoint | provider-specific CLI/app-server code, orchestrator GenServer state | `SymphonyElixir.Agent` |
| `agent/` | provider-neutral Agent run lifecycle | agent-owned capabilities, workspace run flow, continuation, runtime context, generic failure classification | concrete AI agent protocol handling, tracker adapters, test-only wrappers around runner internals | `Capabilities`, `Runner`, `Continuation`, `FailureClassifier`, `DynamicTool.Context` |
| `agent/dynamic_tool/` | provider-neutral Dynamic Tool platform core | source context capture into a stable context record, strict canonical string-key raw `tool_context` normalization, internal `ToolSpec`, `Metadata`, and `Context.ToolPlan` records with canonical map projections at provider boundaries, provider-facing inventory resolution/rendering for supplied capability strings, side-effect policy, bridge execution, usage classification, configurable source aggregation, source module validation, source-catalog contract expansion, result-recorder dispatch, generic repeated-failure escalation | workflow-required tool planning, workflow readiness/review-handoff policy, tracker/repo/repo-provider business semantics, provider-native tool registration details, default source assembly, interpreting source-owned `source_context` payloads | `Context`, `Context.ToolPlan`, `ToolSpec`, `Metadata`, `Inventory`, `Inventory.ResolvedTool`, `Inventory.Renderer`, `Bridge`, `Bridge.Result`, `Bridge.Audit`, `Policy`, `Usage`, `CompositeSource`, `Source`, `SourceCatalog`, `ResultRecorder`, `Spec`, `TypedToolFailurePolicy` |
| `agent/execution_plan/` | generic Agent execution-plan core | provider-neutral plan contract, schema validation, status-machine transitions, storage behaviour, memory test backend, local SQLite durable backend, immutable evidence-ref helpers, explicit opt-in typed-tool contracts and source | workflow envelope fields, workflow Workpad projection, route/profile readiness policy, default Dynamic Tool exposure, multi-node storage semantics | `Contract`, `Schema`, `StatusMachine`, `Evidence`, `Storage`, `Store`, `Tool.Contract`, `Tool.Specs`, `Tool.Arguments`, `Tool.Payload`, `Tool.Command`, `Tool.Options`, `Tool.Guards`, `Tool.Result`, `ToolExecutor`, `DynamicToolSource` |
| `agent/credential/ref.ex` | managed credential reference contract | provider-neutral `credential://provider/id` reference formatting shared by credential stores and higher-level profile/template code | credential storage IO, lease acquisition, account lifecycle, provider protocol handling | `SymphonyElixir.Agent.Credential.Ref` |
| `agent/credential/accounts.ex` | managed account facade | public account login/import/list/verify/lifecycle API and provider-kind normalization entrypoint | provider command execution, file import mechanics, adapter callback dispatch | `SymphonyElixir.Agent.Credential.Accounts` |
| `agent/credential/accounts/` | managed account implementation | provider-kind normalization, account login/import, verification command execution, lifecycle Store calls, credential environment shaping, secret file operations, provider callback dispatch | CLI parsing, provider session protocol clients, orchestrator policy | `Login`, `Import`, `Verification`, `Lifecycle`, `Environment`, `Command`, `Secret`, `ProviderKind`, `ProviderCallbacks`, `Options` |
| `agent/runner/` | Agent runner implementation internals | run execution, worker workspace attempts, provider session loops, turn loops, run context shaping, prompt construction, worker update forwarding, event field projection, turn event/error mapping, run terminal event emission, provider session cleanup, cleanup arbitration, provider-option projection | provider protocol clients, orchestrator GenServer state, tracker adapters | `Execution`, `WorkerAttempt`, `SessionLoop`, `TurnLoop`, `RunContext`, `Prompts`, `WorkerUpdates`, `EventFields`, `TurnEvents`, `RunEvents`, `ActiveSessions`, `SessionCleanup`, `ProviderOptions` |
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
| `orchestrator/running/` | running issue lifecycle implementation | issue-state reconciliation, bounded completion grace decisions, stalled-run detection, task termination and claim cleanup, running/claimed/retry state access, and reconcile event emission | dispatch eligibility policy, retry scheduling policy, worker-exit classification, tracker transport | `Running.Reconciliation`, `Running.CompletionGrace`, `Running.StallDetection`, `Running.Termination`, `Running.StateView`, `Running.Events` |
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
- Provider session cleanup arbitration belongs under `agent/runner/`.
  Normal/exception completion and worker-owner exit handling must claim the
  active session before invoking provider stop; a path that loses the claim
  must no-op rather than emitting a duplicate cleanup failure.
- Dispatch context, issue ordering, eligibility checks, skip reasons, runtime
  slot projection, revalidation, and route-preparation policy belong under
  `orchestrator/dispatch/`; keep `orchestrator/dispatch.ex` as the facade used
  by orchestration callers.
- Retry timer scheduling, retry timer message handling, attempt metadata
  shaping, retry events, retry issue lookup, retry release/defer decisions, and
  redispatch handoff belong under `orchestrator/retry/`; keep
  `orchestrator/retry.ex` as the facade used by orchestration callers.
- Running issue reconciliation, bounded completion grace, stalled-run
  detection, task termination, claim cleanup, running/retry state access, and
  reconcile events belong under `orchestrator/running/`; keep
  `orchestrator/running.ex` as the facade used by orchestration callers.
- Running reconciliation and worker-exit lifecycle code must get workflow state
  meaning through `Orchestrator.Dispatch` predicates. Do not hardcode concrete
  business state names or branch on concrete agent-provider implementations in
  `orchestrator/running/` or `orchestrator/worker_exit.ex`.
- Worker-exit lifecycle code may refresh the just-finished issue's tracker
  facts before deciding retry or continuation, but that refresh must be
  a fallback rather than the primary success path. Agent runner code should
  propagate refreshed `%Issue{}` facts through worker runtime info as soon as
  turn-level state refresh succeeds. Worker-exit refresh remains
  provider-neutral, single-issue, bounded by a short timeout, and safe to skip;
  timeout or tracker failure falls back to the cached running entry and must not
  block the orchestrator indefinitely or become a provider failure.
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
  The supplied context should be an `Agent.DynamicTool.Context` record or a
  canonical string-key raw map accepted by the Dynamic Tool boundary. It should
  not inspect issue state, workflow routes, or Dynamic Tool sources to decide
  tool exposure.

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

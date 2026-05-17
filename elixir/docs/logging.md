# Logging and Observability Guide

This guide defines the current Elixir implementation logging, status-surface,
and observability contract for Maestro.

It complements:

- [`./architecture.md`](./architecture.md): module placement, namespace ownership, and refactor conventions
- [`./agent_providers/README.md`](./agent_providers/README.md): provider-specific runtime and protocol guides
- [`../README.md`](../README.md): operator-facing runtime behavior

## Current Standard

Phases 1, 2, and 3 of the structured observability model are implemented, and the follow-up
edge-path and terminal drill-down work is now part of the shipped baseline. The Elixir reference
therefore has a production-grade observability loop for its current scope: canonical structured
events, centralized redaction, bounded queryable history, JSON-default file logs, dashboard/API
projections, and summary-first terminal drill-down.

That does not mean all observability work is finished. Remaining work is now optional extension work
rather than missing loop components: longer retention, external exporters, alerting, and deeper
operator ergonomics can still improve over time.

Use `SymphonyElixir.Observability.Logger.emit/3` for machine-readable audit and lifecycle events.
Use `SymphonyElixir.Observability.Logger.text/3` for low-value operator-facing text lines when a
canonical event is not warranted.
Avoid introducing new direct `Logger.*` calls in application code.

Current infrastructure notes:

- `Observability.Logger.emit/3` emits canonical event fields into logger metadata instead of packing
  the entire event into one ad hoc message string
- `Observability.Logger.emit/3` and `Observability.Logger.text/3` inherit request-scoped logger
  metadata such as `request_id` automatically
- issue-run scoped logs now carry `run_id` and derive `correlation_id` from `request_id` or `run_id`
- canonical observability metadata fields are defined once in
  `SymphonyElixir.Observability.Fields` and reused by the event envelope, logger, and formatter
- `Observability.Logger.emit/3` also feeds a bounded in-memory structured event store for
  issue/session/run history
- the event-store retention window and async mailbox pressure limit are workflow-configurable, so
  observability traffic cannot create unbounded retained state or process queue growth
- the public event-store entrypoint is `SymphonyElixir.Observability.EventStore`; its config,
  state, index, query, input-normalization, and mailbox pressure implementation modules live under
  `SymphonyElixir.Observability.EventStore.*`
- the rotating file handler can now be configured independently from the console handler
- file logs support `observability.log_format: text | json` and default to `json`
- JSON file formatting is handled by a dedicated formatter, while text formatting stays on OTP's
  normal handler/formatter path
- the public log sink entrypoint is `SymphonyElixir.Observability.LogFile`; its path, runtime
  config, handler, formatter, and sink-event implementation modules live under
  `SymphonyElixir.Observability.LogFile.*`
- JSON file formatting performs a final redaction pass over canonical `observability_event`
  metadata before encoding
- console logging is opt-in by workflow config and, when enabled, includes selected observability
  metadata instead of only bare messages
- redaction summary truncation, in-memory event-store retention, and event-store mailbox pressure
  protection are now workflow-configurable instead of being hardcoded process defaults
- issue API `recent_events` and `logs.agent_session_logs` are now projections of the same
  structured event model instead of placeholder arrays
- the LiveView dashboard now renders recent structured runtime events from the same shared store
- the LiveView dashboard now also serves `/issues/:issue_identifier`, projecting per-issue recent
  structured events and chronological agent session logs from the same shared store
- the terminal status surface now renders a bounded issue/session drill-down from the same shared
  store, so operators can inspect recent issue events and agent history without leaving the terminal

When introducing a new high-value runtime path, do not invent a local log shape first. Prefer the
shared observability helpers so the event is searchable, redactable, and tracker-neutral from day
one.

## Canonical Event Envelope

Structured events emitted through `Observability.Logger` normalize into one envelope with these
top-level fields:

- `timestamp`
- `level`
- `event`
- `message`
- `service`
- `component`

Common context fields:

- `request_id`
- `correlation_id`
- `run_id`
- `issue_id`
- `issue_identifier`
- `tracker_kind`
- `session_id`
- `thread_id`
- `turn_id`
- `attempt`
- `worker_host`
- `workspace_path`

Agent-provider correlation fields have provider-neutral semantics even when the
provider supplies different native identifiers:

- `session_id` is the primary cross-provider join key; its string format is
  provider-owned
- `thread_id` is a provider-native thread/conversation key when known
- `turn_id` is a provider-native turn/message key when known

Common diagnostic fields:

- `route_key`
- `target_route`
- `target_state`
- `tool_name`
- `dynamic_tool_exposure`
- `dynamic_tool_count`
- `dynamic_tool_names`
- `dynamic_tool_rejection_reason`
- `http_method`
- `http_path`
- `status`
- `duration_ms`
- `payload_summary`
- `result_summary`
- `error`
- `error_code`
- `failure_class`
- `operation`
- `retryable`
- `error_stack`

The implementation source of truth for context, message-context, and formatter metadata fields is
[`lib/symphony_elixir/observability/fields.ex`](../lib/symphony_elixir/observability/fields.ex).
Add new shared event fields there first, then use the existing event/logger/formatter projection
paths instead of maintaining local duplicate field lists.

Provider-neutral operation lifecycle status labels such as `started`,
`completed`, `failed`, `stopped`, and `prepared` are owned by
`SymphonyElixir.Observability.OperationStatus`. Turn terminal statuses are a
separate agent-provider contract owned by `SymphonyElixir.AgentProvider.TurnStatus`.

Dynamic Tool metric projection keys are owned by
`SymphonyElixir.Observability.DynamicToolMetrics`. Dynamic Tool operator alert
envelope keys and severity/status values are owned by
`SymphonyElixir.Observability.AlertContract`; dashboard rendering should consume
that contract instead of matching raw alert literals directly.

For HTTP/API-facing events, include the request-critical facts in both structured fields and the
human-readable `message` string. Text-mode operators often tail logs without a JSON parser, so the
message still needs to stand on its own. When a request runs inside Phoenix/Plug, preserve the
`request_id`; when an issue run spans orchestrator, workspace, and agent-provider components,
preserve the same `run_id`.

## Current Structured Event Families

The current Elixir code emits structured audit events for:

- service start / start-failure / stop lifecycle
- log sink configure / disable / config-failure lifecycle
- HTTP observability server start / ignore / start-failure lifecycle
- poll cycle start / completion, tracker candidate fetch failures, and core dispatch selection /
  skip / start / failure decisions
- reconcile / deferred-reconcile / stall-detection / worker-finish / retry / terminal-cleanup /
  cleanup orchestration tails
- workflow load / reload-failure lifecycle
- workflow observability reconfigure-skip lifecycle
- workspace prepare / automation bootstrap / hook / remove lifecycle, including bootstrap
  failure-stage summaries
- prompt workflow-availability / template-parse / render failures
- agent-provider session / turn / stream-output / stream-warning / malformed-stream / approval /
  input-required / process-termination lifecycle
- agent run / worker-attempt / continuation / max-turn / issue-refresh retry/failure lifecycle
- workflow route preparation and route transition outcomes
- dynamic tool request/start/success/failure/rejection
- Linear and TAPD tracker request start/success/failure
- Linear and TAPD comment creation and state-update write-backs
- observability API request completion / failure outcomes
- dashboard PubSub subscribe / skip / failure lifecycle
- dashboard LiveView mount / subscription failure / payload-load failure lifecycle
- dashboard offline / snapshot / terminal-frame render failures

Examples in code:

- [`lib/symphony_elixir/observability/logger.ex`](../lib/symphony_elixir/observability/logger.ex)
- [`lib/symphony_elixir/observability/event_store.ex`](../lib/symphony_elixir/observability/event_store.ex)
  and [`lib/symphony_elixir/observability/event_store/`](../lib/symphony_elixir/observability/event_store/)
- [`lib/symphony_elixir/observability/log_file.ex`](../lib/symphony_elixir/observability/log_file.ex)
  and [`lib/symphony_elixir/observability/log_file/`](../lib/symphony_elixir/observability/log_file/)
- [`lib/symphony_elixir/agent_provider/`](../lib/symphony_elixir/agent_provider/)
- [`lib/symphony_elixir/orchestrator.ex`](../lib/symphony_elixir/orchestrator.ex)
  and [`lib/symphony_elixir/orchestrator/`](../lib/symphony_elixir/orchestrator/)
- [`lib/symphony_elixir/observability/status_dashboard.ex`](../lib/symphony_elixir/observability/status_dashboard.ex)
  and [`lib/symphony_elixir/observability/status_dashboard/`](../lib/symphony_elixir/observability/status_dashboard/)
- [`lib/symphony_elixir/tracker/linear/`](../lib/symphony_elixir/tracker/linear/)
- [`lib/symphony_elixir/tracker/tapd/`](../lib/symphony_elixir/tracker/tapd/)

Provider-specific event names and lifecycle details belong in provider docs.
For the current default provider, see
[`agent_providers/codex.md`](./agent_providers/codex.md).

## Redaction Rules

Secrets must be redacted before they reach any sink.

Shared helpers:

- `SymphonyElixir.Observability.Redaction.redact/1`: recursive map/list/struct redaction
- `SymphonyElixir.Observability.Redaction.summarize/2`: redacted, truncated summary for payloads
- `SymphonyElixir.Observability.Redaction.redact_string/1`: string-level redaction for stream or
  command output

Current string redaction covers bearer/basic credentials, uppercase env assignments, plain
`token=...`/`authorization: ...`-style assignments, and JSON-like quoted secret fields.
Map-key redaction treats credential-shaped token keys such as `token`, `access_token`, and
`api_token` as secrets, while preserving plural usage metrics such as `input_tokens`,
`output_tokens`, `total_tokens`, and `token_count`.

Required practice:

- if you emit a structured event, pass raw fields to `Observability.Logger.emit/3`; it applies the
  shared redaction layer
- if you write a raw `Logger.*` line containing stream output, hook output, or command output,
  sanitize it with `Redaction.redact_string/1` first
- prefer summaries over full payload dumps
- truncation must keep output valid UTF-8 and append the explicit `...<truncated>` marker
- provider app-server or external-CLI adapters should emit `payload_summary` or
  `result_summary` for provider-native payloads and should not publish raw
  provider request/response bodies by default
- provider adapters should implement `summarize_message/1` through their own
  event-summary mapper when the provider emits structured native events; shared
  dashboard code should render the resulting provider-neutral summary instead of
  parsing provider-private payloads
- expected agent-provider failures should include provider kind, operation,
  stable `error_code`, `retryable`, and sanitized details when those fields are
  available

## Sink Configuration

Workflow `observability` config now supports:

- `dashboard_enabled`
- `refresh_ms`
- `render_interval_ms`
- `file_enabled`
- `console_enabled`
- `log_format`
- `summary_max_bytes`
- `global_event_limit`
- `issue_event_limit`
- `run_event_limit`
- `session_event_limit`
- `index_key_limit`
- `pending_event_queue_limit`

Practical behavior:

- `file_enabled: true` keeps Maestro's rotating file handler active
- `console_enabled: false` disables the default console handler explicitly instead of relying on
  startup-time implicit removal; this is the default workflow behavior
- `log_format: json` makes the rotating file sink emit JSON Lines
- `log_format: text` keeps a human-readable single-line text file format with selected metadata
- missing, `null`, or unsupported `log_format` values use the safe JSON default
- `summary_max_bytes` controls default redacted payload-summary truncation
- `global_event_limit`, `issue_event_limit`, `run_event_limit`, `session_event_limit`, and
  `index_key_limit` control bounded in-memory observability retention and index fan-out
- `pending_event_queue_limit` defaults to `5000` and bounds the async `EventStore` mailbox; events
  beyond the limit are dropped before enqueueing so observability cannot create unbounded process
  pressure while file/console logging continues through OTP Logger

## When Text Logs Are Still Acceptable

`Observability.Logger.text/3` is still acceptable for:

- one-off operator-facing process lifecycle messages
- operator-facing logs that still help local terminal reading
- low-value debug text that is not part of the audit trail

When using text logs:

- keep wording deterministic
- pass metadata fields alongside the text instead of burying identifiers inside free-form strings
- include `key=value` context for the highest-signal identifiers
- include `issue_id` and `issue_identifier` for issue-scoped work when known
- include `session_id` for agent session-scoped work when known
- include `request_id` for HTTP-scoped work when known
- include `run_id` for orchestrator/agent/workspace execution paths when known
- do not log large or secret-bearing payloads directly

## Required Context Fields

When logging issue-related work, include both identifiers when known:

- `issue_id`: tracker-native canonical issue ID
- `issue_identifier`: human-facing ticket key
- `run_id`: one stable execution ID for the current orchestrator/agent run

When logging agent execution lifecycle events, include:

- `run_id`
- `session_id` when the provider session is known
- `thread_id` when the provider emits a native thread/conversation key
- `turn_id` when the provider emits a native turn/message key

When logging remote execution or workspace activity, include when known:

- `worker_host`
- `workspace_path`
- `failure_class` when the event represents a classified SSH-worker failure

When logging cleanup activity, include:

- the target `worker_host` when cleanup is host-specific
- the recorded target `workspace_path` when known, rather than only a recomputed workspace hint

## Checklist For New Logging

- Is this path important for later audit, debugging, or cross-system correlation?
- If yes, should it be a structured event via `Observability.Logger.emit/3` instead of a raw text
  line?
- Are `issue_id` / `issue_identifier` present when the event is issue-scoped?
- Is `request_id` present when the event is request-scoped?
- Is `run_id` present when the event is one orchestrator/agent execution chain?
- Is `session_id` present when the event is agent-session-scoped and the
  provider session is known?
- Are `thread_id` / `turn_id` included when the provider emits those native
  identifiers?
- Are secrets removed before anything is logged?
- Did you summarize large payloads instead of dumping them verbatim?
- For Dynamic Tool rejections, did you include the planned exposure mode and a
  stable rejection reason such as `unsupported_tool`?
- Is the event/message shape consistent with the existing observability helpers?

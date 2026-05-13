# Codex Provider

The `codex` agent provider is Maestro's current default concrete AI
coding-agent integration. It is implemented under
[`lib/symphony_elixir/agent_provider/codex/`](../../lib/symphony_elixir/agent_provider/codex/)
and runs Codex through app-server mode.

Provider-neutral execution stays outside this directory:

- run lifecycle, continuation, runner internals, runtime context, and failure
  classification live under
  [`agent/`](../../lib/symphony_elixir/agent/)
- adapter contracts, registry, event/session/usage shapes, event summaries,
  and shared presentation live under
  [`agent_provider/`](../../lib/symphony_elixir/agent_provider/)
- dashboard rendering lives under
  [`observability/status_dashboard/`](../../lib/symphony_elixir/observability/status_dashboard/)

## Configuration

`agent_provider.kind` defaults to `codex`. Codex-specific runtime settings live
under `agent_provider.options`.

Typical local configuration:

```yaml
agent_provider:
  kind: codex
  options:
    command_argv: ["codex", "app-server"]
    approval_policy: never
    thread_sandbox: danger-full-access
    turn_sandbox_policy:
      type: dangerFullAccess
```

`command_argv` is the preferred production shape. It preserves argument
boundaries and is launched locally through an argument-vector process API. When
both `command_argv` and `command` are configured, Codex uses `command_argv`.

`command` is restricted to deployment-authored static commands:

```yaml
agent_provider:
  kind: codex
  options:
    command: codex app-server
```

Do not build `command` from issue, branch, repository, workflow, prompt, or
provider-generated values. Local string commands run through a shell. Remote
string commands are treated as a high-trust deployment-authored command string.

Supported Codex options:

- `command`
- `command_argv`
- `prompt_transport`
- `approval_policy`
- `thread_sandbox`
- `turn_sandbox_policy`
- `credential_ref`
- `turn_timeout_ms`
- `read_timeout_ms`
- `stall_timeout_ms`

`command` must be a non-blank string without newline, carriage return, or NUL
bytes. `command_argv` must be a non-empty list of non-blank strings without
newline, carriage return, or NUL bytes. Unknown Codex options fail validation.

`prompt_transport` currently supports only `json_rpc`.

Safer defaults are used when Codex policy fields are omitted:

- `approval_policy` defaults to `on-request`
- `thread_sandbox` defaults to `workspace-write`
- `turn_sandbox_policy` defaults to a `workspaceWrite` policy rooted at the
  current issue workspace

Supported `approval_policy` values depend on the targeted Codex app-server
version. The Codex CLI `0.128.0` app-server schema accepted string values such
as `untrusted`, `on-failure`, `on-request`, `granular`, and `never`. Maestro
passes map values through for later Codex protocol revisions, but a real smoke
on Codex CLI `0.128.0` rejected object-form `reject`; production profiles
should prefer documented string policies for the installed Codex version.

Supported `thread_sandbox` values:

- `read-only`
- `workspace-write`
- `danger-full-access`

When `turn_sandbox_policy` is set explicitly, Maestro passes the map through
to Codex unchanged. Acceptance then depends on the targeted Codex app-server
version rather than local Maestro validation.

## Managed Account Login

Codex managed credentials currently support only the `codex_api_key` account
shape. Maestro stores the OpenAI API key in the Agent Credentials secret store
and materializes a private file-backed `CODEX_HOME` for the Codex process.

Example:

```bash
jq -r '.OPENAI_API_KEY // empty' "$HOME/.codex/auth.json" \
  | symphony accounts login codex openai --token-stdin path/to/WORKFLOW.md

symphony accounts verify codex openai path/to/WORKFLOW.md
```

Reference the account from workflow config:

```yaml
agent:
  credentials:
    enabled: true
    store_root: ~/.symphony/agent_credentials

agent_provider:
  kind: codex
  options:
    command_argv: ["codex", "app-server"]
    approval_policy: never
    credential_ref: "credential://codex/openai"
```

The provider process receives `CODEX_HOME`, not `OPENAI_API_KEY`. Maestro
writes `CODEX_HOME/config.toml` with `cli_auth_credentials_store = "file"` and
`CODEX_HOME/auth.json` with the API-key login payload. Local materialized
directories are removed during credential cleanup. SSH and worker-daemon
placements write the same files on the worker before launch and remove that
worker-side `CODEX_HOME` when the session stops.

## Runtime Boundary

The provider facade builds a provider-neutral runtime context before starting
Codex. That context contains the prepared workspace root, hook timeout, and
resolved turn sandbox policy. Codex consumes that explicit context; the
app-server client should not read workflow config directly on the production
runtime path.

Codex command cwd is always the prepared issue workspace after local or remote
workspace-boundary validation. Local launches inherit only the explicit runtime
environment needed for repo-provider helpers and the workspace automation pack.
Remote `command_argv` launches are shell-quoted per argument before being sent
through SSH; remote string commands are high-trust deployment-authored command
strings.

## Automation Pack

Maestro bundles provider-neutral workspace automation under
[`priv/workspace_automation/`](../../priv/workspace_automation/). Workspace bootstrap resolves the bundled
or overridden source through
[`Workspace.AutomationPack`](../../lib/symphony_elixir/workspace/automation_pack.ex),
then asks the active provider where that pack should be installed. The Codex
adapter installs it once into each issue workspace root as `.codex` before
`hooks.after_create` runs.

This bundled pack is separate from the repository-root `.codex/` used for
developing Maestro itself. They are not synchronized mirrors. The
repository-root `.codex/skills` are local developer guidance for this checkout
and should use local tools such as `git` and `gh`; they must not depend on
`SYMPHONY_WORKSPACE_AUTOMATION_DIR` or bundled workspace helper paths.

`workspace.bootstrap_automation_from` can override the bundled pack when a
deployment needs a custom local workspace automation directory. Codex still copies
that override into `.codex`; future providers can copy the same source into
their own discovery directories such as `.claude` or `.opencode`.

## Event Mapping And Display

Codex app-server messages are sanitized and normalized before reaching shared
status surfaces:

- [`app_server.ex`](../../lib/symphony_elixir/agent_provider/codex/app_server.ex)
  owns app-server session lifecycle and terminal turn orchestration.
- [`app_server/session_protocol.ex`](../../lib/symphony_elixir/agent_provider/codex/app_server/session_protocol.ex)
  owns app-server initialize, `thread/start`, `turn/start`, and request-id
  response waiting.
- [`app_server/turn_stream.ex`](../../lib/symphony_elixir/agent_provider/codex/app_server/turn_stream.ex)
  owns turn stream reading, terminal turn events, notification dispatch, and
  turn request routing.
- [`app_server/stream_diagnostics.ex`](../../lib/symphony_elixir/agent_provider/codex/app_server/stream_diagnostics.ex)
  owns sanitized non-JSON stream classification and diagnostic logging for
  app-server response and turn streams.
- [`app_server/protocol.ex`](../../lib/symphony_elixir/agent_provider/codex/app_server/protocol.ex)
  owns app-server JSON-RPC writes through the Agent Runtime handle command
  boundary.
- [`app_server/turn_requests.ex`](../../lib/symphony_elixir/agent_provider/codex/app_server/turn_requests.ex)
  owns approval replies, dynamic-tool call replies, non-interactive tool-input
  replies, and input-required detection.
- [`app_server/messages.ex`](../../lib/symphony_elixir/agent_provider/codex/app_server/messages.ex)
  drops raw protocol strings from emitted messages, adds `payload_summary`, and
  redacts structured payloads, details, tool results, and error reasons.
- Shared event-field and process-metadata helpers live under
  [`agent_provider/app_server/`](../../lib/symphony_elixir/agent_provider/app_server/).
- [`event_mapper.ex`](../../lib/symphony_elixir/agent_provider/codex/event_mapper.ex)
  unwraps Codex payloads into the provider-neutral
  `SymphonyElixir.AgentProvider.Event` shape.
- [`event_summary_mapper/`](../../lib/symphony_elixir/agent_provider/codex/event_summary_mapper/)
  converts Codex payloads into provider-neutral event summaries.

Shared rendering belongs in
[`message_presenter.ex`](../../lib/symphony_elixir/agent_provider/message_presenter.ex),
not in Codex-specific mapper modules.

Status and dashboard summaries should prefer `payload_summary` or
`result_summary`. They must not depend on raw app-server request or response
bodies.

## Logging Semantics

Codex session-close events are terminal and mutually exclusive: one close path
emits either `codex_session_completed` or `codex_session_failed`, never both.

Treat `codex_session_failed` narrowly. It means the Codex session or app-server
path failed. If Codex finishes normally and a later agent/orchestrator step
fails, keep the session-close event as completed and emit a separate
component-owned failure event for that downstream path.

When the session is issue-scoped, close events include `issue_id` and
`issue_identifier`.

If local child-process shutdown requires escalation, Codex emits one
`codex_session_process_termination_escalated` event per attempted signal and
emits `codex_session_process_termination_incomplete` only if the OS process
remains alive after escalation.

Plain non-JSON side output that does not parse as protocol traffic is recorded
as `codex_stream_output` and surfaced to the status dashboard as
`stream_output`. Warning-classified side output emits `codex_stream_warning`
and dashboard `stream_warning`.

Expected Codex failures are normalized into
`SymphonyElixir.AgentProvider.Error` before returning through the adapter. The
current mapping covers command missing/invalid/exit, startup failure, turn
failure, timeout, response timeout, input required, cancellation, config
invalid, and cleanup failure. Error details are summaries and must not include
raw prompts, provider auth payloads, resolved secrets, or unbounded command
output.

## Production Readiness

The deterministic implementation gates cover configuration validation,
facade/adapter dispatch, command argv precedence, workspace boundary checks,
structured error normalization, payload redaction, and cleanup paths. A
deployment still must collect real integration evidence before claiming Codex
production readiness: installed/authenticated Codex CLI or app-server command,
one non-interactive successful turn, representative failure or timeout path,
approval/sandbox policy proof, redaction sample, and rollback procedure.

Token accounting is documented separately in
[`codex_token_accounting.md`](./codex_token_accounting.md).

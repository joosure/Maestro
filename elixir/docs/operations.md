# Operations Guide

This guide covers runtime configuration and operational behavior for the
Maestro Elixir runtime. The public product name is Maestro, while concrete
implementation identifiers still use compatibility names such as
`SymphonyElixir`, `symphony`, `.symphony`, and `SYMPHONY_*`.

## Runtime Prerequisites

Use [mise](https://mise.jdx.dev/) to manage Elixir/Erlang versions:

```bash
mise install
mise exec -- elixir --version
```

Workspace sessions and bundled helpers also rely on standard host tooling:

- `bash` and `git` for workspace bootstrap and repository operations
- `gh` for GitHub-backed PR automation
- `symphony` on `PATH`, or `SYMPHONY_CLI` pointing to the executable, for
  bundled workspace helpers
- `CNB_TOKEN` for CNB-backed repository operations

These environment names are maintained as explicit runtime contracts in code,
not repeated ad hoc across callers. Repo-core variables are owned by
`SymphonyElixir.Repo.RuntimeEnv`, repo-provider variables by
`SymphonyElixir.RepoProvider.RuntimeEnv`, and CNB-specific variables by
`SymphonyElixir.RepoProvider.CNB.RuntimeEnv`.

For provider-specific runtime requirements, see
[`agent_providers/`](./agent_providers/).

## Workflow Files

A workflow file has YAML front matter for runtime configuration and a Markdown
body used as the agent-provider prompt.

When no path or `--template` is provided, `./bin/symphony` loads
[`../WORKFLOW.md`](../WORKFLOW.md). If `WORKFLOW.md` is missing or has invalid
YAML at startup, Maestro does not boot. If a later reload fails, Maestro keeps
running with the last known good workflow and logs the reload error until the
file is fixed.

Important workflow fields:

- `tracker.kind`: tracker adapter, such as `linear`, `tapd`, or `memory`
- `tracker.auth`: tracker credential fields, usually supplied from environment
  variables
- `tracker.lifecycle.active_states`: raw tracker states that are dispatchable
- `tracker.lifecycle.terminal_states`: raw tracker states that stop active work
- `tracker.lifecycle.state_phase_map`: raw tracker state to shared lifecycle
  phase mapping
- `workspace.root`: root directory for issue workspaces
- `repo.path`: target repository path inside an issue workspace, usually
  `repo`
- `repo.provider.kind`: repo provider, currently `github`, `cnb`, or `memory`
- `agent.execution.max_concurrent_agents`: concurrent session cap
- `agent.execution.max_turns`: continuation cap for one active issue
- `agent_provider.kind`: agent provider, such as `codex`, `claude_code`,
  `opencode`, or `mock`
- `agent_provider.options`: provider-native options

Agent provider kind strings and supported aliases are owned by
`SymphonyElixir.AgentProvider.Kinds`. The registry, config resolver, provider
metadata, and managed-credential code should use that owner instead of
duplicating provider-kind literals.

Tracker kind strings are owned by `SymphonyElixir.Tracker.Kinds`.
Repo-provider kind strings and labels are owned by
`SymphonyElixir.RepoProvider.Kinds`, while the default repo provider is owned by
`SymphonyElixir.RepoProvider.Defaults`. Operator docs, workflow templates, and
runtime validation should use those owners as the implementation source of
truth.

Environment-backed fields can be supplied as `$VAR`, for example:

- Linear: `tracker.auth.api_key: $LINEAR_API_KEY`
- TAPD: `tracker.auth.api_key: $TAPD_API_USER`
- TAPD: `tracker.auth.api_secret: $TAPD_API_PASSWORD`

For path values, `~` is expanded to the home directory. For env-backed path
values, `$VAR` is resolved before path handling. Command strings such as
`agent_provider.options.command` keep shell expansion in the launched process.

## Templates

Bundled workflow templates live under
[`../priv/workflow_templates/`](../priv/workflow_templates/) and are selected
with `--template <alias>`. Alias format is:

```text
<tracker>/<source>/<agent-provider>[.<variant>]
```

Template aliases and safety notes are documented in
[`../priv/workflow_templates/README.md`](../priv/workflow_templates/README.md).

Templates that set `approval_policy: never`, `danger-full-access`, or
`bypassPermissions` are trusted-environment templates. Use them only where
unattended tracker writes, repository writes, PR operations, and provider
credentials are intentionally allowed.

## Tracker Lifecycle

The prompt always receives a normalized `issue` object, regardless of tracker
kind. In Elixir code this maps to `SymphonyElixir.Issue`.

Raw tracker states remain in `Issue.state`. Configure lifecycle maps so Maestro
can derive tracker-neutral phases for blocker gating, retry, dispatch, and
cleanup decisions.

TAPD status configuration has three layers:

- `Issue.state`: the raw TAPD status returned by the API
- `tracker.lifecycle.raw_state_by_route_key`: fixed Maestro route keys such as
  `review` mapped to raw TAPD statuses
- `tracker.lifecycle.state_phase_map`: raw TAPD statuses mapped to shared
  lifecycle phases such as `human_review`

`review` and `human_review` are intentionally not the same string. `review` is
the route key, while `human_review` is the lifecycle phase that the configured
review status must resolve to. Example:

```text
review -> status_5 -> human_review
```

For TAPD profiles that follow the bundled route-state example:

- leave `tracker.provider.platform.workitem_type_id` unset unless the target
  workspace needs explicit narrowing
- keep the human discussion state out of `tracker.lifecycle.active_states`
- map the dispatchable planning route to a raw queued status such as
  `status_4`
- map the implementation route to the raw in-progress status such as
  `developing`
- map the review route to a raw handoff status such as `status_5`
- replace all example raw values with the exact TAPD API statuses from the
  target workspace

Maestro performs configured TAPD pre-dispatch route transitions in the backend.
For example, when a story enters the `planning` route and the route policy is
`transition_then_dispatch`, the orchestrator moves it to the configured
`developing` raw status before starting the agent.

## TAPD Workitem Type Scope

TAPD workitem type scope has three modes:

- Omit `tracker.provider.platform.workitem_type_id`,
  `tracker.provider.platform.workitem_type_ids`, and
  `tracker.lifecycle.workflows_by_type` for workspace-wide auto-discovery.
  Maestro scans by `tracker.provider.platform.workspace_id + status`,
  discovers observed `workitem_type_id` values from the current active result
  set, and validates matching workflow states only for those discovered types.
- Use `tracker.provider.platform.workitem_type_id` for one strict narrowing
  override when one workspace contains multiple mismatched Story subtypes.
- Use `tracker.provider.platform.workitem_type_ids` for an explicit
  shared-workflow whitelist when multiple Story subtypes are intended to share
  one raw TAPD workflow. Maestro still validates every configured type in that
  whitelist on each poll.

Use `tracker.lifecycle.workflows_by_type` only when one TAPD workspace contains
heterogeneous Story subtype workflows. Do not combine it with
`tracker.provider.platform.workitem_type_id` or
`tracker.provider.platform.workitem_type_ids`.

## Workspace Automation

Maestro copies its bundled provider-neutral workspace automation pack from
[`../priv/workspace_automation/`](../priv/workspace_automation/) into each newly
created issue workspace root before `hooks.after_create` runs. The active agent
provider chooses the target discovery directory. For example, Codex uses
`<workspace>/.codex`.

The copied automation directory is exposed to hooks and agent sessions as
`SYMPHONY_WORKSPACE_AUTOMATION_DIR`.

Bundled skills are grouped under:

- `skills/core/`: `commit`, `pull`, and `debug`
- `skills/repo/`: `push` and `land`
- `skills/tracker/`: `linear` and `tapd`

The bundled pack is separate from the repository-root `.codex/` used for
developing Maestro itself. It is also separate from any `repo/.codex` or
`repo/.agents` content in the target repository.

Set `workspace.bootstrap_automation_from` only when you want to override the
bundled skill pack with a different local workspace automation directory.

## Workspace Hooks

Use `hooks.after_create` to bootstrap a fresh workspace. For Git-backed
workflows, prefer cloning the target repository into `repo/` so the outer issue
workspace can hold Maestro-only automation config without colliding with
repo-local automation config.

The bundled templates keep `hooks.after_create` and `hooks.before_remove` as
explicit extension points. By default they clone the target repo and leave
comment-only placeholders for repo-specific bootstrap or cleanup logic.

If a hook needs `mise exec` inside a freshly cloned workspace, trust the repo
config and fetch project dependencies in `hooks.after_create` before invoking
`mise` later from other hooks.

## SSH Workers

SSH worker workflows are enabled per workflow by configuring
`worker.ssh_hosts`. If `worker.ssh_hosts` is absent, Maestro stays in local-only
mode for that workflow.

Supported `worker.ssh_hosts` forms:

- `host`
- `user@host`
- `host:port`
- `user@host:port`
- `[ipv6-literal]`
- `user@[ipv6-literal]`
- `[ipv6-literal]:port`
- `user@[ipv6-literal]:port`

Use bracketed IPv6 notation in workflow config. Unbracketed forms such as
`::1:2200` are rejected as ambiguous.

`worker.max_concurrent_agents_per_host` is optional, but when set it requires
valid `worker.ssh_hosts`.

SSH worker execution is intentionally non-interactive. Configure SSH auth,
host-key verification posture, and any aliasing through `SYMPHONY_SSH_CONFIG`
or your ambient OpenSSH config rather than relying on prompts during runtime.

Remote cleanup uses the recorded `worker_host` plus the recorded canonical
`workspace_path` when available, so a later `workspace.root` change does not
redirect deletion to a different path.

SSH worker execution is implemented by `SymphonyElixir.Platform.SSH`,
`SymphonyElixir.Agent.Runtime.WorkerDaemon`, and the worker-daemon CLI.
Production-readiness claims for SSH workers should only be made after running
representative live validation against the target host class.

## Dashboard And APIs

`server.port` or CLI `--port` enables the optional Phoenix LiveView dashboard
and JSON API:

- `/`: dashboard
- `/issues/:issue_identifier`: issue detail page
- `/api/v1/state`: JSON state snapshot
- `/api/v1/<issue_identifier>`: issue JSON detail
- `/api/v1/refresh`: refresh endpoint

The dashboard projects orchestrator snapshot state, recent structured runtime
events, and issue/session history from the shared in-memory event store.

When using shell commands to summarize `/api/v1/state`, gate JSON parsing on a
successful HTTP response. A failed local monitor command should be diagnosed
separately from the resident service:

```bash
state_json=$(mktemp)
if curl -fsS --max-time 3 http://127.0.0.1:4000/api/v1/state -o "$state_json"; then
  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(sorted(data.keys()))' "$state_json"
else
  echo "state_api_unavailable"
fi
rm -f "$state_json"
```

Current logging, event-store, redaction, dashboard, and terminal status behavior
is documented in [`logging.md`](./logging.md).

## Long-Running Service Verification

The main `./bin/symphony` service is a resident process. An empty queue is not a
terminal condition: the orchestrator should continue polling, and
`candidate_count=0` should be followed by later `poll_cycle_started` events.

For local verification, prefer a foreground run:

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  path/to/WORKFLOW.md \
  --port 4000
```

Keep the process attached long enough to observe at least two or three poll
cycles. A healthy empty-queue service keeps the configured dashboard/API port
listening and continues to emit `poll_cycle_completed status=ok` in
`log/symphony.log*`.

Do not use a background process launched from a transient automation shell as
proof of daemon behavior. In particular, `nohup ./bin/symphony ... &` inside an
agent/tool execution shell may be cleaned up when that shell returns. If that
happens without `service_stopped`, child crash logs, or missing poll cycles
while the parent shell is still alive, treat it as a launch-method artifact
before investigating Supervisor or child lifecycle code.

When true daemon behavior needs validation, run the service under a real
supervisor such as launchd, systemd, Docker/release runner, tmux, or screen.
Always stop verification runs explicitly and confirm the configured port is
released before starting another run.

## Repo Provider And Testing

Repository provider operation details live in
[`repo_provider.md`](./repo_provider.md). Local and live validation details live
in [`testing.md`](./testing.md).

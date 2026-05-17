# Maestro Elixir Runtime

This directory contains the Elixir/OTP runtime implementation of Maestro
Control Plane (Maestro): a tracker-driven orchestrator for running AI agent
providers against isolated workspaces, real repositories, workflow policies,
and observable tracker state transitions.

The implementation still uses compatibility identifiers inherited from the
original Symphony codebase, including `SymphonyElixir` module names, the
`symphony` CLI/escript, `.symphony` runtime directories, and `SYMPHONY_*`
environment variables. Keep those literal names when configuring or invoking
concrete runtime surfaces.

> [!WARNING]
> Maestro's Elixir runtime is early-stage software intended for trusted
> evaluation and pilot deployments. Harden deployments against your own
> operational, security, and compliance requirements before production use.

## Screenshot

![Maestro Elixir runtime screenshot](../.github/media/elixir-screenshot.png)

## What It Does

Maestro turns tracker work items into supervised agent sessions:

1. Polls the configured tracker for candidate work
2. Creates an isolated workspace for each claimed issue or story
3. Copies workspace automation and runs configured bootstrap hooks
4. Starts the configured agent provider in the workspace
5. Exposes workflow-planned Dynamic Tools to the provider
6. Reconciles tracker state, workspace lifecycle, logs, and evidence

The default agent provider is `codex`, implemented with Codex
[App Server mode](https://developers.openai.com/codex/app-server/). Provider
selection lives under `agent_provider.kind`; provider-specific options live
under `agent_provider.options`. See
[`docs/agent_providers/`](./docs/agent_providers/) for provider-specific
runtime notes.

Linear-backed bundled workflows expose typed tracker tools such as
`linear_issue_snapshot`, `linear_move_issue`, and `linear_upsert_workpad`.
TAPD-backed bundled workflows expose typed tools such as `tapd_issue_snapshot`,
`tapd_move_issue`, and `tapd_upsert_workpad`. Raw Linear GraphQL and raw TAPD
REST passthrough are not part of the normal agent-facing workflow surface.

If a claimed issue or story moves to a configured terminal state, Maestro stops
the active agent for that item and cleans up matching workspaces.

## Quick Start

Use [mise](https://mise.jdx.dev/) to install the Elixir/Erlang versions pinned
by this repository:

```bash
git clone <maestro-repository-url> maestro
cd maestro/elixir
mise trust
mise install
mise exec -- mix setup
mise exec -- mix build
```

Start the local memory/mock workflow. This path does not require Linear, TAPD,
GitHub, CNB, Codex, Claude Code, OpenCode, or external credentials:

```bash
mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

Open the optional dashboard at `http://localhost:4000`.

The memory/mock template overrides the tracker, repo provider, and agent
provider for local validation. Real tracker/repository workflows should use one
of the repo-backed templates or a custom workflow file.

Running `./bin/symphony` without a workflow path or `--template` loads
`./WORKFLOW.md`. Pass a workflow file path to run a custom workflow:

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  /path/to/custom/WORKFLOW.md
```

The acknowledgement flag is required because the reference templates can run
with broad filesystem, repository, tracker, and provider permissions.

## Workflow Templates

Bundled templates live under
[`priv/workflow_templates/`](./priv/workflow_templates/) and are selected with
`--template <alias>`. Alias format is:

```text
<tracker>/<source>/<agent-provider>[.<variant>]
```

Template aliases are documented in
[`priv/workflow_templates/README.md`](./priv/workflow_templates/README.md).
Example:

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template linear/github/codex
```

Common aliases include `memory/no_repo/mock`, `linear/github/codex`,
`tapd/github/codex`, and `tapd/cnb/opencode`.

Templates that set `approval_policy: never`, `danger-full-access`, or
`bypassPermissions` are trusted-environment templates. Use them only where
unattended tracker writes, repository writes, PR operations, and provider
credentials are intentionally allowed.

## External Systems

Configure the tracker, repository, and provider credentials required by the
template you select.

Tracker credentials:

- Linear: set `LINEAR_API_KEY`; bundled Linear templates also require
  `LINEAR_PROJECT_SLUG`.
- TAPD: set `TAPD_API_USER`, `TAPD_API_PASSWORD`, and `TAPD_WORKSPACE_ID`.

Agent provider credentials and local setup depend on the selected provider. See
[`docs/agent_providers/`](./docs/agent_providers/) before running Codex,
Claude Code, or OpenCode backed templates.

Repository inputs for repo-backed templates:

```bash
export SOURCE_REPO_URL=https://github.com/example-user/sample-repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=example-user/sample-repo
```

Treat `example-user/sample-repo` as a placeholder and replace it with the
target repository. `SOURCE_REPO_PROVIDER_REQUIRED_PR_LABEL` is optional and only
applies to GitHub label enforcement.

Set `SYMPHONY_WORKSPACE_ROOT` before production or full-flow validation so issue
workspaces are isolated from local developer paths and easy to clean up.

## Configuration

Workflow files use YAML front matter for runtime configuration plus a Markdown
body used as the agent-provider prompt.

Minimal Linear shape for a custom workflow:

```md
---
tracker:
  kind: linear
  auth:
    api_key: $LINEAR_API_KEY
  provider:
    project_slug: $LINEAR_PROJECT_SLUG
  lifecycle:
    active_states: [Todo, In Progress]
    terminal_states: [Done, Closed]
    state_phase_map:
      Todo: todo
      In Progress: in_progress
      Done: done
      Closed: canceled
workspace:
  root: $SYMPHONY_WORKSPACE_ROOT
repo:
  path: repo
  base_branch: $SOURCE_REPO_BASE_BRANCH
  remote:
    name: origin
    url: $SOURCE_REPO_URL
  provider:
    kind: github
    repository: $SOURCE_REPO_PROVIDER_REPOSITORY
hooks:
  after_create: |
    if [ -z "${SOURCE_REPO_URL:-}" ]; then
      echo "SOURCE_REPO_URL is required" >&2
      exit 1
    fi
    if [ -n "${SOURCE_REPO_BASE_BRANCH:-}" ]; then
      "${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" clone \
        "$SOURCE_REPO_URL" repo --depth 1 --branch "$SOURCE_REPO_BASE_BRANCH"
    else
      "${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" clone "$SOURCE_REPO_URL" repo --depth 1
    fi
agent_provider:
  kind: codex
  options:
    command: codex app-server
---

You are working on issue {{ issue.identifier }}.
```

Important configuration notes:

- The prompt always receives a normalized `issue` object. In code this maps to
  `SymphonyElixir.Issue`.
- Raw tracker states remain in `Issue.state`; lifecycle maps derive
  tracker-neutral phases for orchestration decisions.
- TAPD workflows can use `tracker.lifecycle.raw_state_by_route_key` to map
  Maestro route keys such as `review` to raw TAPD API statuses such as
  `status_5`.
- `tracker.kind` built-ins are `linear`, `tapd`, and `memory`; canonical
  tracker kind strings are owned by `SymphonyElixir.Tracker.Kinds`.
- `repo.provider.kind` defaults to `github`; bundled repo-provider kinds are
  `github`, `cnb`, and local/test `memory`. Canonical repo-provider kind
  strings and labels are owned by `SymphonyElixir.RepoProvider.Kinds`, while
  defaults are owned by `SymphonyElixir.RepoProvider.Defaults`.
- `agent_provider.kind` defaults to `codex`. Canonical agent provider kind
  strings and supported aliases are owned by `SymphonyElixir.AgentProvider.Kinds`.
- `workspace.bootstrap_automation_from` is optional and overrides the bundled
  workspace automation source when you need a custom skill pack.
- `server.port` or CLI `--port` enables the Phoenix LiveView dashboard and JSON
  API at `/`, `/api/v1/state`, `/api/v1/<issue_identifier>`, and
  `/api/v1/refresh`.

See [`docs/operations.md`](./docs/operations.md) for the detailed workflow,
workspace, TAPD, SSH worker, and dashboard runbook.

## Workspace Automation

Maestro copies its provider-neutral workspace automation pack from
[`priv/workspace_automation/`](./priv/workspace_automation/) into each newly
created issue workspace before `hooks.after_create` runs. The active agent
provider chooses the discovery directory; for example Codex uses
`<workspace>/.codex`.

The bundled pack is separate from the repository-root `.codex/` used for
developing Maestro itself. Repo-local automation in the target repository also
stays isolated when templates clone the target repository into `repo/`.

Core skills live under:

- `skills/core/`: `commit`, `pull`, and `debug`
- `skills/repo/`: `push` and `land`
- `skills/tracker/`: `linear` and `tapd`

## Repo Provider

The workspace `repo` and `repo-provider` helpers route repository and PR
operations through the `symphony` escript. They provide provider-neutral
surfaces for GitHub and CNB-backed workflows, including branch facts, commit
helpers, PR creation/update, review inspection, checks, merge/land watching,
and smoke validation.

See [`docs/repo_provider.md`](./docs/repo_provider.md) for prerequisites,
environment variables, supported commands, GitHub/CNB behavior, and smoke
workflows.

## Tracker Smoke

Use `mix tracker.smoke` for deployment-scoped tracker validation. It is
read-only by default and validates workflow tracker config, tracker
connectivity, and optional targeted issue refresh:

```bash
mix tracker.smoke --template memory/no_repo/mock --issue local-memory-1 --json
```

State-write validation requires `--confirm-state-write` and sends
`expected_current_state` to the tracker adapter. Run it only against disposable
or explicitly approved tracker issues.

## Observability

The optional dashboard uses Phoenix LiveView and Bandit:

- Dashboard at `/`
- Issue detail pages at `/issues/:issue_identifier`
- JSON API under `/api/v1/*`
- Structured file logs under `./log/symphony.log` by default

Detailed logging, event-store, redaction, dashboard, and terminal status behavior
is documented in [`docs/logging.md`](./docs/logging.md).

## Project Layout

- `lib/symphony_elixir.ex`: library entrypoint that starts the orchestrator in
  the current BEAM node
- `lib/symphony_elixir/application.ex`: OTP application entrypoint
- `lib/symphony_elixir/cli.ex`: escript CLI entrypoint used by `bin/symphony`
- `lib/symphony_elixir/`: OTP runtime modules and domain namespaces
- `lib/symphony_worker_daemon/`: worker-daemon server implementation namespace
- `lib/symphony_elixir_web/`: Phoenix endpoint, controllers, presenters, and
  LiveView surfaces
- `lib/mix/tasks/`: repository-specific quality and workflow Mix tasks
- `test/`: ExUnit coverage for runtime behavior
- `docs/architecture.md`: module placement and refactor conventions
- `docs/logging.md`: logging and observability implementation guide
- `docs/agent_providers/`: provider-specific runtime, protocol, and accounting
  guides
- `priv/workflow_templates/`: bundled workflow templates
- `priv/workspace_automation/`: bundled workspace automation pack

Detailed module ownership rules live in
[`docs/architecture.md`](./docs/architecture.md).

## Testing

Run the standard local quality gate:

```bash
make all
```

Before publishing or opening a PR, run the shared secret scan:

```bash
make secret-scan
```

Live external tests create disposable tracker resources and may launch real
agent sessions. Use them only when the required credentials and write
permissions are intentionally available.

See [`docs/testing.md`](./docs/testing.md) for the full test matrix, live E2E
requirements, local SSH helper usage, and TAPD/GitHub destructive smoke notes.

## FAQ

### Why Elixir?

Elixir runs on Erlang/BEAM/OTP, which is well suited to supervising
long-running processes. It also supports hot code reloading without stopping
actively running subagents, which is useful during development.

### Where should I start for my own codebase?

Start with `--template memory/no_repo/mock` to verify the local runtime. Then
pick the closest repo-backed template, configure tracker and repository
credentials, set `SYMPHONY_WORKSPACE_ROOT`, and adapt the workflow prompt and
state mappings for your tracker.

## License

Maestro is licensed under the [GNU Affero General Public License version 3 (AGPL-3.0-only)](../LICENSE). Portions derived from OpenAI Symphony retain their Apache-2.0 attribution and notice requirements; see [`../NOTICE`](../NOTICE), [`../LICENSES/Apache-2.0.txt`](../LICENSES/Apache-2.0.txt), [`../MODIFICATIONS.md`](../MODIFICATIONS.md), [`../SOURCE.md`](../SOURCE.md), and [`../THIRD_PARTY_LICENSES.md`](../THIRD_PARTY_LICENSES.md).

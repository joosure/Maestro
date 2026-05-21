# Maestro Elixir Runtime Guide

This directory contains the Elixir/OTP runtime implementation that actually runs Maestro.

The root README explains the project value. This guide explains how to start the runtime, try the local demo, connect real systems, and find the operational documents.

## What it does

Maestro turns a task from a project system into a traceable AI agent run:

```text
Read or sync a task from TAPD / Linear / Memory
  -> Create an isolated workspace inside Maestro's own runtime environment
  -> Prepare the target Git repository inside that workspace
  -> Start Codex / Claude Code / OpenCode / Mock
  -> Let the agent analyze, modify, or produce suggestions from the repository copy
  -> Record logs, tool calls, diffs, summaries, and links
  -> Write the result back to the project system
```

The isolated workspace is not created inside TAPD or GitHub. It is created on the local machine, SSH host, or worker environment where Maestro runs. It gives each task its own directory, repository copy, logs, and temporary files, which makes parallel execution, isolation, cleanup, and review easier.

Maestro does not replace any coding agent. It helps teams schedule and manage agents from real project tasks.

## Naming note

The public project name is **Maestro**.

The current runtime still uses compatibility names inherited from Symphony:

- `SymphonyElixir` module names
- `./bin/symphony` CLI entrypoint
- `.symphony` runtime directories
- `SYMPHONY_*` environment variables

Use those names when running the current code. They are compatibility names, not a separate product.

## Status

Maestro is early-stage software for trusted evaluation, experiments, and pilot deployments.

Start locally or in a test environment. Before connecting real project systems, real repositories, or unattended write access, review credentials, repository permissions, security boundaries, and compliance requirements.

## Quick start: local demo

This is the safest way to try Maestro. It does not require Linear, TAPD, GitHub, CNB, Codex, Claude Code, OpenCode, or external credentials.

```bash
git clone https://github.com/joosure/Maestro.git
cd Maestro/elixir

mise trust
mise install
mise exec -- mix setup
mise exec -- mix build

mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

Open:

```text
http://localhost:4000
```

This starts a local flow using:

- a local simulated task source;
- a local simulated code platform;
- a mock agent;
- the dashboard/API on port `4000`.

## Choose a template

A workflow template is a “run recipe.” It decides:

```text
where the task comes from / where the Git repository or code platform is / which agent runs
```

| Template | Meaning | Best for |
| --- | --- | --- |
| `memory/no_repo/mock` | Local simulated task + no real repository + mock agent | First safe demo |
| `linear/github/codex` | Linear + GitHub + Codex | Codex on Linear/GitHub tasks |
| `linear/github/claude_code` | Linear + GitHub + Claude Code | Claude Code on Linear/GitHub tasks |
| `tapd/github/codex` | TAPD + GitHub + Codex | TAPD task + GitHub repository |
| `tapd/cnb/opencode` | TAPD + CNB + OpenCode | TAPD/CNB flow |
| `tapd/cnb/claude_code` | TAPD + CNB + Claude Code | TAPD/CNB flow |

See [Workflow templates](./priv/workflow_templates/README.md) for details.

## Connect real systems

Only configure the credentials required by the template you choose.

TAPD:

```bash
export TAPD_API_USER=...
export TAPD_API_PASSWORD=...
export TAPD_WORKSPACE_ID=...
```

Linear:

```bash
export LINEAR_API_KEY=...
export LINEAR_PROJECT_SLUG=...
```

Repository inputs:

```bash
export SOURCE_REPO_URL=https://github.com/example-user/sample-repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=example-user/sample-repo
```

Before connecting real systems, set an explicit isolated workspace root:

```bash
export SYMPHONY_WORKSPACE_ROOT=/path/to/isolated/maestro-workspaces
```

## Start a real template

Example: TAPD + GitHub + Codex:

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template tapd/github/codex \
  --port 4000
```

Example: Linear + GitHub + Codex:

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template linear/github/codex \
  --port 4000
```

Real templates may update project systems, create branches, push commits, or open PRs. Run them only in trusted test environments or explicitly approved production environments.

## Workflow file overview

A workflow file has two parts:

1. YAML front matter: config for the project system, repository, agent, workspace, and limits.
2. Markdown body: the prompt given to the agent.

Example shape:

```yaml
---
tracker:
  kind: tapd
workspace:
  root: $SYMPHONY_WORKSPACE_ROOT
repo:
  provider:
    kind: github
agent_provider:
  kind: codex
---

You are working on {{ issue.identifier }}.
```

Start from bundled templates before writing custom workflows.

## Dashboard and API

Use `--port` to enable the dashboard/API.

| Path | Purpose |
| --- | --- |
| `/` | Dashboard |
| `/issues/:issue_identifier` | Task detail page |
| `/api/v1/state` | Runtime state JSON |
| `/api/v1/<issue_identifier>` | Task detail JSON |
| `/api/v1/refresh` | Refresh endpoint |

Structured logs default to `./log/symphony.log`.

## Testing

Standard local quality gate:

```bash
make all
```

Secret scan before publishing:

```bash
make secret-scan
```

Tracker smoke example:

```bash
mix tracker.smoke --template memory/no_repo/mock --issue local-memory-1 --json
```

Live tests and destructive smoke tests may create real tasks, run real agents, push branches, or create PRs. Use them only in disposable or explicitly approved environments.

## Continue reading

- [Workflow templates](./priv/workflow_templates/README.md): choose a run recipe.
- [Operations guide](./docs/operations.md): run safely in real environments.
- [Logging guide](./docs/logging.md): logs, events, redaction, and dashboard.
- [Repo provider guide](./docs/repo_provider.md): GitHub/CNB repository and PR operations.
- [Testing guide](./docs/testing.md): local, live, smoke, and destructive validation.
- [Agent provider docs](./docs/agent_providers/): provider notes for Codex, Claude Code, and OpenCode.

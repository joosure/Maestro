# Operations Guide

This guide is for people who want to run Maestro beyond the local demo.

Core principle:

```text
try locally -> connect one real system -> observe results -> increase permissions gradually
```

Maestro can let AI agents work on real project tasks and real Git repositories. The more powerful the setup, the more carefully you should handle credentials, repository writes, project-system updates, and logs.

## Runtime modes

| Mode | Uses | Best for |
| --- | --- | --- |
| Local demo | local simulated tasks + mock agent | first experience and learning |
| Trusted evaluation | test project/test repository + real agent | workflow validation |
| Team pilot | real project workflow + human review | small team rollout |
| Production operation | credentials, monitoring, approval, and cleanup policies | long-running use |

Do not jump from local demo to unrestricted production operation.

## Questions to answer before running

1. Does the task come from TAPD, Linear, or local simulated data?
2. Where is the target Git repository? GitHub, CNB, or a local simulated code platform?
3. Which agent is used: Codex, Claude Code, OpenCode, or mock?
4. Can the agent modify the repository or push branches?
5. Can the agent update project-system states, comments, or links?
6. Where is the isolated workspace created?
7. Who reviews the result?
8. How do you stop, clean up, and inspect a run?

When in doubt, start with `memory/no_repo/mock`.

## Runtime prerequisites

Use `mise` to install pinned Erlang/Elixir versions:

```bash
cd elixir
mise trust
mise install
mise exec -- elixir --version
```

Common host tools:

- `bash`
- `git`
- `gh`, for GitHub PR workflows
- the selected agent CLI, such as Codex, Claude Code, or OpenCode
- `./bin/symphony` or `SYMPHONY_CLI`

Provider details live under:

```text
elixir/docs/agent_providers/
```

## Compatibility names

The public project name is **Maestro**.

The current runtime still uses compatibility names:

- `symphony` CLI
- `SymphonyElixir` module names
- `.symphony` directories
- `SYMPHONY_*` environment variables

Use those names in concrete runtime configuration.

## Credentials

Only provide the credentials required by the selected template.

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

GitHub:

```bash
gh auth status
export SOURCE_REPO_PROVIDER_REPOSITORY=owner/repo
```

CNB:

```bash
export CNB_TOKEN=...
```

Repository inputs:

```bash
export SOURCE_REPO_URL=https://github.com/owner/repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=owner/repo
```

Use least-privilege credentials when possible. Avoid using high-privilege personal tokens for long-running unattended operation.

## Workspaces

Each task should have its own workspace.

Before connecting real systems, set:

```bash
export SYMPHONY_WORKSPACE_ROOT=/path/to/isolated/maestro-workspaces
```

The workspace is created inside Maestro's runtime environment: local machine, SSH host, or worker environment. It is not created inside TAPD, Linear, GitHub, or CNB.

Good workspace practices:

- use a dedicated directory;
- do not place it inside important local projects;
- give each task its own directory and repository copy;
- make it easy to inspect;
- make it easy to delete;
- do not mix it with unrelated automation.

Why isolated workspaces matter:

- multiple tasks can run in parallel;
- code copies, logs, and temporary files do not leak across tasks;
- failed runs can be inspected and cleaned up separately;
- reviewers can reconstruct what happened in one agent run.

## Safe rollout path

### Step 1: local demo

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

Goal: confirm that the runtime, dashboard, and local task flow work.

### Step 2: low-risk validation

Use smoke tests or disposable tasks first.

```bash
mix tracker.smoke --template memory/no_repo/mock --issue local-memory-1 --json
```

Goal: validate configuration without affecting real users.

### Step 3: real project system + disposable repository

Use a test project, test repository, or explicitly approved sandbox.

Goal: validate real end-to-end integration behavior.

### Step 4: team pilot

Limit task scope, reviewers, credential permissions, and concurrency.

Goal: learn failure modes and improve templates and prompts.

### Step 5: production hardening

Add approvals, monitoring, credential rotation, cleanup policies, and incident handling.

## Dashboard and API

Use `--port` or `server.port` to enable the dashboard/API.

| Path | Purpose |
| --- | --- |
| `/` | Dashboard |
| `/issues/:issue_identifier` | Task detail page |
| `/api/v1/state` | Runtime state JSON |
| `/api/v1/<issue_identifier>` | Task detail JSON |
| `/api/v1/refresh` | Refresh endpoint |

The dashboard helps inspect:

- which tasks are running;
- which agent is used;
- recent events;
- workspace and session state;
- final results.

## Logs and delivery records

A run should answer:

- Why did Maestro start this task?
- Which project system did the task come from?
- Which Git repository and branch were used?
- Which template and agent were used?
- What changed in the repository?
- Which tools did the agent call?
- Was a branch or PR created?
- Where did it fail?
- What should a human review next?

Detailed logging and redaction behavior lives in:

```text
elixir/docs/logging.md
```

## Repository operations

Repo-backed workflows may clone repositories, create branches, push commits, open PRs, check statuses, or watch merge state.

Before enabling repository writes, confirm:

- a disposable repository was tested first;
- base branch and branch naming are correct;
- repository permissions are appropriate;
- PRs or important changes require human review;
- early runs do not bypass tests, review, or release judgment.

More details:

```text
elixir/docs/repo_provider.md
```

## Tracker lifecycle

Maestro needs to know which task states can run and which states should stop.

| Concept | Meaning |
| --- | --- |
| Active state | Maestro may pick up this task |
| Terminal state | Maestro should stop or clean up this task |
| Route state | Workflow next step, such as planning or review |
| Human review state | A human should inspect the result |

TAPD raw API states may differ from the workflow names people see. Configure mappings carefully and test them on disposable tasks first.

## SSH and worker execution

Some workflows can run agents on an SSH host or worker service instead of the local machine.

Enable this only after the local and single-machine paths are stable.

Before enabling remote workers, confirm:

- SSH can authenticate without interactive prompts;
- host-key policy is clear;
- workspace roots are isolated;
- cleanup has been tested;
- concurrency limits are set;
- operators can see logs and errors.

## Stop and cleanup checklist

Before running real tasks, know how to:

- stop the Maestro process;
- find the workspace for a task;
- inspect logs and dashboard state;
- remove or revert test branches;
- clean temporary workspaces;
- undo test states or comments in the project system.

## Related docs

- [Elixir runtime guide](../README.md)
- [Workflow templates](../priv/workflow_templates/README.md)
- [Logging guide](./logging.md)
- [Repo provider guide](./repo_provider.md)
- [Testing guide](./testing.md)

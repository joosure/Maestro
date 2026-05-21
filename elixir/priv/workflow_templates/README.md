# Workflow Templates

A workflow template is Maestro's “run recipe.”

A template answers three questions:

```text
Where does the task come from?
Where is the code or code platform?
Which AI agent runs?
```

For example, `tapd/github/codex` means:

```text
TAPD task -> GitHub repository -> Codex Agent
```

For example, `linear/github/codex` means:

```text
Linear task -> GitHub repository -> Codex Agent
```

## Start here

For the first run, use:

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

This template requires no external accounts or credentials. It is the safest way to understand Maestro's basic flow.

## Naming rule

Template aliases use this format:

```text
<tracker>/<source>/<agent-provider>[.<variant>]
```

| Segment | Meaning | Examples |
| --- | --- | --- |
| `tracker` | project system or local simulated task source | `linear`, `tapd`, `memory` |
| `source` | repository or code platform source; use `no_repo` when there is no real repository | `github`, `cnb`, `no_repo` |
| `agent-provider` | AI agent or local mock | `codex`, `claude_code`, `opencode`, `mock` |
| `variant` | optional special version | `canary` |

## Current templates

| Template | What it does | Best for |
| --- | --- | --- |
| `memory/no_repo/mock` | local simulated task + no real repository + mock agent | first safe demo |
| `linear/github/codex` | Linear + GitHub + Codex | Linear task to GitHub PR |
| `linear/github/claude_code` | Linear + GitHub + Claude Code | Linear/GitHub flow |
| `linear/github/opencode.canary` | Linear + GitHub + OpenCode canary | OpenCode experiments |
| `tapd/github/codex` | TAPD + GitHub + Codex | TAPD task to GitHub PR |
| `tapd/cnb/opencode` | TAPD + CNB + OpenCode | TAPD/CNB flow |
| `tapd/cnb/claude_code` | TAPD + CNB + Claude Code | TAPD/CNB flow |

These templates connect external systems. They do not mean that Linear, TAPD, GitHub, CNB, or agents are embedded inside Maestro.

## Which template should I choose?

| Goal | Recommended template |
| --- | --- |
| Understand Maestro without credentials | `memory/no_repo/mock` |
| Run Codex on TAPD + GitHub tasks | `tapd/github/codex` |
| Run OpenCode on TAPD + CNB tasks | `tapd/cnb/opencode` |
| Run Codex on Linear + GitHub tasks | `linear/github/codex` |
| Run Claude Code on Linear + GitHub tasks | `linear/github/claude_code` |
| Add a new integration | Copy and adapt the closest template |

## Notes for real templates

Real templates may:

- read tasks from TAPD or Linear;
- clone or check out the target Git repository;
- create branches;
- push commits;
- create or update PRs;
- write comments, states, or links back to the project system;
- run a real coding agent.

Before running real templates, confirm:

- the target project system is allowed to be updated;
- the target repository is a test repository or explicitly approved;
- credentials use the smallest practical permission set;
- `SYMPHONY_WORKSPACE_ROOT` points to an isolated directory;
- someone knows how to inspect, stop, and clean up the run;
- important changes still require human review.

## Create your own template

Create a Markdown file in this directory using the same three-segment shape:

```text
<tracker>/<source>/<agent-provider>[.<variant>].md
```

A template has:

1. YAML front matter: runtime configuration.
2. Markdown body: the agent prompt.

Simplified example:

```md
---
tracker:
  kind: memory
repo:
  provider:
    kind: memory
agent_provider:
  kind: mock
---

You are working on {{ issue.identifier }}.
Summarize the task and produce a safe local result.
```

## Template author checklist

Before adding a template, answer:

- Which project system does the task come from?
- Does it need a real Git repository?
- Which agent runs?
- Which credentials are required?
- Will it write to the project system, repository, or PR?
- Is it for local demo, trusted evaluation, team pilot, or production operation?
- What should the agent produce?
- How should the task be updated after completion?
- How should failed runs clean up workspaces and test data?

## Related docs

- [Elixir runtime guide](../../README.md)
- [Operations guide](../../docs/operations.md)
- [Agent provider docs](../../docs/agent_providers/)

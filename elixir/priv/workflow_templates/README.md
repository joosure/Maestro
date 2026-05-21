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

The three segments in the alias correspond to the top-level config in the front
matter:

- `tracker`: the issue/story system that drives orchestration, such as `linear`
  or `tapd`.
- `source`: the workflow's external work source. Use repo provider names such as
  `github` or `cnb` for workflows that clone, push, open PRs, or merge code. Use
  `no_repo` for workflows that do not perform repo clone, push, PR, or merge
  operations.
- `agent-provider`: the canonical agent runtime/provider kind, such as `codex`,
  `opencode`, `claude_code`, `codebuddy_code`, or `mock`. The Elixir runtime owns
  these strings and supported aliases in `SymphonyElixir.AgentProvider.Kinds`.
- `variant`: optional detail for a specialized template that shares the same
  tracker, source, and agent provider. Keep variants as a suffix on the file
  name, for example `opencode.canary.md`, before adding another directory level.

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

Example aliases:

```text
memory/no_repo/mock
tapd/cnb/opencode
tapd/cnb/claude_code
tapd/cnb/codebuddy_code
tapd/github/codex
linear/github/codex
linear/github/claude_code
linear/github/codebuddy_code
linear/github/opencode.canary
```

## Template author checklist

Operational notes:

- `memory/no_repo/mock` is the local Quick Start template. It uses the memory
  tracker, memory repo provider, and mock agent provider, so it starts without
  Linear, GitHub, CNB, Codex, Claude Code, OpenCode, or any other external
  credentials.
- `linear/github/codex` and `tapd/github/codex` run Codex with
  `approval_policy: never` and a `danger-full-access` sandbox. Use them only in
  trusted evaluation or production environments whose repository, tracker, and
  credential boundaries are explicitly prepared for unattended write access.
- `tapd/cnb/claude_code` and `linear/github/claude_code` run Claude Code with
  `bypassPermissions`; treat them as the same trusted-environment class.
- `linear/github/codebuddy_code` and `tapd/cnb/codebuddy_code` run CodeBuddy
  Code over ACP stdio with `permission_mode: bypass_permissions`,
  session-scoped generated MCP Dynamic Tools, and a managed credential reference
  at `credential://codebuddy_code/default`. Store that account locally before
  starting the template; plugin-hosted tools, auxiliary HTTP, usage metrics,
  quota probing, and remote runtime are intentionally not enabled.
- The Linear templates require `LINEAR_PROJECT_SLUG` so a bundled template
  cannot silently target a repository maintainer's private Linear project.
- Templates that use `SYMPHONY_WORKSPACE_ROOT` fall back to Symphony's runtime
  default when the variable is unset, but production deployments should set it
  explicitly to an isolated workspace root.

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

```bash
symphony --template memory/no_repo/mock
symphony --template tapd/cnb/opencode
symphony --template tapd/cnb/codebuddy_code
symphony --template linear/github/codex
symphony --template linear/github/claude_code
symphony --template linear/github/codebuddy_code
symphony --template linear/github/opencode.canary
```

Running `symphony` without a workflow path or `--template` loads the project
default `WORKFLOW.md`.

Provider options inside templates should remain provider-native but portable:

- Use executable names in `command` or `command_argv`, not machine-local
  absolute paths.
- For Claude Code, `model: sonnet` is a Claude Code model alias. It is useful
  when a template should follow Claude Code's current Sonnet selection. Replace
  it with a full model id when reproducible model pinning is required.
- For CodeBuddy Code, use a managed `credential_ref` instead of placing
  `CODEBUDDY_API_KEY`, `CODEBUDDY_AUTH_TOKEN`, or related auth environment
  variables directly in template `agent_provider.options.env`.
- For OpenCode, `agent` selects the OpenCode agent profile, while `model`
  selects the provider/model pair sent to OpenCode.

Keep the three segments even when a tracker currently has only one template.
That keeps aliases predictable and lets tooling list, validate, and document
templates without special cases. If a source/agent combination needs variants,
prefer adding detail to the file name first, for example
`tapd/cnb/opencode.low_concurrency.md`. Add another directory level only after a
single combination has enough variants that file names become hard to scan.

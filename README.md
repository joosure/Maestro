# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-early%20stage-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

Languages: [English](./README.md) · [简体中文](./README.zh-CN.md) · [日本語](./README.ja.md) · [한국어](./README.ko.md) · [Español](./README.es.md) · [Português](./README.pt-BR.md) · [More](./LANGUAGES.md)

## Let AI agents work from real project tasks.

Maestro connects **project systems, Git repositories, and coding agents** into one engineering task execution flow.

Instead of watching one AI chat at a time, Maestro can read new or ready tasks from systems such as Linear or TAPD, create an isolated workspace for each task, prepare the target Git repository, start the right AI agent, record what happened, and write the result back to the project system.

It is not another coding agent.

It helps teams answer the questions that appear after agents become useful: where the task comes from, where the code comes from, where the agent runs, how many tasks can run in parallel, what changed, whether the result can be trusted, and how the team can review or recover the run.

> **Symphony proved that project tasks can drive agents. Maestro turns that pattern into an operable engineering platform.**

---

## One example

Imagine a new task appears in TAPD or Linear:

> The checkout page fails when a user applies two coupons.

With Maestro, that task can become a visible agent run:

1. Maestro syncs or reads the task from TAPD, Linear, or another project system.
2. Maestro creates an isolated workspace in its own runtime environment.
3. Maestro clones or checks out the target Git repository into that workspace.
4. Maestro starts Codex, Claude Code, OpenCode, or another supported agent with the task, repository copy, and allowed tools.
5. The agent analyzes the repository copy and prepares a code change, analysis result, or review suggestion.
6. Maestro records the diff, logs, tool calls, summary, and related links.
7. Maestro writes the result back to the project system so the team can review, continue, or take over.

The point is not to let an agent run blindly. The point is this:

> **A project task becomes an isolated, recorded, reviewable agent engineering run.**

The isolated workspace matters because each task gets its own directory, repository copy, logs, and temporary files. Multiple projects and tasks can run in parallel without polluting each other, and failed runs are easier to inspect, clean up, and retry.

---

## Why this matters

Coding agents are getting better at writing code. Teams need more than code generation.

They need practical answers:

- Which project system does the task come from?
- Which Git repository and branch does it map to?
- Which agent should run it?
- Where does the agent run?
- How do multiple runs stay isolated?
- What changed?
- Can humans review the result?
- What happens if it fails?
- How can the team understand what happened?

Maestro is built around those questions.

---

## What you can do with Maestro

### 1. Turn a bug task into a pull request

A bug appears in TAPD or Linear. Maestro reads the task, creates an isolated workspace, prepares the target Git repository, starts an agent, lets the agent analyze and change code, and writes the PR link, summary, and open questions back to the task.

### 2. Analyze a requirement before coding

If a requirement is not ready, Maestro can ask an agent to produce scope, risks, acceptance criteria, and clarification questions before anyone starts implementation.

### 3. Refine a task that cannot start yet

If a task lacks context, Maestro can surface assumptions, blockers, and questions instead of letting an agent guess.

### 4. Triage incoming work

Maestro can help classify new tasks, suggest priority, identify risk, and recommend the next state.

### 5. Compare different coding agents

Run similar tasks with Codex, Claude Code, or OpenCode and compare outputs, failure modes, logs, and delivery records.

### 6. Try the flow locally without real accounts

Use the local memory/mock flow to understand Maestro without connecting Linear, TAPD, GitHub, CNB, Codex, Claude Code, or OpenCode.

---

## Current integration support

The systems below are **supported integrations and bundled templates**, not systems embedded inside Maestro. Linear, TAPD, GitHub, CNB, Codex, Claude Code, and OpenCode remain external systems or tools. Maestro connects and orchestrates them.

Project-system adapters:

- Linear
- TAPD
- Memory, for local tests and demos

Agent adapters:

- Codex
- Claude Code
- OpenCode
- Mock, for local tests and demos

Code-platform adapters:

- GitHub
- CNB
- Memory, for local tests and demos

Bundled workflow templates include:

- `memory/no_repo/mock`
- `linear/github/codex`
- `linear/github/claude_code`
- `linear/github/opencode.canary`
- `tapd/github/codex`
- `tapd/cnb/opencode`
- `tapd/cnb/claude_code`

Maestro is designed to grow through more project systems, code platforms, agents, and workflow templates.

---

## How it works

```text
Task in a project system
   ↓
Maestro reads/syncs the task and decides whether to handle it
   ↓
Maestro creates an isolated workspace in its own runtime environment
   ↓
The target Git repository is prepared inside that workspace
   ↓
An AI agent runs with the task, repository copy, and allowed tools
   ↓
The agent produces a code change, analysis result, or review suggestion
   ↓
Maestro records diffs, logs, tool calls, summaries, and links
   ↓
Maestro writes the result back to the project system for review or handoff
```

For developers, the same flow is organized around a few extension points:

- **Project systems**: where tasks come from, such as Linear or TAPD.
- **Git repositories and code platforms**: where code is cloned from and where branches, PRs, reviews, and checks happen.
- **Agents**: who performs the work, such as Codex, Claude Code, or OpenCode.
- **Workflows**: what kind of work should happen, such as fixing bugs, analyzing requirements, refining tasks, triaging work, or suggesting reviews.
- **Workspaces and runtimes**: where each agent run happens, how it is isolated, and how runs can happen in parallel.
- **Records**: logs, diffs, task comments, summaries, and other reviewable information.

---

## Quick start

Clone the repository:

```bash
git clone https://github.com/joosure/Maestro.git
cd Maestro
```

Install the pinned Erlang / Elixir toolchain. `mise` is recommended:

```bash
cd elixir
mise trust
mise install
cd ..
```

Install dependencies and run tests:

```bash
make -C elixir deps
make -C elixir test
```

Start the local demo:

```bash
make -C elixir build
cd elixir
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

Open the optional dashboard at:

```text
http://localhost:4000
```

This demo uses memory data and a mock agent. It is the safest way to understand the project before connecting real systems.

> Public branding uses **Maestro**. Some runtime names still use `symphony` for compatibility, including the CLI entrypoint and some environment variables.

---

## Using real systems

After the local demo, you can connect a real project system, Git repository, and coding agent.

### Example: TAPD + GitHub + Codex

```bash
export TAPD_API_USER=...
export TAPD_API_PASSWORD=...
export TAPD_WORKSPACE_ID=...
export SOURCE_REPO_URL=https://github.com/owner/repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=owner/repo

./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template tapd/github/codex \
  --port 4000
```

### Example: Linear + GitHub + Codex

```bash
export LINEAR_API_KEY=...
export LINEAR_PROJECT_SLUG=...
export SOURCE_REPO_URL=https://github.com/owner/repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=owner/repo

./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template linear/github/codex \
  --port 4000
```

Before using real repositories or high-privilege credentials, read the runtime and template documentation:

- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## What Maestro is, and is not

Maestro is:

- an engineering task execution platform that connects project systems, Git repositories, and coding agents;
- a way to run AI agents from real project tasks;
- a workflow layer for coding, requirement analysis, task refinement, triage, and review suggestions;
- a safer way to test, compare, and manage different coding agents.

Maestro is not:

- a new large language model;
- a replacement for Codex, Claude Code, or OpenCode;
- a tool for bypassing team review, testing, or release judgment;
- a system you should give repository access to and then leave unattended.

---

## Project status

Maestro is early-stage software under active development.

It is suitable for:

- learning how task-driven agent workflows can work;
- running local memory/mock demos;
- prototyping new integrations;
- experimenting with real systems in controlled environments.

Use extra care before:

- allowing agents to modify real repositories or push branches;
- allowing agents to write back to real project-system states or comments;
- using high-privilege credentials or personal tokens;
- sharing one runtime environment across multiple teams;
- skipping human review before test, release, or production steps.

The guiding rule is:

> **Automate boldly. Gate carefully. Keep the trail visible.**

---

## Learn more

- [Roadmap](./ROADMAP.md)
- [Languages](./LANGUAGES.md)
- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Attribution

Maestro started as a fork of [OpenAI Symphony](https://github.com/openai/symphony). Symphony demonstrated that project tasks can drive coding agents. Maestro extends that idea into a broader platform for real engineering workflows.

---

## License

Maestro is licensed under the GNU Affero General Public License version 3 (AGPL-3.0-only). Portions derived from OpenAI Symphony retain their Apache-2.0 attribution and notice requirements. Review `LICENSE`, `NOTICE`, `LICENSES/Apache-2.0.txt`, `MODIFICATIONS.md`, `SOURCE.md`, and `THIRD_PARTY_LICENSES.md` before using or distributing Maestro.

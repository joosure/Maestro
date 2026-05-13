# Maestro Elixir Runtime

This directory contains the Elixir/OTP runtime implementation for Maestro
Control Plane (Maestro): a tracker-driven orchestrator that creates isolated
workspaces and runs configured agent providers against tracker work items and,
when configured, target repositories.

Concrete runtime identifiers still use compatibility names inherited from the
original implementation. Keep `SymphonyElixir` module names, the `symphony`
CLI/escript, `.symphony` runtime directories, and `SYMPHONY_*` environment
variables unchanged unless a task explicitly includes a compatibility-breaking
rename.

## Environment

- Tool versions are pinned in `mise.toml` (Elixir `1.19.5-otp-28` and
  Erlang/OTP `28`).
- If your shell is not already managed by `mise`, prefix commands with
  `mise exec --`.
- Install deps: `mix setup`.
- Build the escript: `mix build`.
- Main local quality gate: `make all` (setup, build, format check, lint,
  coverage, and dialyzer).
- Open-source hygiene gate: `make secret-scan`.

## Codebase-Specific Conventions

- Runtime config is loaded from workflow front matter via
  `SymphonyElixir.Workflow` and `SymphonyElixir.Config`. The default path is
  `WORKFLOW.md`; CLI/app-env overrides may point to a different workflow file,
  and `--template <alias>` selects bundled templates under
  `priv/workflow_templates/`.
- Template aliases use `<tracker>/<source>/<agent-provider>[.<variant>]`; use
  `no_repo` as the source for workflows that do not perform repository
  operations.
- Keep public/operator-facing prose on the Maestro brand, while preserving
  literal implementation names such as `SymphonyElixir`, `symphony`,
  `.symphony`, and `SYMPHONY_*` on concrete runtime surfaces.
- Keep implementation behavior aligned with runtime docs, workflow templates,
  and tests that ship in this repository.
- Do not let runtime source, docs, tests, or templates depend on source-only
  design assets.
- Prefer adding config access through `SymphonyElixir.Config` instead of
  ad-hoc env reads.
- Workspace safety is critical:
  - Never run an agent turn with the Maestro source repository as cwd.
  - Workspaces must stay under the configured workspace root.
  - Target repositories cloned by workflow templates must stay isolated under
    `repo/`.
- Orchestrator behavior is stateful and concurrency-sensitive; preserve retry,
  reconciliation, dispatch, and cleanup semantics.
- Keep root service modules thin facades when a namespace already exists.
  `Workspace`, `Orchestrator`, and `Observability.StatusDashboard` delegate
  into matching namespaces under `workspace/`, `orchestrator/`, and
  `observability/status_dashboard/`.
- SSH transport belongs under `platform/ssh.ex` as
  `SymphonyElixir.Platform.SSH`. Do not introduce or depend on a root-level
  SSH facade.
- Provider-specific message summary mapping belongs under the owning
  `agent_provider/<provider>/` namespace; keep the generic status dashboard
  provider-neutral.
- Worker-daemon runtime code belongs under `agent/runtime/worker_daemon/`; keep
  `agent/runtime/executor/worker_daemon.ex` as the thin executor adapter and
  keep daemon server code under `lib/symphony_worker_daemon/`.
- Follow [`docs/architecture.md`](./docs/architecture.md) for normative
  file-placement, namespace-ownership, and AI-oriented refactor rules.
- Follow [`docs/logging.md`](./docs/logging.md) for logging conventions and
  required issue/session context fields.

## Tests and Validation

Choose validation based on the change's blast radius. Run targeted checks while
iterating; for code or runtime-contract changes, run the full local gate before
handoff.

```bash
make all
```

Useful targeted checks:

```bash
mix specs.check
mix test test/symphony_elixir/repo_architecture_test.exs
mix test test/symphony_elixir/workflow_templates_test.exs
make worker-daemon-check
```

For documentation-only changes, prefer focused validation over the full gate:

```bash
git diff --check -- <changed-docs>
mix test test/symphony_elixir/repo_architecture_test.exs
```

Do not run live E2E, destructive smoke, or real provider-turn targets unless
the task explicitly calls for them and the required credentials, repositories,
and tracker workspaces are intentionally available.

Before publishing or opening a PR, run:

```bash
make secret-scan
```

## Required Rules

- Public functions (`def`) in `lib/` must have an adjacent `@spec`.
  Split default-argument declarations such as `def foo(arg \\ nil)` are part
  of that same adjacent public API shape and are accepted by `mix specs.check`
  when the `@spec` sits immediately above the declaration/implementation pair.
- `defp` specs are optional.
- `@impl` callback implementations are exempt from the local `@spec`
  requirement.
- Keep changes narrowly scoped; avoid unrelated refactors.
- Follow existing module/style patterns in `lib/symphony_elixir/*`.
- Use structured parsers/APIs where the codebase already provides them; avoid
  ad-hoc string parsing for workflow YAML, provider payloads, or tracker
  responses.

## PR Requirements

- PR body must follow `../.github/pull_request_template.md` exactly.
- Validate PR body locally when needed:

```bash
mix pr_body.check --file /path/to/pr_body.md
```

## Docs Update Policy

If behavior/config changes, update docs in the same PR:

- `../README.md` for project concept, branding, and goals.
- `README.md` for Elixir runtime overview and run instructions.
- `docs/operations.md` for workflow, workspace, TAPD, SSH worker, dashboard,
  and operator runbook changes.
- `docs/repo_provider.md` for repository provider helpers, environment
  variables, GitHub/CNB behavior, and smoke workflows.
- `docs/testing.md` for test matrix, live E2E, local SSH, and destructive
  smoke validation changes.
- `docs/architecture.md` for module layout, namespace ownership, and
  structural conventions.
- `docs/logging.md` for observability, audit events, redaction, or
  dashboard/status-surface contract changes.
- `docs/agent_providers/` for provider-specific runtime, protocol, tooling, or
  token-accounting changes.
- `WORKFLOW.md` and `priv/workflow_templates/` for workflow/config contract
  changes.

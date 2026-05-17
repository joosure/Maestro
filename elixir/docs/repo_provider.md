# Repo Provider Guide

This guide covers the Maestro Elixir runtime's provider-neutral repository and
PR helper surface. Concrete implementation identifiers still use compatibility
names such as `symphony`, `SYMPHONY_*`, and `SymphonyElixir`.

## Helper Model

The bundled workspace helpers live under
[`../priv/workspace_automation/`](../priv/workspace_automation/):

- `bin/repo`: provider-neutral Git facts and side effects
- `bin/repo-provider`: provider-backed PR, review, check, merge, and API
  operations

Both helpers route through the `symphony` escript. A workspace must have either
`symphony` on `PATH` or `SYMPHONY_CLI` pointing to the executable.

Maestro exports configured repository fields to helper environment variables:

- `repo.base_branch` -> `SYMPHONY_REPO_BASE_BRANCH`
- `repo.branch.work_prefix` -> `SYMPHONY_REPO_BRANCH_WORK_PREFIX`
- `repo.provider.repository` -> `SYMPHONY_REPO_PROVIDER_REPOSITORY`
- `repo.provider.api_base_url` -> `SYMPHONY_REPO_PROVIDER_API_BASE_URL`
- `repo.provider.web_base_url` -> `SYMPHONY_REPO_PROVIDER_WEB_BASE_URL`

Repository-backed workflow templates also commonly consume:

```bash
export SOURCE_REPO_URL=https://github.com/example-user/sample-repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=example-user/sample-repo
```

Treat `example-user/sample-repo` as a placeholder and replace it with the
target repository.

## Prerequisites

Required host tools:

- `bash` and `git` for workspace bootstrap and repository operations
- `gh` for GitHub-backed PR automation
- `symphony` on `PATH`, or `SYMPHONY_CLI`, for bundled helpers

Provider credentials:

- GitHub: `GH_TOKEN`, `GITHUB_TOKEN`, or an already-authenticated `gh` keyring
  with access to the target repository and PR checks
- CNB: `CNB_TOKEN`

Runtime environment variable names are code-owned contracts. Repo-core names
live in `SymphonyElixir.Repo.RuntimeEnv`; repo-provider names live in
`SymphonyElixir.RepoProvider.RuntimeEnv`; CNB-specific names, including
`CNB_TOKEN`, live in `SymphonyElixir.RepoProvider.CNB.RuntimeEnv`.

Repo-provider kind values and display labels are code-owned by
`SymphonyElixir.RepoProvider.Kinds`. Defaults are owned separately by
`SymphonyElixir.RepoProvider.Defaults`, so registries, CLI output, smoke
selection, and config schemas stay aligned when a provider is added.

CNB `run-list` and `run-view` additionally depend on CNB build/bill
authorization for the target repository's build APIs.

## Repo Helper

`bin/repo` supports provider-neutral Git operations such as:

- repository root, current branch, head SHA, remote URL, and base branch
- generated working branch names
- status and diff inspection
- clone, fetch, merge, sync-base, and rerere setup
- branch creation and switching
- push and remote branch deletion
- staging and commit helpers

It delegates to `symphony repo` and does not perform PR, review, check, or
provider merge operations.

## Repo-Provider Helper

`bin/repo-provider` supports provider-backed operations such as:

- `current-kind`
- `auth-status`
- `pr-view`
- `pr-create`
- `pr-edit`
- `pr-add-label`
- `pr-issue-comments`
- `pr-add-issue-comment`
- `pr-reviews`
- `pr-review-comments`
- `pr-reply-review-comment`
- `pr-checks`
- `pr-land-watch`
- `pr-merge`
- `pr-close`
- `api`
- `run-list`
- `run-view`

In GitHub mode, the Elixir adapter owns the provider-neutral command surface
and uses `gh` as the underlying transport behind normalized output and error
contracts.

In CNB mode, the Elixir adapter owns the same provider-neutral command surface
except GitHub-only `pr-add-label`, and calls CNB HTTP APIs directly. The CNB
`api` path includes the bundled translation subset used by automation flows for
issue comments, review summaries, inline review comments/replies, and head
`check-runs`, including explicit repo paths with nested CNB namespaces such as
`repos/org/group/project/...`. Unmatched endpoints use direct OpenAPI
passthrough.

GitHub and CNB check-run normalizers emit the same internal status/conclusion
contract. Consumers should use `SymphonyElixir.RepoProvider.CheckRun` for
completed status checks, successful conclusion lists, and display fallback
values instead of duplicating provider-normalized literals.

The CNB helper implements `--jq` / `-q` internally for the query shapes used by
bundled automation, including field access, array indexing, and array
iteration. It does not require an external `jq` binary.

The Elixir implementation keeps the helper path split into three layers:

- `RepoProvider.Invocation` and `repo_provider/invocation/*` parse argv into a
  provider-neutral invocation struct.
- `RepoProvider.Command` and `repo_provider/command/*` execute parsed command
  semantics through the repo-provider facade and shape command-specific results.
- `RepoProvider.CLI.Evaluator` adapts parsed command execution to the CLI
  runtime by reading environment, resolving runtime config, emitting
  observability events, and returning `{stdout, stderr, exit_code}` tuples.

`RepoProvider.CommandNames` remains the root-level owner of the external helper
command-name contract because parser, smoke, helper, and provider handler code
all consume the same names.

CNB HTTP tuning environment variables:

- `SYMPHONY_REPO_PROVIDER_HTTP_TIMEOUT_SECONDS`, default `10`
- `SYMPHONY_REPO_PROVIDER_MAX_HTTP_RETRIES`, default `3`, retryable `GET`
  requests only
- `SYMPHONY_REPO_PROVIDER_RETRY_BACKOFF_SECONDS`, default `1`

## Land Watch

`pr-land-watch` is the canonical land watcher used by the bundled land skill.
It exits with:

- `2` for unresolved review feedback
- `3` for missing or failed CI
- `4` for PR head updates
- `5` for merge conflicts

Agent-review recognition is configured with:

- `SYMPHONY_AGENT_REVIEW_BOTS`, default empty
- `SYMPHONY_AGENT_REVIEW_REQUEST_TOKEN`, default `@agent review`
- `SYMPHONY_AGENT_REPLY_PREFIX`, default `[agent]`
- `SYMPHONY_AGENT_REVIEW_HEADING`, default `## Agent Review`

The Elixir owner for these names and defaults is
`SymphonyElixir.RepoProvider.LandWatch.RuntimeEnv`; land-watch policy code
should use that module instead of duplicating environment-variable literals.

## Observability

The Elixir repo-provider CLI emits structured observability events for command
start and finish with command name, provider kind, runtime path label, duration,
exit code, and error code when present.

The canonical field name is `repo_provider_runtime`, and the current value is
fixed to `symphony`.

## Smoke Validation

Run read-only smoke validation from `elixir/` after building the escript:

```bash
./bin/symphony repo-provider smoke --provider github --repo owner/repo --pr 123
./bin/symphony repo-provider smoke --provider cnb --repo group/repo --pr 123 --api-endpoint 'repos/{owner}/{repo}/issues/123/comments' --api-jq '.[0].id'
./bin/symphony repo-provider smoke --provider github --repo owner/repo --pr 123 --json
```

Write-path smoke is explicitly destructive:

```bash
./bin/symphony repo-provider smoke --provider github --repo owner/repo --destructive --head feature/smoke --base main --json
./bin/symphony repo-provider smoke --provider cnb --repo group/repo --destructive --auto-provision-cnb-pipeline --base main --json
```

Development alternatives:

```bash
mix repo_provider.smoke --provider github --repo owner/repo --pr 123
make repo-provider-smoke REPO_PROVIDER_SMOKE_ARGS='--provider github --repo owner/repo --pr 123'
```

By default, the smoke task probes only `current-kind` and `auth-status`.
`--pr <number>` adds `pr-view`, `pr-reviews`, and `pr-checks`. `--api-endpoint
<path>` adds a read-only `api` GET probe.

`--destructive --head <branch>` opts into a write-path smoke that creates,
edits, verifies, and closes a PR for an already-pushed source branch. It does
not merge by default.

`--destructive --auto-provision-cnb-pipeline` is CNB-only and creates a
temporary branch with a minimal `.cnb.yml`, validates `run-list` and
`run-view --log`, then closes the PR and deletes the branch. The generated
`.cnb.yml` includes a branch-specific YAML comment so repeated smoke runs still
produce a disposable diff when the base branch already contains a previous smoke
pipeline.

The task exits non-zero when any probe fails and emits structured
`repo_provider_smoke_*` observability events. JSON output reports summaries and
byte counts rather than full raw provider stdout/stderr so API payloads are not
dumped by default.

## Smoke Inputs

Required live smoke inputs:

- `--provider github|cnb` or `SYMPHONY_REPO_PROVIDER_KIND`
- `--repo owner-or-group/repo` or `SYMPHONY_REPO_PROVIDER_REPOSITORY`
- `--pr <number>` for PR-specific probes
- `--destructive --head <branch>` for write-path smoke against an existing
  remote source branch
- `--destructive --auto-provision-cnb-pipeline` for CNB-only write-path smoke
- `CNB_TOKEN` for CNB smoke

GitHub smoke requires `gh` on `PATH` plus one of `GH_TOKEN`, `GITHUB_TOKEN`, or
an already-authenticated `gh` keyring with access to the target repository and
PR checks.

CNB auto-provision smoke additionally requires Git push permission on the target
repository and CNB build/bill authorization for the target repository's build
endpoints.

CNB private or non-default endpoints may also require
`SYMPHONY_REPO_PROVIDER_API_BASE_URL` and
`SYMPHONY_REPO_PROVIDER_WEB_BASE_URL`.

## GitHub Actions

The repository includes manual workflows for repo-provider validation:

- [`../../.github/workflows/repo-provider-smoke.yml`](../../.github/workflows/repo-provider-smoke.yml)
- [`../../.github/workflows/repo-provider-destructive-smoke.yml`](../../.github/workflows/repo-provider-destructive-smoke.yml)

Configure these repository secrets when using those workflows:

- `REPO_PROVIDER_GITHUB_TOKEN` for GitHub repos outside the workflow's own
  repository or when the default `GITHUB_TOKEN` lacks sufficient read access
- `REPO_PROVIDER_CNB_TOKEN` for CNB smoke; the workflow maps this secret into
  the runtime `CNB_TOKEN` contract before invoking the Elixir smoke task

The destructive workflow supports either an existing remote source branch via
`head_branch` or CNB's `auto_provision_cnb_pipeline=true` mode.

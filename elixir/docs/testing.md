# Testing Guide

This guide covers local quality gates, secret scanning, and live external E2E
validation for the Maestro Elixir runtime. Concrete implementation identifiers
still use compatibility names such as `SymphonyElixir`, `symphony`, and
`SYMPHONY_*`.

## Local Quality Gate

Run the standard local quality gate from `elixir/`:

```bash
make all
```

`make all` runs the standard local quality gate, including coverage
enforcement. The default coverage threshold is `70`; override it with
`SYMPHONY_TEST_COVERAGE_THRESHOLD` or `make COVERAGE_THRESHOLD=<n> all`.

Useful focused targets:

- `make deps`
- `make build`
- `make fmt-check`
- `make lint`
- `make test`
- `make coverage`
- `make dialyzer`
- `make tracker-smoke`
- `make repo-provider-smoke`
- `make agent-provider-smoke`
- `make worker-daemon-check`

Target definitions live in [`../Makefile`](../Makefile).

## Tracker Smoke

Run tracker smoke validation from `elixir/` before claiming that a workflow's
tracker configuration is production-ready:

```bash
mix tracker.smoke --template memory/no_repo/mock --issue local-memory-1 --json
make tracker-smoke TRACKER_SMOKE_ARGS='--template memory/no_repo/mock --issue local-memory-1 --json'
```

The default mode is read-only: it validates the workflow tracker config, runs
the tracker `healthcheck`, and optionally fetches one issue by id. State-write
validation is opt-in and must target a disposable or explicitly approved issue:

```bash
mix tracker.smoke --workflow WORKFLOW.md --issue <issue-id> --confirm-state-write --json
```

When `--confirm-state-write` is supplied without `--write-state`, the smoke
runner writes the fetched current state back with `expected_current_state` set
to that same fetched state. This validates tracker write permission and stale
state protection while avoiding an intentional route change.

## Agent-Provider Smoke

Run agent-provider smoke validation from `elixir/` before claiming that a
workflow's selected agent provider can launch in the target environment:

```bash
mix agent_provider.smoke --template memory/no_repo/mock --json
make agent-provider-smoke AGENT_PROVIDER_SMOKE_ARGS='--template memory/no_repo/mock --json'
```

By default the smoke runner validates workflow config, creates a temporary empty
workspace, prepares provider-owned tooling, starts the configured provider, sends
one minimal first-turn prompt, stops the session, and removes the temporary
workspace. It does not run the workflow business prompt and does not read or
write tracker issues, repositories, or repo-provider resources.

Use `--start-only` when an environment should validate provider process startup
without consuming a first-turn model request:

```bash
mix agent_provider.smoke --template tapd/cnb/opencode --start-only --json
```

## Secret Scan

Before publishing or opening a PR, run:

```bash
make secret-scan
```

The target runs [`../../scripts/secret-scan.sh`](../../scripts/secret-scan.sh),
which wraps `gitleaks`, `trufflehog`, and `detect-secrets`. The checked-in
[`../../.secrets.baseline`](../../.secrets.baseline) records reviewed false
positives from tests and examples; do not update it for real credentials.

## Live E2E Tests

Live external tests create disposable tracker resources and may launch real
agent sessions. Run them only when the required credentials and write
permissions are intentionally available.

The default E2E target is Linear-backed:

```bash
cd elixir
export LINEAR_API_KEY=...
export LINEAR_PROJECT_SLUG=...
make e2e
```

In the current Makefile, `make e2e` is an alias for `make e2e-linear`.

Linear live behavior:

- creates a temporary Linear project and issue
- writes a temporary `WORKFLOW.md`
- runs a real agent turn
- verifies the workspace side effect
- requires the default Codex provider to comment on and close the Linear issue
- marks the project completed so the run remains visible in Linear

Optional Linear environment:

- `SYMPHONY_LIVE_LINEAR_TEAM_KEY`, default `SYME2E`
- `SYMPHONY_LIVE_SSH_WORKER_HOSTS`, comma-separated SSH hosts using the same
  syntax as `worker.ssh_hosts`

## Local SSH Worker Validation

`make e2e` currently runs two Linear-backed live scenarios:

- one with a local worker
- one with SSH workers

If `SYMPHONY_LIVE_SSH_WORKER_HOSTS` is unset, the SSH scenario uses
`docker compose` to start disposable SSH workers on `localhost:<port>`. The
live test generates a temporary SSH keypair, mounts the host
`~/.codex/auth.json` into each worker, verifies that Maestro can talk to them
over real SSH, then runs the same orchestration flow against those worker
addresses.

Set `SYMPHONY_LIVE_SSH_WORKER_HOSTS` if you want `make e2e` to target real SSH
hosts instead. Use the same host-key verification posture you intend for
production when doing that validation.

To run the SSH live scenario against this machine without Docker, use
[`../test/support/live_e2e_local_ssh/localhost_ssh_worker.sh`](../test/support/live_e2e_local_ssh/localhost_ssh_worker.sh).
It starts a temporary loopback-only `sshd`, generates an ephemeral keypair, and
mirrors the caller's current `PATH` into remote SSH sessions so `codex` and
`node` stay visible without enabling a system-wide SSH service.

One-shot localhost SSH worker run:

```bash
cd elixir
export LINEAR_API_KEY=...
# Optional:
# export SYMPHONY_LIVE_LINEAR_TEAM_KEY=DEMO

test/support/live_e2e_local_ssh/localhost_ssh_worker.sh run -- \
  env SYMPHONY_RUN_LIVE_E2E=1 \
  mix test test/symphony_elixir/live_e2e_test.exs:129
```

Keep the local SSH worker alive across multiple commands:

```bash
cd elixir
test/support/live_e2e_local_ssh/localhost_ssh_worker.sh start
eval "$(test/support/live_e2e_local_ssh/localhost_ssh_worker.sh env)"

export LINEAR_API_KEY=...
mix test test/symphony_elixir/live_e2e_test.exs:129

test/support/live_e2e_local_ssh/localhost_ssh_worker.sh stop
```

Convenience target:

```bash
cd elixir
export LINEAR_API_KEY=...
make e2e-linear-local-ssh
```

Optional helper-script overrides:

- `SYMPHONY_LOCAL_SSH_WORKER_DIR`
- `SYMPHONY_LOCAL_SSH_WORKER_ALIAS`
- `SYMPHONY_LOCAL_SSH_WORKER_PORT`
- `SYMPHONY_LOCAL_SSH_WORKER_REMOTE_PATH`

Current SSH live coverage:

- `make e2e-linear` and `make e2e-linear-local-ssh` exercise the SSH path with
  a real Linear-backed workflow
- TAPD live smoke exists separately, but it is not currently documented as an
  equivalent tracker-plus-SSH live validation profile

## TAPD Live Smoke

TAPD live smoke entry points:

```bash
cd elixir
export TAPD_API_USER=...
export TAPD_API_PASSWORD=...
export TAPD_WORKSPACE_ID=...

# Optional but recommended when validating a non-Maestro target repo.
export SOURCE_REPO_URL=https://github.com/example-user/sample-repo.git
export SOURCE_REPO_BASE_BRANCH=main
# Optional only for the GitHub PR label convention.
# export SOURCE_REPO_PROVIDER_REQUIRED_PR_LABEL=...

# Optional but required to unskip TAPD route-policy live smoke cases.
# Use the exact raw TAPD status values from your workspace workflow.
# export TAPD_ROUTE_POLICY_PLANNING_STATE=...
# export TAPD_ROUTE_POLICY_DEVELOPING_STATE=...
# export TAPD_ROUTE_POLICY_REVIEW_STATE=...
# export TAPD_ROUTE_POLICY_MERGING_STATE=...
# export TAPD_ROUTE_POLICY_REWORK_STATE=...
# export TAPD_ROUTE_POLICY_RESOLVED_STATE=...
# export TAPD_ROUTE_POLICY_REJECTED_STATE=...

make e2e-tapd
make e2e-tapd-pr
make e2e-tapd-land
make e2e-tapd-rework
```

TAPD live behavior:

- `make e2e-tapd` self-provisions a temporary TAPD Story, dispatches it from
  the active state scan, performs a repo change, creates a local commit,
  creates or updates the persistent TAPD workpad comment, and moves the Story
  out of `active_states`
- the same live file also contains route-policy smoke for planning-route
  `transition_then_dispatch`, `wait`, and `stop`; those cases stay skipped
  unless every `TAPD_ROUTE_POLICY_*_STATE` variable is exported with the exact
  raw TAPD states from the target workspace
- single-Story reads in TAPD prompts and live harnesses use `GET /stories` with
  `params.id=<Story.id>`; path-style `/stories/<id>` is not part of the
  supported TAPD tool surface
- the TAPD client performs short bounded retries for transient TAPD `408`,
  `429`, `500`, `502`, `503`, and `504` responses
- the live harness layers additional retries around candidate-issue scans,
  issue-state refresh, and bounded orchestrator restart cleanup

`make e2e-tapd-pr` additionally requires authenticated `gh` access and validates
branch push, PR create/update, optional GitHub-only
`repo.provider.options.required_pr_label` enforcement, and PR metadata
write-back to the persistent TAPD workpad comment.

`make e2e-tapd-land` and `make e2e-tapd-rework` are destructive opt-in
harnesses. They create a temporary GitHub repo, exercise merge or rework flow
end-to-end, then delete the temporary repo.

For TAPD land/rework smoke, the active `gh` credential must be able to create
and delete a temporary repository in addition to push, PR, comment, and merge
operations. In practice this means repository `Administration` write,
`Contents` write, and `Pull requests` write. If the target owner is an
organization, the token may also need explicit org approval before `gh` can use
it.

If normal `gh auth status` is sufficient for `make e2e-tapd-pr` but fails on
`make e2e-tapd-land` or `make e2e-tapd-rework` with `createRepository`, run
just those destructive smoke commands with a session-local `GH_TOKEN=...`
override, then unset it afterward so your normal `gh` keyring session remains
unchanged.

GitHub may occasionally return a transient `404` when the harness creates a
label immediately after creating a brand-new temporary repo. If that happens on
land/rework smoke, retry the smoke once before treating it as a workflow
regression.

For repository-backed TAPD/GitHub/Codex validation, provide a disposable or
explicitly approved target repository through `SOURCE_REPO_URL`,
`SOURCE_REPO_BASE_BRANCH`, and optionally `SOURCE_REPO_PROVIDER_REPOSITORY`. A
representative full-flow validation should cover Story dispatch, repo content
change, branch push, GitHub PR creation, persistent TAPD workpad
branch/commit/PR sync, route-policy behavior, and final Story transition into
the configured review or terminal raw state.

## Repo-Provider Smoke

Repo-provider smoke validation is documented in
[`repo_provider.md`](./repo_provider.md).

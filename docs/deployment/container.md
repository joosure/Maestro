# Container Deployment Guide: Start with Mock, Then Connect Real Workflows

Languages: [English](./container.md) | [简体中文](./container.zh-CN.md)

This guide explains how to run the Maestro/Symphony Elixir OTP runtime in `elixir/` with Docker and Docker Compose. It has two goals: **a newcomer can get a working container on the first read, and a maintainer can understand the image, configuration, and security boundaries clearly**.

> **Naming note**
>
> The current product name is **Maestro**. Existing CLI entrypoints, image commands, module names, and environment variables still use the older name, so commands and configuration continue to use `symphony` / `SYMPHONY_*`. This is expected, not a documentation error. Use the exact names shown in this guide.

## Which Section Should I Read?

| Goal | Read this |
| --- | --- |
| Run the container for the first time without any external account or token | [Container Mock Quickstart](#container-mock-quickstart) |
| You finished the quickstart and want to know what to do next | [8. After Mock Quickstart](#8-after-mock-quickstart) |
| Connect Linear/GitHub/OpenCode | [Minimal Linear + GitHub + OpenCode Example](#31-minimal-linear--github--opencode-example) |
| Connect Linear/GitHub/Codex | [Minimal Linear + GitHub + Codex Example](#32-minimal-linear--github--codex-example) |
| Connect Linear/GitHub/Claude Code | [Minimal Linear + GitHub + Claude Code Example](#33-minimal-linear--github--claude-code-example) |
| Connect TAPD/CNB/CodeBuddy Code | [Minimal TAPD + CNB + CodeBuddy Code Example](#34-minimal-tapd--cnb--codebuddy-code-example) |
| Maintain Dockerfile, Compose, or provider images | [Images](#images) |
| Own production release, security scanning, or platform governance | [Runtime Controls](#runtime-controls), [Security Notes](#security-notes), and [Appendix B: Supply-Chain Checks](#appendix-b-supply-chain-checks) |
| Change environment variables, image targets, or provider versions | [Maintainer Change Checklist](#maintainer-change-checklist) and [Appendix C: Environment Variable Reference](#appendix-c-environment-variable-reference) |
| Only look up variables | [Appendix C: Environment Variable Reference](#appendix-c-environment-variable-reference) |

If you are not sure which path to choose, start with **Container Mock Quickstart**. It does not need a real tracker, repository, agent provider, or model API key.

## Concept Overview

| Concept | Meaning |
| --- | --- |
| Tracker | A task system, such as Linear or TAPD. |
| Repo provider | A code hosting platform, such as GitHub or CNB. |
| Agent provider | A coding agent/model tool, such as OpenCode, Codex, Claude Code, or CodeBuddy Code. |
| Template | A preset workflow combination, such as `memory/no_repo/mock` or `linear/github/opencode`. |
| Mock Quickstart | A local mock flow that does not connect external systems. It validates the image, OTP release, HTTP server, and Dashboard. |
| OTP release | The packaged Elixir application. The container starts the release without requiring Mix, Elixir, or Erlang on the host. |
| Dashboard | The web UI exposed by the container, available at `http://localhost:4000` by default. |
| Managed credential | An Agent Provider credential managed by Maestro/Symphony. Workflows with `credential_ref` need initialization; Integration Compose runs login + verify automatically before serving. |

Container usage has two paths:

- **Container Mock Quickstart**: runs `memory/no_repo/mock` without real trackers, repositories, or agent providers. It requires no external credentials and is the safest first validation path.
- **Real workflow integration**: runs a real workflow template with tracker, repository, and agent provider credentials supplied by `.env`, environment variables, or read-only file mounts. This is the container path for real-system integration; it is **not a full production-release standard by itself**.

## Container Mock Quickstart

Use this path first if you are new to Maestro/Symphony, or if you only want to verify that the container image, OTP release, HTTP server, and Dashboard work.

It matches the low-risk `memory/no_repo/mock` path recommended by the [Newcomer End-to-End Run Guide](../../elixir/docs/quickstart/en.md), but the container path does not require a local Elixir, Erlang, or `mise` setup.

### What This Quickstart Runs

| Dimension | Value |
| --- | --- |
| Docker target | `runtime-base` |
| Tracker | `memory` |
| Repo provider | `memory` |
| Agent provider | `mock` |
| Template | `memory/no_repo/mock` |
| External credentials | None |
| Host port | `4000` |

This step does not require Linear, TAPD, GitHub, CNB, Codex, Claude Code, OpenCode, model API keys, or repository tokens.

### 1. Prepare Docker

Install and start Docker first:

- macOS/Windows: use Docker Desktop with Compose v2 enabled.
- Linux: install Docker Engine and the Docker Compose plugin.

Confirm Docker is available:

```bash
docker --version
docker compose version
```

Clone the repository and enter the repository root:

```bash
git clone https://github.com/joosure/Maestro.git maestro
cd maestro
```

If you already have the repository, run all commands below from the repository root, not from `elixir/`.

### 2. Start the Container Mock Quickstart

```bash
docker compose -f deploy/compose/compose.quickstart.yml up --build
```

The first build can take several minutes because Docker must download base images, fetch Hex/Rebar dependencies, compile the Elixir application, and produce the OTP release. Later builds are usually faster because Docker can reuse layer cache.

The Mock Quickstart Compose file supplies these runtime values:

```text
SYMPHONY_TEMPLATE=memory/no_repo/mock
HOST=0.0.0.0
PORT=4000
SYMPHONY_WORKSPACE_ROOT=/workspaces
```

`HOST=0.0.0.0` lets the host reach the service inside the container; local runtime defaults are normally `127.0.0.1` for safety. Quickstart maps host port `4000` to container port `4000`.

### 3. Open the Dashboard

Open:

```text
http://localhost:4000
```

You should see the Dashboard. The terminal should also show output similar to:

```text
Dashboard: http://127.0.0.1:4000/
MEM-1 [classifying]
Local memory/mock workflow completed one ...
```

The container runs this OTP release entrypoint:

```text
/app/bin/symphony eval "SymphonyElixir.Release.Runner.serve_from_env()"
```

The image entrypoint converts the default `serve` command into the release call above. Other commands are passed directly to `/app/bin/symphony`, so later operator commands such as `accounts` and `repo-provider smoke` can run as `docker compose run ... symphony <command>`. In that Compose command, `symphony` is the Compose service name and `<command>` is what is passed to the release CLI inside the container. The host does not need Mix, Elixir, or a prebuilt local `elixir/bin/symphony` CLI.

### 4. Verify Health and State

In another terminal, from the repository root:

```bash
curl -fsS http://localhost:4000/healthz
```

Expected result:

```json
{"status":"ok"}
```

You can also inspect current orchestration state:

```bash
curl -fsS http://localhost:4000/api/v1/state
```

If the response contains `mock`, `memory`, `MEM-1`, issues, or recent events, the container Mock Quickstart is running correctly.

### 5. Inspect Container Status and Logs

Check whether the service is healthy:

```bash
docker compose -f deploy/compose/compose.quickstart.yml ps
```

Follow logs:

```bash
docker compose -f deploy/compose/compose.quickstart.yml logs -f symphony
```

Open a shell in the container when you need to inspect files or permissions:

```bash
docker compose -f deploy/compose/compose.quickstart.yml exec symphony bash
```

Useful checks inside the container:

```bash
id
ls -la /app /app/.symphony /app/log /workspaces
```

The runtime user should be the non-root `symphony` user. The default UID/GID is `10001:10001`.

### 6. Stop and Clean Up

Stop the container while keeping named volumes:

```bash
docker compose -f deploy/compose/compose.quickstart.yml down
```

Remove local quickstart state completely, including workspace, runtime state, and log volumes:

```bash
docker compose -f deploy/compose/compose.quickstart.yml down -v
```

Use `down -v` carefully. It deletes Docker volumes created by Compose.

### 7. Success Criteria and Common Issues

After Quickstart, you should be able to confirm:

- `docker compose -f deploy/compose/compose.quickstart.yml ps` shows the `symphony` service as running/healthy;
- `http://localhost:4000` opens in a browser;
- `curl -fsS http://localhost:4000/healthz` returns `{"status":"ok"}`;
- `curl -fsS http://localhost:4000/api/v1/state` contains mock workflow state such as `mock`, `memory`, `MEM-1`, issues, or recent events.

| Symptom | Common cause | Fix |
| --- | --- | --- |
| `docker compose` is not found | Compose v2 is not installed, or Docker Desktop is not running | Start Docker Desktop, or install the Docker Compose plugin |
| Build fails while downloading base images | Network or registry access issue | Retry after the network is stable; configure registry mirrors on corporate networks |
| Build fails while fetching Hex/Rebar dependencies | Access to Hex/Rebar is restricted | Retry, or configure your corporate proxy/mirror |
| Port `4000` is already in use | Another local service uses the port | Stop that service; Quickstart uses fixed `4000:4000`, so edit `compose.quickstart.yml` if you need another port |
| Dashboard does not open | Container is not started, still building, or unhealthy | Run `docker compose -f deploy/compose/compose.quickstart.yml ps` and inspect logs |
| `/healthz` fails | HTTP server did not start or the port is unavailable | Check logs and confirm `HOST=0.0.0.0` and `PORT=4000` |
| Permission errors under `/workspaces` or `/app/log` | Old volume ownership does not match the current UID/GID | Recreate volumes with `down -v`, or rebuild with matching `SYMPHONY_UID`/`SYMPHONY_GID` build args |

### 8. After Mock Quickstart

If you are unsure which path to take, follow this table from top to bottom.

| Goal | Next step |
| --- | --- |
| Understand local runtime and real workflow concepts first | Read the [Newcomer End-to-End Run Guide](../../elixir/docs/quickstart/en.md) |
| Validate the OpenCode integration image without real credentials | Use `SYMPHONY_OPENCODE_TEMPLATE=memory/no_repo/mock` with `--profile opencode` |
| Validate the Codex integration image without real credentials | Use `SYMPHONY_CODEX_TEMPLATE=memory/no_repo/mock` with `--profile codex` |
| Validate the Claude Code integration image without real credentials | Use `SYMPHONY_CLAUDE_CODE_TEMPLATE=memory/no_repo/mock` with `--profile claude-code` |
| Validate the CodeBuddy Code integration image without real credentials | Use `SYMPHONY_CODEBUDDY_TEMPLATE=memory/no_repo/mock` with `--profile codebuddy` |
| Connect real Linear/GitHub/OpenCode | Prepare `.env`, set `SYMPHONY_OPENCODE_TEMPLATE=linear/github/opencode`, then use `compose.integration.yml --profile opencode` |
| Connect real Linear/GitHub/Codex | Prepare `.env`, set `SYMPHONY_CODEX_TEMPLATE=linear/github/codex`, then use `compose.integration.yml --profile codex` |
| Connect real Linear/GitHub/Claude Code | Prepare `.env`, set `SYMPHONY_CLAUDE_CODE_TEMPLATE=linear/github/claude_code`, then use `compose.integration.yml --profile claude-code` |
| Connect real TAPD/CNB/CodeBuddy Code | Prepare TAPD/CNB/CodeBuddy by following the [Newcomer End-to-End Run Guide](../../elixir/docs/quickstart/en.md); use `compose.integration.yml --profile codebuddy` to build `runtime-agent-codebuddy` |
| Prepare production image promotion | See [Appendix B: Supply-Chain Checks](#appendix-b-supply-chain-checks), run `scripts/container-security-scan.sh`, and review Trivy/SBOM artifacts |

For the first real integration, use a test tracker, test repository, low-privilege token, and disposable workspace volume. Real workflows may clone repositories, push branches, create PR/MR, update tracker state, and write comments.

## Real Workflow Integration

> **Note**
>
> A real workflow connects to a real tracker, code repository, and Agent Provider. It may read or update issues, clone repositories, create branches, push code, create or update PR/MR, write comments, and call model APIs. For first validation, use test projects, test repositories, low-privilege tokens, and removable workspace volumes. `compose.integration.yml` requires an explicit provider profile such as `opencode`, `codex`, `claude-code`, or `codebuddy`; production readiness still depends on your image scanning, credential management, network policy, audit, backup, alerting, and release process.

In real workflow integration, the common components are:

- Tracker: the task source, such as Linear or TAPD;
- Repo provider: the code host, such as GitHub or CNB;
- Agent provider: the tool that performs coding work, such as OpenCode, Codex, Claude Code, or CodeBuddy Code;
- Template: the preset that combines those systems, such as `linear/github/opencode`.

### Before You Start: Make Three Choices

Real workflow configuration has a few branches. For a first integration, choose your path from this table before copying `.env` examples.

| Choice | Newcomer recommendation | When to choose something else |
| --- | --- | --- |
| Workflow source | Choose the provider profile template, for example `SYMPHONY_OPENCODE_TEMPLATE=linear/github/opencode` or `SYMPHONY_CODEX_TEMPLATE=linear/github/codex` | Use `SYMPHONY_WORKFLOW_PATH` if you generated a local workflow file from quickstart, or if the workflow contains `credential_ref` |
| Provider credentials | Use the provider's own config/env when the built-in template has no `credential_ref` | Use managed credentials when the workflow explicitly uses a `credential://provider/account` ref; startup preflight runs login + verify |
| Agent image | Choose exactly one provider profile: `opencode`, `codex`, `claude-code`, or `codebuddy` | Do not mix multiple provider CLIs into the generic `runtime-agent` image |

If this is your first Linear + GitHub + OpenCode integration, start with built-in template + `OPENCODE_CONFIG`. This avoids generating a local workflow and avoids managed credential store details. After that path works, use [Appendix A: Advanced Credentials and Local Workflow Files](#appendix-a-advanced-credentials-and-local-workflow-files) to switch to `SYMPHONY_WORKFLOW_PATH` and `credential_ref`.

### 1. Validate the Agent Integration Images First

`compose.integration.yml` does not provide a service without a profile. You must choose one profile explicitly: `--profile opencode`, `--profile codex`, `--profile claude-code`, or `--profile codebuddy`. Each profile builds the matching `runtime-agent-*` target and maps its provider-specific template variable to `SYMPHONY_TEMPLATE` inside the container. All provider targets start from the provider-neutral `runtime-agent` tools image and only add the pinned CLI required by that provider.

Before connecting real systems, you can still use the mock template to validate that the matching provider image starts. Run only the profile you plan to use.

OpenCode image:

```bash
SYMPHONY_OPENCODE_TEMPLATE=memory/no_repo/mock docker compose -f deploy/compose/compose.integration.yml --profile opencode up -d --build
curl -fsS http://localhost:4000/healthz
docker compose -f deploy/compose/compose.integration.yml --profile opencode down
```

Codex image:

```bash
SYMPHONY_CODEX_TEMPLATE=memory/no_repo/mock docker compose -f deploy/compose/compose.integration.yml --profile codex up -d --build
curl -fsS http://localhost:4000/healthz
docker compose -f deploy/compose/compose.integration.yml --profile codex down
```

Claude Code image:

```bash
SYMPHONY_CLAUDE_CODE_TEMPLATE=memory/no_repo/mock docker compose -f deploy/compose/compose.integration.yml --profile claude-code up -d --build
curl -fsS http://localhost:4000/healthz
docker compose -f deploy/compose/compose.integration.yml --profile claude-code down
```

CodeBuddy Code image:

```bash
SYMPHONY_CODEBUDDY_TEMPLATE=memory/no_repo/mock docker compose -f deploy/compose/compose.integration.yml --profile codebuddy up -d --build
curl -fsS http://localhost:4000/healthz
docker compose -f deploy/compose/compose.integration.yml --profile codebuddy down
```

### 2. Prepare `.env`

Create a local `.env` from the repository root:

```bash
cp .env.example .env
```

Edit `.env` and fill only the variables required by your selected template. Do not commit real `.env` files.

This repository-root `.env` is for Docker Compose. It is intentionally separate from the local quickstart files under `elixir/`, such as `elixir/.env.tapd.local` and `elixir/.env.linear.local`. If you generated a local workflow by following the quickstart guide, keep that workflow file under `elixir/quickstart/` and mount it into the container with `SYMPHONY_WORKFLOW_FILE` as shown in Appendix A.

`.env.example` sets separate templates for the integration profiles:

```env
SYMPHONY_OPENCODE_TEMPLATE=linear/github/opencode
SYMPHONY_CODEX_TEMPLATE=linear/github/codex
SYMPHONY_CLAUDE_CODE_TEMPLATE=linear/github/claude_code
SYMPHONY_CODEBUDDY_TEMPLATE=tapd/cnb/codebuddy_code
```

Docker Compose automatically reads `.env` from the repository root. Do not reuse one global `SYMPHONY_TEMPLATE` for integration profiles; provider-specific variables prevent choosing the `opencode` profile while passing a CodeBuddy template. For temporary smoke tests, override the provider-specific variable once at the command line, such as `SYMPHONY_OPENCODE_TEMPLATE=memory/no_repo/mock`.

Each `compose.integration.yml` profile sets `SYMPHONY_TEMPLATE` inside the container to start a built-in template. If you generated a local workflow file by following the [Newcomer End-to-End Run Guide](../../elixir/docs/quickstart/en.md) and want the container to run that file instead of a built-in template, use the `SYMPHONY_WORKFLOW_PATH` path in [Appendix A](#appendix-a-advanced-credentials-and-local-workflow-files).

Before starting real systems, check these three points:

- the provider-specific template variable in `.env` matches the selected profile, or `SYMPHONY_WORKFLOW_PATH` is set;
- setting `OPENCODE_CONFIG=./secrets/opencode.json` does not put the file into the container by itself; you must also enable the matching read-only mount on the `symphony-opencode` service in `compose.integration.yml`;
- if you use `SYMPHONY_WORKFLOW_PATH`, you must also enable the `SYMPHONY_WORKFLOW_FILE` read-only mount so `/app/WORKFLOW.local.md` really exists inside the container.

### 3. Prepare Provider-Specific `.env` Examples

The paths below are peer provider profile examples. Use 3.1 for `opencode`, 3.2 for `codex`, 3.3 for `claude-code`, and 3.4 for `codebuddy`.

#### 3.1 Minimal Linear + GitHub + OpenCode Example

The `opencode` profile in `deploy/compose/compose.integration.yml` maps this `.env` variable to `SYMPHONY_TEMPLATE` inside the container:

```text
SYMPHONY_OPENCODE_TEMPLATE=linear/github/opencode
```

A minimal `.env` usually includes:

```env
# Required: choose the OpenCode profile workflow template
SYMPHONY_OPENCODE_TEMPLATE=linear/github/opencode

# Required: Linear
LINEAR_API_KEY=<linear api key>
LINEAR_PROJECT_SLUG=<linear project slug>

# Required: target repository
SOURCE_REPO_URL=https://github.com/<owner>/<repo>.git
SOURCE_REPO_BASE_BRANCH=main

# Recommended: explicit provider repository name, usually owner/repo
SOURCE_REPO_PROVIDER_REPOSITORY=<owner>/<repo>

# Required: OpenCode provider access, choose one
# Option A, recommended for newcomers: use OpenCode's own config file; see Appendix A for the OPENCODE_CONFIG mount
OPENCODE_CONFIG=./secrets/opencode.json
# Option B: use a local workflow with credential_ref; see Appendix A for SYMPHONY_WORKFLOW_PATH and automatic preflight
# ZAI_API_KEY=<zai api key>

# Choose one GitHub token variable. If unsure, set only one to avoid confusion.
GH_TOKEN=<github token>
# GITHUB_TOKEN=<github token>
```

If OpenCode or repository access uses file credentials, uncomment and adjust the read-only mounts in `deploy/compose/compose.integration.yml`:

```yaml
# - ${OPENCODE_CONFIG:-../../secrets/opencode.json}:/home/symphony/.config/opencode/opencode.json:ro
# - ${SSH_PRIVATE_KEY:-../../secrets/id_rsa}:/home/symphony/.ssh/id_rsa:ro
```

If the workflow uses `credential_ref`, or if you need to mount a locally generated workflow file, jump to [Appendix A: Advanced Credentials and Local Workflow Files](#appendix-a-advanced-credentials-and-local-workflow-files). The main flow keeps the newcomer-recommended built-in template + `OPENCODE_CONFIG` path.

#### 3.2 Minimal Linear + GitHub + Codex Example

The `codex` profile maps this `.env` variable to `SYMPHONY_TEMPLATE` inside the container:

```env
SYMPHONY_CODEX_TEMPLATE=linear/github/codex
LINEAR_API_KEY=<linear api key>
LINEAR_PROJECT_SLUG=<linear project slug>
SOURCE_REPO_URL=https://github.com/<owner>/<repo>.git
SOURCE_REPO_BASE_BRANCH=main
SOURCE_REPO_PROVIDER_REPOSITORY=<owner>/<repo>
GH_TOKEN=<github token>
OPENAI_API_KEY=<openai api key>
```

```bash
docker compose -f deploy/compose/compose.integration.yml --profile codex up -d --build
```

#### 3.3 Minimal Linear + GitHub + Claude Code Example

The `claude-code` profile maps this `.env` variable to `SYMPHONY_TEMPLATE` inside the container:

```env
SYMPHONY_CLAUDE_CODE_TEMPLATE=linear/github/claude_code
LINEAR_API_KEY=<linear api key>
LINEAR_PROJECT_SLUG=<linear project slug>
SOURCE_REPO_URL=https://github.com/<owner>/<repo>.git
SOURCE_REPO_BASE_BRANCH=main
SOURCE_REPO_PROVIDER_REPOSITORY=<owner>/<repo>
GH_TOKEN=<github token>
CLAUDE_CODE_OAUTH_TOKEN=<claude code oauth token>
```

```bash
docker compose -f deploy/compose/compose.integration.yml --profile claude-code up -d --build
```

#### 3.4 Minimal TAPD + CNB + CodeBuddy Code Example

The other newcomer real workflow in the [Newcomer End-to-End Run Guide](../../elixir/docs/quickstart/en.md) is `tapd/cnb/codebuddy_code`. The project supports the `codebuddy_code` provider, and the Dockerfile provides a `runtime-agent-codebuddy` target. It starts from `runtime-agent`, installs the pinned `@tencent-ai/codebuddy-code` package, sets `CODEBUDDY_CONFIG_DIR=/home/symphony/.codebuddy`, and sets `DISABLE_AUTOUPDATER=1` so the image does not drift after it starts.

To run that path, use `compose.integration.yml --profile codebuddy` and set:

```env
SYMPHONY_CODEBUDDY_TEMPLATE=tapd/cnb/codebuddy_code
TAPD_API_USER=<tapd api user>
TAPD_API_PASSWORD=<tapd api password>
TAPD_WORKSPACE_ID=<tapd workspace id>
CNB_TOKEN=<cnb token>
SOURCE_REPO_URL=https://cnb.cool/<org>/<team>/<repo>
CODEBUDDY_API_KEY=<codebuddy api key, only for initial credential login>
```

```bash
docker compose -f deploy/compose/compose.integration.yml --profile codebuddy up -d --build
```

If your CodeBuddy account needs the China or iOA environment, set `CODEBUDDY_INTERNET_ENVIRONMENT=internal` or `CODEBUDDY_INTERNET_ENVIRONMENT=ioa`. If your team uses a custom CodeBuddy API endpoint, also set `CODEBUDDY_BASE_URL`. For first-time managed credential login, still use [Appendix A](#appendix-a-advanced-credentials-and-local-workflow-files).

### 4. Start the Real Workflow Container

OpenCode path:

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode up -d --build
```

CodeBuddy Code path:

```bash
docker compose -f deploy/compose/compose.integration.yml --profile codebuddy up -d --build
```

Codex path:

```bash
docker compose -f deploy/compose/compose.integration.yml --profile codex up -d --build
```

Claude Code path:

```bash
docker compose -f deploy/compose/compose.integration.yml --profile claude-code up -d --build
```

Verify:

```bash
curl -fsS http://localhost:4000/healthz
docker compose -f deploy/compose/compose.integration.yml --profile opencode ps
docker compose -f deploy/compose/compose.integration.yml --profile opencode logs -f symphony-opencode
```

The following commands use the OpenCode profile as examples. For other paths, change the profile and service name accordingly, such as `codex` / `symphony-codex`, `claude-code` / `symphony-claude-code`, or `codebuddy` / `symphony-codebuddy`.

`/healthz` only means the HTTP server started. It does not prove tracker, repo provider, and agent provider credentials are valid. During first real integration, keep watching logs and confirm there are no missing variables, missing provider CLI, authentication failures, or permission errors.

Optionally run a read-only repo provider smoke test. It checks provider type and authentication state by default; it does not clone, push, or create PR/MR:

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode run --rm --no-deps symphony-opencode \
  repo-provider smoke --provider github --json
```

For CNB, change `github` to `cnb`:

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode run --rm --no-deps symphony-opencode \
  repo-provider smoke --provider cnb --json
```

Stop:

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode down
```

### 5. Real Workflow Success Criteria

After first real integration, confirm at least:

- `.env` sets the selected provider template variable to the real target template, not `memory/no_repo/mock`;
- the selected profile service is running/healthy, such as `symphony-opencode`, `symphony-codex`, `symphony-claude-code`, or `symphony-codebuddy`;
- `curl -fsS http://localhost:4000/healthz` returns `{"status":"ok"}`;
- logs show no missing variables, missing provider CLI, authentication failure, repository permission error, or model provider credential failure;
- the read-only repo provider smoke test passes, or you completed the equivalent smoke path in the [Newcomer End-to-End Run Guide](../../elixir/docs/quickstart/en.md);
- if the workflow uses `credential_ref`, startup logs show a passing managed credential preflight; this automatically initializes and verifies the credential before serving;
- Dashboard / `/api/v1/state` no longer only shows mock-only state such as `MEM-1`, `mock`, or `memory`; if the real tracker already has issues that match the workflow scan rules, you should see the corresponding issue or event.

If the real tracker does not yet have issues that match the workflow scan rules, the Dashboard may not show new issues. That is not necessarily a container error. Check tracker project, state transitions, labels/gates, and token permissions against the matching quickstart path first.

### 6. Real Workflow Risk Boundary

A real workflow is trusted runtime configuration and may:

- read and update Linear/TAPD issues;
- clone the target repository;
- create work branches;
- push branches;
- create or update PR/MR;
- write tracker comments;
- call Agent Providers and model APIs.

For first validation, use test projects, test repositories, and low-privilege tokens. Do not connect production trackers or production repositories directly.

## Images

The Dockerfile exposes layered runtime targets:

| Target | Purpose |
| --- | --- |
| `runtime-base` | Minimal OTP release runtime for mock/local validation. It does not include Mix or the Elixir toolchain. |
| `runtime-agent` | Provider-neutral OTP release runtime plus common agent/repository tools such as Node.js, `gh`, `ripgrep`, and Python. It intentionally does not install a concrete Agent Provider CLI. |
| `runtime-agent-opencode` | OpenCode-specific image built on `runtime-agent`; adds pinned `opencode-ai`. `compose.integration.yml --profile opencode` uses it. |
| `runtime-agent-codex` | Codex-specific image built on `runtime-agent`; adds pinned `@openai/codex`. `compose.integration.yml --profile codex` uses it. |
| `runtime-agent-claude-code` | Claude Code-specific image built on `runtime-agent`; adds pinned `@anthropic-ai/claude-code`. `compose.integration.yml --profile claude-code` uses it. |
| `runtime-agent-codebuddy` | CodeBuddy Code-specific image built on `runtime-agent`; adds pinned `@tencent-ai/codebuddy-code`. `compose.integration.yml --profile codebuddy` uses it. |

Do not add every supported provider CLI to `runtime-agent`. Provider CLIs have different installation sources, release cadences, authentication directories, and supply-chain risk profiles. Prefer one final target per provider, plus one explicit profile per provider in `compose.integration.yml`. This repository ships separate targets for OpenCode, Codex, Claude Code, and CodeBuddy Code; future providers should follow the same pattern with a separate target, a separate profile, and a separate version pin.

The release is built with `mix release symphony --overwrite` in the build stage, then copied into a Debian runtime image. Keep the build and runtime Debian families aligned because the release includes ERTS and depends on the libc ABI used by the build image.

The runtime image creates a stable non-root `symphony` user. The default UID/GID is `10001:10001`. If your runtime platform needs different volume ownership, override `SYMPHONY_UID` and `SYMPHONY_GID` as Docker build args.

Manual builds:

```bash
docker build -f docker/app/Dockerfile --target runtime-base -t symphony:quickstart .
docker build -f docker/app/Dockerfile --target runtime-agent -t symphony:agent-tools .
docker build -f docker/app/Dockerfile --target runtime-agent-opencode --build-arg OPENCODE_VERSION=1.14.33 -t symphony:agent-opencode .
docker build -f docker/app/Dockerfile --target runtime-agent-codex --build-arg CODEX_VERSION=0.135.0 -t symphony:agent-codex .
docker build -f docker/app/Dockerfile --target runtime-agent-claude-code --build-arg CLAUDE_CODE_VERSION=2.1.158 -t symphony:agent-claude-code .
docker build -f docker/app/Dockerfile --target runtime-agent-codebuddy --build-arg CODEBUDDY_VERSION=2.99.1 -t symphony:agent-codebuddy .
```

`OPENCODE_VERSION`, `CODEX_VERSION`, `CLAUDE_CODE_VERSION`, and `CODEBUDDY_VERSION` default in the build args in `docker/app/Dockerfile`. This guide uses `1.14.33`, `0.135.0`, `2.1.158`, and `2.99.1`; when updating provider CLI versions, check Dockerfile, `deploy/compose/compose.integration.yml`, `scripts/container-security-scan.sh`, `.github/workflows/container-security.yml`, and examples in this guide. Use `rg "OPENCODE_VERSION|CODEX_VERSION|CLAUDE_CODE_VERSION|CODEBUDDY_VERSION"` to avoid missing a reference.

For production-image digest pinning, Trivy/SBOM, and provenance requirements, see [Appendix B: Supply-Chain Checks](#appendix-b-supply-chain-checks). For the full environment variable reference, see [Appendix C: Environment Variable Reference](#appendix-c-environment-variable-reference).

## Maintainer Change Checklist

When changing container deployment behavior, check at least:

- `docker/app/Dockerfile`: image targets, base images, provider CLI installation, and build args;
- `deploy/compose/compose.quickstart.yml`: whether Mock Quickstart still starts without external credentials;
- `deploy/compose/compose.integration.yml`: profiles, environment variables, volume mounts, default template, and runtime target;
- `.env.example`: safe defaults, variable names, and comments match Compose;
- `scripts/container-security-scan.sh` and `.github/workflows/container-security.yml`: scan target, build args, trigger paths, and version pins;
- `docs/deployment/container.md` and `docs/deployment/container.zh-CN.md`: both languages describe the same runtime path;
- `elixir/docs/quickstart/en.md` and `elixir/docs/quickstart/zh-CN.md`: local quickstart workflow names, generated workflow file paths, and credential steps still match the container handoff path;
- Elixir entrypoint and tests: if you add `SYMPHONY_*` variables or change template/workflow precedence, add the matching release runner or CLI tests.

When updating provider CLI versions, base image digests, or provider CLI installation, use `rg "OPENCODE_VERSION|CODEX_VERSION|CLAUDE_CODE_VERSION|CODEBUDDY_VERSION|runtime-agent-|SYMPHONY_WORKFLOW_PATH"` to find related references.

## Runtime Controls

Quickstart Compose and integration profiles use:

- non-root `symphony` user from the image, default UID/GID `10001:10001`;
- Docker `init: true` for process reaping;
- `no-new-privileges:true`;
- `cap_drop: [ALL]`;
- `stop_grace_period: 30s`;
- image-level `HEALTHCHECK` against `http://127.0.0.1:4000/healthz`.

If a future provider CLI truly requires a Linux capability, document the reason and add back only the required capability instead of removing `cap_drop: [ALL]`.

## Volumes

| Volume | Container path | Purpose |
| --- | --- | --- |
| `symphony-workspaces` | `/workspaces` by default | Isolated issue/story workspaces. |
| `symphony-state` | `/app/.symphony` | Runtime state; Integration also stores managed credentials under `/app/.symphony/agent_credentials` by default. |
| `symphony-logs` | `/app/log` | Runtime logs. |

## Security Notes

- Do not bake secrets into the image.
- Do not commit real `.env` files.
- Use `.env`, Docker secrets, or read-only file mounts for credentials.
- The container runs as the non-root `symphony` user, default UID/GID `10001:10001`.
- Keep `SYMPHONY_WORKSPACE_ROOT` isolated from host developer directories.
- Review workflow templates before using real tracker, repository, or provider credentials.
- Templates that enable broad filesystem, repository, tracker, or provider permissions should only run in trusted environments.

## Cleanup

Stop quickstart:

```bash
docker compose -f deploy/compose/compose.quickstart.yml down
```

Remove quickstart volumes:

```bash
docker compose -f deploy/compose/compose.quickstart.yml down -v
```

Stop real integration containers:

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode down
```

To remove named volumes used by real integration:

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode down -v
```

Use `down -v` carefully. It deletes Docker volumes created by Compose, including workspaces, runtime state, and logs.

## Appendix A: Advanced Credentials and Local Workflow Files

Containers support two Agent Provider credential approaches. Choose one first; do not mix them accidentally.

| Approach | Best for | What to do |
| --- | --- | --- |
| Provider-owned config file | Built-in `linear/github/opencode` template, or a team-managed OpenCode config file | Enable the `OPENCODE_CONFIG` read-only mount on the `symphony-opencode` service in `compose.integration.yml`; the OpenCode CLI reads its own config |
| Maestro managed credential | Workflows containing `credential_ref`, such as `credential://opencode/zai`, `credential://codex/default`, `credential://claude_code/default`, or `credential://codebuddy_code/default` | Provide the matching API key in `.env`; `compose.integration.yml` runs login + verify preflight automatically before the service starts |

All `compose.integration.yml` integration profiles store managed credentials at:

```text
/app/.symphony/agent_credentials
```

This path is inside the `symphony-state` named volume, so credentials survive container rebuilds. Override it in `.env` if needed:

```env
SYMPHONY_AGENT_CREDENTIALS_STORE_ROOT=/app/.symphony/agent_credentials
SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT=auto
```

`SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT=auto` is the Integration Compose default. At container startup, Symphony resolves the active `SYMPHONY_TEMPLATE` or `SYMPHONY_WORKFLOW_PATH`; only workflows with `agent_provider.options.credential_ref` trigger managed credential handling. When the matching API key is present, preflight creates or updates the credential and then verifies it. When the API key is absent, preflight verifies the credential already persisted in the named volume. Workflows without `credential_ref` are skipped. Set it to `required` to fail when no `credential_ref` exists, or `off` to disable the startup preflight.

The built-in `tapd/cnb/codebuddy_code` template uses `credential://codebuddy_code/default` by default. On the first start with an empty credential store, set `CODEBUDDY_API_KEY` in `.env`; the container automatically writes and verifies this `default` credential before serving. After the credential is written to the `symphony-state` named volume, later restarts do not need to keep the API key in `.env`; preflight verifies the persisted credential. If your CodeBuddy account requires an internal or IOA environment, set:

```env
CODEBUDDY_INTERNET_ENVIRONMENT=internal
# or
# CODEBUDDY_INTERNET_ENVIRONMENT=ioa
```

The built-in `linear/github/opencode` template does not contain `credential_ref` by default, so it does not need managed credential preflight. Use OpenCode's own config file, OpenCode-readable environment variables, or your team's approved authentication method. If you switch to a local workflow with `credential://opencode/zai`, providing `ZAI_API_KEY` in `.env` is enough for startup preflight to log in and verify automatically. For non-ZAI OpenCode accounts, set `SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME` to the environment variable name that should be materialized for OpenCode.

The built-in `linear/github/codex` and `linear/github/claude_code` templates normally read provider tokens directly from the environment: Codex uses `OPENAI_API_KEY`, and Claude Code uses `CLAUDE_CODE_OAUTH_TOKEN`. If you switch to a local workflow with `credential://codex/default` or `credential://claude_code/default`, startup preflight can initialize and verify managed credentials through the same mechanism.

If you use a local workflow generated by the quickstart initialization script, and that workflow contains `credential_ref`, set this in `.env` first:

```env
SYMPHONY_WORKFLOW_PATH=/app/WORKFLOW.local.md
# OpenCode:
SYMPHONY_WORKFLOW_FILE=./elixir/quickstart/WORKFLOW.linear-github-opencode.local.md
# CodeBuddy Code:
# SYMPHONY_WORKFLOW_FILE=./elixir/quickstart/WORKFLOW.tapd-cnb-codebuddy.local.md
```

Then enable the matching read-only mount on the selected service in `deploy/compose/compose.integration.yml`: OpenCode uses `symphony-opencode`; Codex uses `symphony-codex`; Claude Code uses `symphony-claude-code`; CodeBuddy Code uses `symphony-codebuddy`.

```yaml
# - ${SYMPHONY_WORKFLOW_FILE:?set SYMPHONY_WORKFLOW_FILE to the selected provider workflow file}:/app/WORKFLOW.local.md:ro
```

When `SYMPHONY_WORKFLOW_PATH` is set, the container runs that workflow file first. Otherwise it uses `SYMPHONY_TEMPLATE`. The startup preflight and the service use the same resolved workflow, so credentials are written to the same store that runtime reads.

The normal path does not require manual account commands in this guide. If startup fails, check container logs for `Managed credential preflight failed`: for first initialization or credential rotation, set `CODEBUDDY_API_KEY`, `ZAI_API_KEY`, `OPENAI_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, or the variable referenced by the matching `SYMPHONY_*_TOKEN_ENV`, then run `docker compose up` again. If your CodeBuddy account requires an internal or IOA environment, set `CODEBUDDY_INTERNET_ENVIRONMENT=internal` or `CODEBUDDY_INTERNET_ENVIRONMENT=ioa` before restarting.

## Appendix B: Supply-Chain Checks

Run this before promoting production images locally or in CI:

```bash
scripts/container-security-scan.sh
```

The script builds `runtime-agent-opencode` by default, runs a Trivy `HIGH,CRITICAL` vulnerability gate, and outputs Trivy JSON plus Syft SPDX/CycloneDX SBOM files. Set `CONTAINER_SECURITY_TARGET` to scan another target such as `runtime-agent-codex`, `runtime-agent-claude-code`, or `runtime-agent-codebuddy`.

Common overrides:

```bash
CONTAINER_SECURITY_TARGET=runtime-base scripts/container-security-scan.sh
CONTAINER_SECURITY_TARGET=runtime-agent-codex scripts/container-security-scan.sh
CONTAINER_SECURITY_TARGET=runtime-agent-claude-code scripts/container-security-scan.sh
CONTAINER_SECURITY_TARGET=runtime-agent-codebuddy scripts/container-security-scan.sh
CONTAINER_SECURITY_IMAGE=registry.example.com/symphony:candidate scripts/container-security-scan.sh
TRIVY_SEVERITY=CRITICAL scripts/container-security-scan.sh
```

Pull requests that touch Docker, Compose, Elixir release, or container deployment docs trigger `.github/workflows/container-security.yml`, which builds `runtime-base`, `runtime-agent`, `runtime-agent-opencode`, `runtime-agent-codex`, `runtime-agent-claude-code`, and `runtime-agent-codebuddy`, runs Trivy, and uploads SBOM artifacts.

Strict production CI should use digest-pinned base images:

```bash
docker build -f docker/app/Dockerfile \
  --target runtime-agent-opencode \
  --build-arg ELIXIR_IMAGE='elixir:1.19.5-otp-28-slim@sha256:...' \
  --build-arg RUNTIME_IMAGE='debian:trixie-slim@sha256:...' \
  --build-arg OPENCODE_VERSION=1.14.33 \
  --build-arg CODEX_VERSION=0.135.0 \
  --build-arg CLAUDE_CODE_VERSION=2.1.158 \
  --build-arg CODEBUDDY_VERSION=2.99.1 \
  --build-arg SYMPHONY_UID=10001 \
  --build-arg SYMPHONY_GID=10001 \
  -t symphony:agent-opencode .
```

Production CI should also require:

- `ELIXIR_IMAGE` and `RUNTIME_IMAGE` use digest pinning;
- retaining `trivy-image.json`, `sbom.spdx.json`, and `sbom.cyclonedx.json` artifacts;
- signing images and recording provenance after the scan passes, for example with Cosign/Sigstore;
- continuous vulnerability monitoring in the image registry.

## Appendix C: Environment Variable Reference

### Minimal Variables by Template

| Template | Scenario | Minimal variables |
| --- | --- | --- |
| `memory/no_repo/mock` | Mock Quickstart / local validation | No external credentials; Quickstart Compose sets `SYMPHONY_TEMPLATE=memory/no_repo/mock` |
| `linear/github/opencode` | Linear + GitHub + OpenCode | `SYMPHONY_OPENCODE_TEMPLATE` or `SYMPHONY_WORKFLOW_PATH`, `LINEAR_API_KEY`, `LINEAR_PROJECT_SLUG`, `SOURCE_REPO_URL`, `SOURCE_REPO_BASE_BRANCH`, `GH_TOKEN` or `GITHUB_TOKEN`; OpenCode credentials use `OPENCODE_CONFIG`, OpenCode-readable environment variables, or a workflow with `credential_ref` + `ZAI_API_KEY` automatic preflight; `SOURCE_REPO_PROVIDER_REPOSITORY` is recommended |
| `linear/github/codex` | Linear + GitHub + Codex | `SYMPHONY_CODEX_TEMPLATE` or `SYMPHONY_WORKFLOW_PATH`, `LINEAR_API_KEY`, `LINEAR_PROJECT_SLUG`, `SOURCE_REPO_URL`, `SOURCE_REPO_BASE_BRANCH`, `GH_TOKEN` or `GITHUB_TOKEN`, `OPENAI_API_KEY`; use `compose.integration.yml --profile codex` / `runtime-agent-codex` |
| `linear/github/claude_code` | Linear + GitHub + Claude Code | `SYMPHONY_CLAUDE_CODE_TEMPLATE` or `SYMPHONY_WORKFLOW_PATH`, `LINEAR_API_KEY`, `LINEAR_PROJECT_SLUG`, `SOURCE_REPO_URL`, `SOURCE_REPO_BASE_BRANCH`, `GH_TOKEN` or `GITHUB_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`; use `compose.integration.yml --profile claude-code` / `runtime-agent-claude-code` |
| `tapd/cnb/codebuddy_code` | TAPD + CNB + CodeBuddy Code | `SYMPHONY_CODEBUDDY_TEMPLATE` or `SYMPHONY_WORKFLOW_PATH`, `TAPD_API_USER`, `TAPD_API_PASSWORD`, `TAPD_WORKSPACE_ID`, `CNB_TOKEN`, `SOURCE_REPO_URL`, `CODEBUDDY_API_KEY`; use `compose.integration.yml --profile codebuddy` / `runtime-agent-codebuddy`; managed credential preflight runs automatically by default |

### Common Variables

| Variable | Required | Description |
| --- | --- | --- |
| `SYMPHONY_PORT` | Optional for Integration | Dashboard host port. `compose.integration.yml` profiles default to `4000`. Quickstart Compose fixes `4000:4000`. |
| `PORT` | Usually not set manually | Application listen port inside the container. Compose sets `4000`. The image `HEALTHCHECK` also uses it. |
| `HOST` | Usually not set manually | Application listen address inside the container. Compose sets `0.0.0.0` so the host can reach the service. |
| `SYMPHONY_OPENCODE_TEMPLATE` | Required for OpenCode profile | Workflow template alias for the OpenCode profile, defaulting to `linear/github/opencode`. Compose maps it to `SYMPHONY_TEMPLATE` inside the container. |
| `SYMPHONY_CODEX_TEMPLATE` | Required for Codex profile | Workflow template alias for the Codex profile, defaulting to `linear/github/codex`. Compose maps it to `SYMPHONY_TEMPLATE` inside the container. |
| `SYMPHONY_CLAUDE_CODE_TEMPLATE` | Required for Claude Code profile | Workflow template alias for the Claude Code profile, defaulting to `linear/github/claude_code`. Compose maps it to `SYMPHONY_TEMPLATE` inside the container. |
| `SYMPHONY_CODEBUDDY_TEMPLATE` | Required for CodeBuddy profile | Workflow template alias for the CodeBuddy profile, defaulting to `tapd/cnb/codebuddy_code`. Compose maps it to `SYMPHONY_TEMPLATE` inside the container. |
| `SYMPHONY_TEMPLATE` | Usually not set directly | Runtime workflow template variable read inside the container. Integration profiles derive it from provider-specific variables; setting one global `SYMPHONY_TEMPLATE` directly can cause profile/template mismatches. |
| `SYMPHONY_WORKFLOW_PATH` | Optional | Container path to a workflow file. When set, it takes precedence over `SYMPHONY_TEMPLATE`, for example `/app/WORKFLOW.local.md`. |
| `SYMPHONY_WORKFLOW_FILE` | Optional | Host path to the workflow file, used for the read-only mount into `SYMPHONY_WORKFLOW_PATH`. |
| `SYMPHONY_WORKSPACE_ROOT` | Recommended | Workspace root inside the container. Defaults to `/workspaces`. |
| `SYMPHONY_AGENT_CREDENTIALS_STORE_ROOT` | Recommended | Managed credential store path. Integration Compose defaults to `/app/.symphony/agent_credentials`. |
| `SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT` | Recommended | Integration Compose defaults to `auto`. When the workflow has `credential_ref`, startup creates/updates and verifies managed credentials; without an API key, it verifies the persisted credential. Set to `off` or `required` when needed. |
| `SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT_VERIFY_MODE` | Optional | Defaults to `auth`, which runs a minimal non-interactive provider probe after credential login and may make a small provider API/model call. Set to `command` to only run the provider command-level check. |
| `SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT_VERIFY_PROMPT` | Optional | Prompt used by the `auth` preflight probe. Defaults to `Reply with exactly OK.` |
| `SYMPHONY_AGENT_CREDENTIAL_ACCOUNT_ID` | Optional | Account id to initialize when the workflow uses a credential pool reference instead of a concrete account id. Normal `credential://provider/id` refs do not need this. |

### Tracker Credentials

| Variable | Used by |
| --- | --- |
| `LINEAR_API_KEY` | Linear templates |
| `LINEAR_PROJECT_SLUG` | Linear templates |
| `TAPD_API_USER` | TAPD templates |
| `TAPD_API_PASSWORD` | TAPD templates |
| `TAPD_WORKSPACE_ID` | TAPD templates |
| `TAPD_COMMENT_AUTHOR` | Optional TAPD comment author override. |
| `TAPD_WORKITEM_TYPE_ID` | Optional TAPD Story/workitem type filter used by TAPD workflow preparation. |

### Repository Inputs

| Variable | Description |
| --- | --- |
| `SOURCE_REPO_URL` | Target repository clone URL. |
| `SOURCE_REPO_BASE_BRANCH` | Base branch, usually `main`. |
| `SOURCE_REPO_BRANCH_WORK_PREFIX` | Optional work branch prefix; the quickstart examples use `maestro/`. |
| `SOURCE_REPO_PROVIDER_REPOSITORY` | Optional explicit provider repository name, such as GitHub `<owner>/<repo>`. |
| `SOURCE_REPO_PROVIDER_REQUIRED_PR_LABEL` | Optional GitHub PR label enforcement. |
| `GH_TOKEN` | GitHub token. Use either `GH_TOKEN` or `GITHUB_TOKEN`; setting only one avoids confusion. |
| `GITHUB_TOKEN` | GitHub token. Use either `GH_TOKEN` or `GITHUB_TOKEN`; setting only one avoids confusion. |
| `CNB_TOKEN` | CNB token. |
| `CNB_GIT_USER_NAME` | Optional Git author name configured in CNB workspaces. |
| `CNB_GIT_USER_EMAIL` | Optional Git author email configured in CNB workspaces. |

### Provider Credentials and Build Variables

| Variable | Description |
| --- | --- |
| `ZAI_API_KEY` | ZAI token startup preflight can read when using `credential://opencode/zai` managed credentials. Required for first write or rotation. |
| `SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME` | Optional OpenCode managed credential override. By default Symphony infers from account id: `zai` -> `ZAI_API_KEY`, `openrouter` -> `OPENROUTER_API_KEY`, `anthropic` -> `ANTHROPIC_API_KEY`, `google` / `gemini` -> `GOOGLE_GENERATIVE_AI_API_KEY`. |
| `SYMPHONY_OPENCODE_TOKEN_ENV` | Optional OpenCode managed credential override. By default preflight reads the token from the same environment variable named by `SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME`. Unknown OpenCode account ids still require `SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME`. |
| `CODEBUDDY_API_KEY` | CodeBuddy Code API key startup preflight can read when using `credential://codebuddy_code/default`. Required for first write or rotation. |
| `SYMPHONY_CODEBUDDY_TOKEN_ENV` | Optional CodeBuddy managed credential override. Defaults to `CODEBUDDY_API_KEY`. |
| `CODEBUDDY_INTERNET_ENVIRONMENT` | Optional CodeBuddy Code network environment. China deployments commonly use `internal`; iOA uses `ioa`; leave it empty for the default/overseas path. |
| `CODEBUDDY_BASE_URL` | Optional custom CodeBuddy Code API endpoint. Most deployments do not need it. |
| `CODEBUDDY_CONFIG_DIR` | CodeBuddy Code configuration directory. `runtime-agent-codebuddy` defaults to `/home/symphony/.codebuddy`, and Compose persists it with a named volume. |
| `OPENAI_API_KEY` | Codex API key startup preflight can read when using `credential://codex/default`. Required for first write or rotation. |
| `SYMPHONY_CODEX_TOKEN_ENV` | Optional Codex managed credential override. Defaults to `OPENAI_API_KEY`. |
| `SYMPHONY_CODEX_VERIFY_COMMAND` | Optional Codex verify command override. Defaults to `codex`. |
| `CODEX_HOME` | Codex configuration directory. `runtime-agent-codex` defaults to `/home/symphony/.codex`, and Compose persists it with a named volume. |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code OAuth token startup preflight can read when using `credential://claude_code/default`. Claude Code managed credentials use this token form, not `ANTHROPIC_API_KEY`. |
| `SYMPHONY_CLAUDE_CODE_TOKEN_ENV` | Optional Claude Code managed credential override. Defaults to `CLAUDE_CODE_OAUTH_TOKEN`. |
| `SYMPHONY_CLAUDE_CODE_VERIFY_COMMAND` | Optional Claude Code verify command override. Defaults to `claude`. |
| `CLAUDE_CONFIG_DIR` | Claude Code configuration directory. `runtime-agent-claude-code` defaults to `/home/symphony/.claude`, and Compose persists it with a named volume. |
| `ANTHROPIC_API_KEY` | Optional when an OpenCode managed credential or selected provider uses Anthropic-compatible API access. |
| `OPENROUTER_API_KEY` | Optional when an OpenCode managed credential uses OpenRouter. |
| `GOOGLE_GENERATIVE_AI_API_KEY` | Optional when an OpenCode managed credential uses Google Gemini. |
| `OPENCODE_CONFIG` | Optional local file path mounted to `/home/symphony/.config/opencode/opencode.json`. |
| `SSH_PRIVATE_KEY` | Optional local SSH private key path mounted to `/home/symphony/.ssh/id_rsa`. |
| `OPENCODE_VERSION` | OpenCode CLI version used when building `runtime-agent-opencode`; default is defined in `docker/app/Dockerfile`. |
| `CODEX_VERSION` | Codex CLI version used when building `runtime-agent-codex`; default is defined in `docker/app/Dockerfile`. |
| `CLAUDE_CODE_VERSION` | Claude Code CLI version used when building `runtime-agent-claude-code`; default is defined in `docker/app/Dockerfile`. |
| `CODEBUDDY_VERSION` | CodeBuddy Code CLI version used when building `runtime-agent-codebuddy`; default is defined in `docker/app/Dockerfile`. |

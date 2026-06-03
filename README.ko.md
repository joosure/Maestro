# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-platformizing-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Português (Brasil)](./README.pt-BR.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Русский](./README.ru.md) | [Bahasa Indonesia](./README.id.md)

## 엔터프라이즈 엔지니어링을 위한 AI Agent 오케스트레이션 및 거버넌스 플랫폼.

Maestro는 engineering team을 위한 AI Agent 오케스트레이션 및 거버넌스 플랫폼입니다. Issue trackers, requirements, repositories, Agent Providers, runtime environments, tool integrations, delivery evidence를 연결해 Codex, Claude Code, CodeBuddy Code, OpenCode, 미래의 Coding Agents가 실제 project work를 맡고, 실행하고, 변경을 제출하고, audit 가능한 evidence를 남길 수 있게 합니다.

또 하나의 coding agent가 아닙니다.

Codex, Claude Code, CodeBuddy Code, OpenCode, 그리고 미래의 agent가 실제 project system, repository, workflow, 운영 제약 안에서 일할 수 있게 합니다.

> **Symphony는 이 패턴을 증명했습니다. Maestro는 그 플랫폼을 만듭니다.**

---

## 컨테이너 Quick Start

외부 credentials 없이 local memory/mock workflow를 실행합니다:

```bash
docker compose -f deploy/compose/compose.quickstart.yml up --build
```

Dashboard는 `http://localhost:4000`에서 열 수 있습니다.

전체 container mock quickstart, real workflow container integration, volumes, credential handling은 [`docs/deployment/container.md`](./docs/deployment/container.md)를 참고하세요.

---

## 왜 Maestro인가

OpenAI Symphony는 강력한 아이디어를 제시했습니다. **agent session이 아니라 work를 관리한다**는 것입니다.

엔지니어가 coding agent chat을 하나씩 감독하는 대신, Symphony는 Linear 같은 project-management system이 autonomous coding work의 진입점이 될 수 있음을 보여주었습니다.

Maestro는 이 패턴을 더 확장합니다.

원래의 `Linear + Codex` reference implementation을 현대 engineering workflow를 위한 **tracker-driven, provider-neutral AI Agent 오케스트레이션 및 거버넌스 플랫폼**으로 일반화합니다.

실제로 Maestro는 팀이 다음 상태에서:

```text
human-managed agent chats
```

다음 상태로 이동하도록 돕습니다:

```text
tracker-driven agent operations
```

이 차이는 중요합니다. Demo는 agent 하나, issue 하나, repository 하나로 성공할 수 있습니다. Production team에는 scheduling, isolation, credential control, quota awareness, evidence, logs, reviews, state transitions, failure recovery가 필요합니다.

Maestro는 그 두 번째 세계를 위해 만들어졌습니다.

---

## Maestro가 하는 일

Maestro는 agentic engineering task의 전체 lifecycle을 조율합니다:

```text
Work Item
  Ticket / Story / Issue
        ↓
Workflow Policy
  WORKFLOW.md / Profile / Route Policy / Capabilities
        ↓
Control Plane
  Orchestrator / Dispatch / Retry / Reconciliation
        ↓
Execution Runtime
  Agent Runner / Workspace / Local / SSH / Worker Daemon
        ↓
Provider & Tool Integration
  Agent Provider / Dynamic Tool Bridge / Repo Provider
        ↓
Delivery & Evidence
  Diff / PR / Review / CI / Tracker Update / Audit Trail
```

Work system, agent provider, code platform, runtime environment, observability를 하나의 operating layer로 연결합니다.

| Capability Area | Maestro가 제공하는 것 |
| --- | --- |
| Tracker | Linear, TAPD, Memory, 그리고 Jira, YouTrack, Feishu Project, GitHub Issues 등으로 확장 가능한 adapter |
| Agent Provider | Codex, Claude Code, CodeBuddy Code, OpenCode, 그리고 미래 CLI 또는 remote agent provider |
| Repo | clone, branch, commit, diff, push 같은 provider-neutral Git operations |
| Repo Provider | GitHub, CNB, Memory, 그리고 GitLab, Gitea, Bitbucket, Gerrit 지원 확장 |
| Workflow | coding delivery, requirement analysis, refinement, review routing, triage를 위한 재사용 가능한 profile |
| Runtime | Local, SSH, Worker Daemon execution modes |
| Tool Bridge | agent에게 노출되는 provider-neutral dynamic tools |
| Governance | accounts, credential store, lease, quota polling, redaction, human gates |
| Observability | structured events, JSON logs, event store, dashboard drilldown, production evidence |

---

## Maestro가 해결하는 문제

Coding agent는 강력해지고 있습니다. 하지만 강력한 agent가 곧 신뢰할 수 있는 engineering system이 되는 것은 아닙니다.

| Maestro 없음 | Maestro 사용 |
| --- | --- |
| Agent work가 고립된 chat session에서 발생 | 실제 tracker에서 dispatch되고 실제 issue에 연결 |
| Provider마다 session model이 다름 | provider가 shared lifecycle contract 뒤에 래핑됨 |
| Agent output을 audit하기 어려움 | diff, PR, tool call, log, state transition, evidence가 캡처됨 |
| 팀이 하나의 tracker나 code platform에 묶임 | tracker와 repo provider가 adapter-based |
| Workflow가 script에 hardcode됨 | Workflow Profile이 policy, state, routing, deliverables를 정의 |
| Credential과 quota가 ad hoc | accounts, leases, quota polling, redaction이 platform concern이 됨 |
| scale하려면 session을 수동 감독해야 함 | Worker Daemon이 capacity-aware execution과 operational control을 제공 |

Maestro의 thesis는 단순합니다:

> **미래는 하나의 완벽한 coding agent가 아닙니다. 미래는 실제 engineering workflow 전반에서 여러 agent를 schedule, observe, govern할 수 있는 operating layer입니다.**

---

## Core Design Principles

### 1. Trackers are the dispatch surface

팀은 이미 project-management system 위에서 일합니다. Maestro는 work를 private queue에 숨기지 않습니다. Linear, TAPD, Memory, 미래 tracker를 autonomous work의 dispatch surface로 만듭니다.

### 2. Agents are execution units

Codex, Claude Code, CodeBuddy Code, OpenCode, 미래 agent는 replaceable provider로 다뤄집니다. Maestro는 orchestration layer가 필요로 하는 lifecycle, 즉 session creation, turn execution, tool-call capture, evidence collection, quota awareness, cleanup을 표준화합니다.

### 3. Workflow Profiles encode business intent

Coding, requirement analysis, refinement, review routing, triage는 서로 다른 workflow입니다. Maestro는 profile을 first-class로 만들어 언제 dispatch할지, wait할지, stop할지, 어떤 evidence가 필요한지, 언제 human takeover가 필요한지 정의하게 합니다.

### 4. Evidence beats claims

"Done"만으로는 부족합니다. Maestro는 branch, commit, diff, PR, review note, CI result, tracker comment, tool call, event, log 같은 감사 가능한 artifacts를 중시합니다.

### 5. Adapters prevent platform lock-in

모든 외부 system은 contract를 통해 들어옵니다. Orchestrator는 특정 provider에 묶인 branch logic의 집합이 되어서는 안 됩니다. 새로운 integration은 adapters, contract tests, smoke tests, explicit capability discovery를 통해 들어와야 합니다.

---

## Architecture

Maestro는 engineering orchestration and governance architecture로 이해하는 것이 가장 명확합니다. Orchestrator는 scheduling state를 소유하고, workflow policy는 business meaning을 소유하며, providers는 명시적인 contracts를 통해 들어옵니다. Governance와 evidence는 전체 run을 가로지르는 cross-cutting layer입니다.

```text
+----------------------------------------------------------------------------+
| Governance                                                                 |
| Credential / Lease / Quota / Redaction / Approval Policy                   |
+----------------------------------------------------------------------------+
                                      |
                               governs / constrains
                                      v
+============================================================================+
| Core Execution Pipeline                                                    |
|                                                                            |
| +-------------+    +-----------------+    +------------------+             |
| | Work Source | -> | Workflow Policy | -> | Control Plane    |             |
| | Tracker     |    | WORKFLOW.md     |    | Orchestrator     |             |
| | Issue       |    | Profile         |    | Dispatch / Retry |             |
| | Story       |    | Route Policy    |    | Reconciliation   |             |
| | Ticket      |    | Capabilities    |    | State Tracking   |             |
| +-------------+    +-----------------+    +------------------+             |
|                                                   |                        |
|                                                   v                        |
|                                         +---------------------+            |
|                                         | Execution Runtime   |            |
|                                         | Agent Runner        |            |
|                                         | Workspace           |            |
|                                         | local / ssh / daemon|            |
|                                         | Session Lifecycle   |            |
|                                         +---------------------+            |
|                                                   |                        |
|                                                   v                        |
| +---------------------+              +-----------------------------+       |
| | Agent Provider      | <----------> | Provider & Tool Integration |       |
| | Codex               |              | Dynamic Tool Bridge         |       |
| | Claude Code         |              | Tracker Adapter             |       |
| | CodeBuddy Code      |              | Repo Facade                 |       |
| | OpenCode            |              | Repo Provider               |       |
| | Mock                |              +-----------------------------+       |
| +---------------------+                                                    |
+============================================================================+
                                      |
                                  emits / records
                                      v
+----------------------------------------------------------------------------+
| Evidence & Observability                                                   |
| Events / JSON Logs / Diff / PR / CI / Audit Trail / Dashboard              |
+----------------------------------------------------------------------------+
```

### 핵심 아키텍처 레이어

Maestro의 platform architecture는 여덟 개 layer로 요약할 수 있습니다. 처음 여섯 개는 main execution path이고, governance와 evidence는 control 및 audit을 위한 cross-cutting layer입니다.

| Layer | Components | Responsibility |
| --- | --- | --- |
| Work Source Layer | Tracker / Issue / Story / Ticket | work가 system에 들어오는 위치를 정의 |
| Workflow Policy Layer | `WORKFLOW.md` / Workflow Profile / Route Policy / Capabilities / Human Gate Declarations | team이 agent work를 어떻게 진행할지 정의 |
| Control Plane Layer | Orchestrator / Scheduler / Dispatch / Retry / Reconciliation / State Tracking | work 실행, retry, stop, reconcile 시점을 결정 |
| Execution Runtime Layer | Agent Runner / Workspace / Runtime / Local / SSH / Worker Daemon / Session Lifecycle | 각 work item을 격리된 execution boundary 안에서 실행 |
| Agent Provider Layer | Codex / Claude Code / CodeBuddy Code / OpenCode / Mock / Future Agent Providers | replaceable agent implementations를 shared lifecycle 뒤에 둠 |
| Provider & Tool Integration Layer | Dynamic Tool Bridge / Tracker Adapter / Repo Facade / Repo Provider | external systems를 provider-neutral contracts로 연결 |
| Governance Layer | Credential / Lease / Quota / Redaction / Approval / Policy Enforcement | access, capacity, approvals, safety posture를 제어 |
| Evidence & Observability Layer | Events / JSON Logs / Diff / PR / CI / Evidence / Audit Trail / Dashboard | 무엇이, 왜 일어났고 결과가 신뢰 가능한지 기록 |

### Primary Boundaries

| Boundary | Responsibility |
| --- | --- |
| `Workflow File` | YAML front matter로 runtime configuration을 제공하고 Markdown body로 Agent prompt를 제공 |
| `Workflow Profile` | route policy, capabilities, completion contract, stop conditions, human gates 정의 |
| `Tracker Adapter` | candidate work items 읽기, state 동기화, comments 작성, tracker typed tools 노출 |
| `Orchestrator` | polling, reconciliation, scheduling, retry, runtime state tracking, terminal cleanup |
| `Agent Runner` | 단일 work item의 workspace를 만들고 hooks를 실행하며 Agent session을 시작하고 구동 |
| `Workspace` | 각 work item의 runtime directory, workspace automation, repository copy, local evidence 격리 |
| `Agent Provider` | Codex / Claude Code / CodeBuddy Code / OpenCode / Mock session start, drive, stream, stop, cleanup |
| `Agent Runtime` | provider process를 local, SSH, Worker Daemon에 배치하고 sandbox / executor context 해석 |
| `Repo` | provider-neutral local Git operations: clone, branch, commit, diff, push |
| `Repo Provider` | GitHub, CNB, Memory 등의 code platform capabilities: PR / MR, reviews, checks, merge, comments, status updates |
| `Dynamic Tool Bridge` | Tracker, Repo, Repo Provider capabilities를 session-scoped provider-neutral tools로 집계 |
| `Observability` | structured events, JSON logs, event store, redaction, dashboard, evidence, audit trail |

---

## Workflow Profiles

Maestro는 "issue에서 code 작성"에만 제한되지 않습니다. 같은 platform layer로 여러 engineering workflow를 orchestrate할 수 있습니다.

| Profile | Purpose | Typical Evidence |
| --- | --- | --- |
| `coding_pr_delivery` | work item을 code changes와 PR로 변환 | branch, commit, diff, PR, CI result, review note |
| `requirement_analysis` | requirement를 structured analysis로 변환 | scope, risks, impact, acceptance criteria, task breakdown |
| `requirement_refinement` | implementation 전에 ambiguity 식별 | clarification questions, blockers, assumptions, refined acceptance criteria |
| `review_routing` | review를 적절한 사람 또는 agent로 route | reviewer suggestions, risk tags, checklist |
| `triage` | work item 분류 및 route | priority, owner, type, risk, next state |

이 지점에서 Maestro는 automation script 이상의 것이 됩니다. Profile은 agent가 무엇을 해야 하는지, 무엇을 하면 안 되는지, 어떤 evidence를 만들어야 하는지, 언제 human에게 넘겨야 하는지에 대한 operational definition입니다.

---

## Example Configuration Shape

현재 구현은 workflow Markdown file의 YAML front matter로 runtime configuration을 설정하고, Markdown body를 Agent prompt로 사용합니다. 아래는 현재 field 위치를 보여주는 shape example이며 완전한 runnable configuration은 아닙니다:

```yaml
workflow:
  profile:
    kind: coding_pr_delivery  # coding_pr_delivery | requirement_analysis | requirement_refinement | review_routing | triage
tracker:
  kind: linear                # linear | tapd | memory
repo:
  provider:
    kind: github              # github | cnb | memory
agent_provider:
  kind: codex                 # codex | claude_code | codebuddy_code | opencode | mock
agent_runtime:
  placement: local            # local | ssh | worker_daemon
```

Agent provider kind values는 canonical runtime strings입니다. 현재 built-ins는 `codex`, `claude_code`, `codebuddy_code`, `opencode`, `mock`입니다. Supported aliases는 registry lookup 전에 Elixir provider-kind owner가 normalize합니다.

Canonical tracker, repo-provider, agent-provider kind strings는 Elixir의 `Tracker.Kinds`, `RepoProvider.Kinds`, `AgentProvider.Kinds` modules가 소유하여 registries, defaults, documentation이 일관되게 유지되도록 합니다.

Production deployment는 이 차원들을 독립적으로 조합할 수 있습니다. 예:

```text
TAPD + CodeBuddy Code + CNB + Worker Daemon + requirement_analysis
Linear + Codex + GitHub + Local Runtime + coding_pr_delivery
Memory + Mock Agent + Memory Repo Provider + Contract Tests
```

---

## Quick Start

Maestro를 처음 실행한다면 먼저 [Newcomer End-to-End Run Guide](./elixir/docs/quickstart/en.md)를 확인하세요. 이 가이드는 로컬 `memory/no_repo/mock`, 실제 `TAPD + CNB + CodeBuddy Code`, 실제 `Linear + GitHub + OpenCode` workflow 경로를 다룹니다.

Repository를 clone합니다:

```bash
git clone https://github.com/joosure/Maestro.git
cd Maestro
```

먼저 repository에 고정된 Erlang / Elixir toolchain을 준비하세요. `mise` 사용을 권장하며, version은 `elixir/mise.toml`에 고정되어 있습니다:

```bash
cd elixir
mise trust
mise install
cd ..
```

의존성을 설치하고 test suite를 실행합니다. 현재 shell에 `mise` toolchain이 활성화되어 있으면 `make`를 직접 사용할 수 있습니다:

```bash
make -C elixir deps
make -C elixir test
```

`elixir/`에서 `mise exec -- mix setup`과 `mise exec -- mix test`를 실행할 수도 있습니다.

### Workflow template 실행해 보기

CLI를 build하고 `elixir/`에서 로컬 memory/mock workflow를 시작합니다:

```bash
cd elixir
make build
mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

이 명령은 `memory/no_repo/mock` template으로 service를 시작하고 선택적 dashboard/API를 `http://localhost:4000`에 노출합니다. Memory tracker, memory repo provider, mock agent provider를 사용하므로 Linear, GitHub, Codex, Claude Code, CodeBuddy Code, OpenCode, CNB credentials가 필요 없습니다.

실제 tracker, repository, agent runtime에 연결하려면 필요한 credentials를 먼저 설정한 뒤 template을 바꾸세요:

```bash
export LINEAR_API_KEY=...
export LINEAR_PROJECT_SLUG=...
export SOURCE_REPO_URL=https://github.com/owner/repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=owner/repo
export ZAI_API_KEY=...

command -v opencode
gh auth status

./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template linear/github/opencode \
  --port 4000
```

`SOURCE_REPO_BRANCH_WORK_PREFIX`와 `SOURCE_REPO_PROVIDER_REQUIRED_PR_LABEL`은 optional입니다. `SYMPHONY_WORKSPACE_ROOT`는 local quick start에서는 생략할 수 있습니다. real tracker, real repository 또는 full-flow validation에 연결하기 전에는 isolated workspace root로 명시적으로 설정하는 것이 좋습니다. 이렇게 하면 workspace가 local developer path에 생성되어 cleanup하기 어려워지는 일을 피할 수 있습니다. Real tracker나 repository에 연결하기 전에 [workflow template aliases](./elixir/priv/workflow_templates/README.md)와 [runtime configuration](./elixir/README.md)을 확인하세요.

Pull request를 열기 전에 CI와 같은 local gates를 실행하세요:

```bash
make -C elixir all
make -C elixir secret-scan
```

`make -C elixir secret-scan`은 `scripts/secret-scan.sh`를 통해 `gitleaks`,
`trufflehog`, `detect-secrets`를 실행합니다. CI도 `main` push와 pull requests에서 같은 gate를 실행합니다.

Local experimentation은 낮은 위험 경로부터 진행하세요:

- 외부 credentials 없이 orchestration을 검증하려면 `tracker.kind: memory`와 `repo.provider.kind: memory`를 설정하세요.
- fake 또는 simulated agent adapter는 adapter registry를 통해 tests나 extension work에서만 사용하세요. 내장 agent providers는 `codex`, `claude_code`, `codebuddy_code`, `opencode`입니다.
- memory path가 안정된 뒤 Linear/TAPD, GitHub/CNB 또는 destructive smoke tests로 이동하세요.

> 공개 브랜드는 **Maestro**를 사용합니다. 초기 버전에는 `symphony`에서 상속된 module names, CLI entrypoints, environment variables가 남아 있을 수 있습니다. Project branding과 platform boundaries가 안정될 때까지 compatibility names로 취급하세요.

---

## Extension Model

Maestro는 hardcoded branch가 아니라 contract를 통해 성장하도록 설계되었습니다.

### Add a Tracker Adapter

다음 tracker contract를 구현합니다:

- candidate work items listing;
- title, description, labels, state, owner, metadata reading;
- work claiming 또는 locking;
- comments와 evidence writing;
- 특정 provider의 states를 Maestro workflow model로 mapping;
- contract tests와 live smoke tests 통과.

### Add an Agent Provider

다음 provider contract를 구현합니다:

- session creation;
- prompt and context injection;
- turn execution;
- streaming events;
- tool-call capture;
- evidence extraction;
- cancellation and cleanup;
- sandbox, tools, approval, quota, context window 같은 capability reporting.

### Add a Repo Provider

다음 repo-provider contract를 구현합니다:

- PR / MR creation;
- review comments;
- checks and statuses;
- merge gates;
- branch protection detection;
- evidence links;
- idempotent updates.

### Add a Workflow Profile

정의할 항목:

- trigger states;
- dispatch policy;
- input context;
- agent instructions;
- allowed tools;
- required evidence;
- stop conditions;
- human approval gates;
- tracker transitions.

---

## Observability and Evidence

Maestro는 observability를 사후 보완이 아니라 제품의 일부로 취급합니다.

각 run은 다음을 통해 설명 가능해야 합니다:

- dispatch decision;
- workflow profile;
- selected provider;
- runtime and worker;
- session and turn history;
- tool calls;
- stdout / stderr / structured event stream;
- workspace and repository changes;
- PR or review artifacts;
- tracker comments and state changes;
- redacted logs;
- final evidence summary.

이로써 Maestro는 automation뿐 아니라 evaluation, debugging, governance, production rollout에도 유용해집니다.

---

## Project Status

Maestro는 active platformization 단계입니다.

적합한 용도:

- tracker-driven agent orchestration 연구;
- adapter prototypes 구축;
- workflow profiles 검증;
- memory-provider 또는 local test loops 실행;
- controlled environments에서 real providers 실험.

다음 전에 hardening이 필요합니다:

- unrestricted production execution;
- destructive repository operations;
- high-privilege credentials;
- multi-tenant worker pools;
- unattended merge or deploy automation.

Guiding rule:

> **대담하게 자동화하고, 신중하게 gate하며, evidence를 보존하세요.**

---

## Who Maestro Is For

Maestro는 다음 사용자에게 유용합니다:

- Codex, Claude Code, CodeBuddy Code, OpenCode, 미래 coding agents를 평가하는 engineering teams;
- internal AI engineering infrastructure를 구축하는 platform teams;
- agent operations workflows를 만드는 DevTools teams;
- 기존 trackers에서 agent가 일하길 원하는 product and engineering organizations;
- agent reliability, evidence, orchestration을 연구하는 researchers;
- structured agent-driven contribution flows를 원하는 open-source maintainers.

---

## Attribution

Maestro는 [OpenAI Symphony](https://github.com/openai/symphony)의 fork에서 시작했습니다. 원래 Symphony reference implementation은 Linear-driven Codex orchestration에 초점을 둡니다. Maestro는 이 아이디어를 trackers, agent providers, repository providers, workflow profiles, runtimes, tools, evidence 전반의 broader platform architecture로 확장합니다.

---

## Repository

- GitHub: <https://github.com/joosure/Maestro>
- Origin project: <https://github.com/openai/symphony>

---

## License

Maestro는 GNU Affero General Public License version 3 (AGPL-3.0-only)에 따라 라이선스됩니다. OpenAI Symphony에서 파생된 부분에는 Apache-2.0 attribution 및 notice 요구사항이 유지됩니다. Maestro를 사용하거나 배포하기 전에 `LICENSE`, `NOTICE`, `LICENSES/Apache-2.0.txt`, `MODIFICATIONS.md`, `SOURCE.md`, `THIRD_PARTY_LICENSES.md`를 검토하세요.

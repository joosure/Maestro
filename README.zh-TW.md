# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-platformizing-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

[English](./README.md) | [简体中文](./README.zh-CN.md) | [繁體中文](./README.zh-TW.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Português (Brasil)](./README.pt-BR.md) | [Deutsch](./README.de.md) | [Français](./README.fr.md) | [Русский](./README.ru.md) | [Bahasa Indonesia](./README.id.md)

## 面向企業級工程的 AI Agent 營運與治理平台。

Maestro 是一個面向工程團隊的 AI Agent 營運與治理平台。它把工單系統、需求文件、程式碼倉庫、Agent Provider、執行環境和交付證據連接起來，讓 Codex、Claude Code、CodeBuddy Code、OpenCode 等 Coding Agent 可以從真實專案任務中自動接單、執行、提交和留痕。

它不是另一個 coding agent。

它是讓 Codex、Claude Code、CodeBuddy Code、OpenCode 和未來 Agent 在真實專案系統、真實倉庫、真實 workflow 與真實營運限制中工作的工程平台。

> **Symphony 證明了這個模式。Maestro 建構的是平台。**

---

## 容器快速啟動

執行本地 memory/mock workflow，不需要任何外部憑證：

```bash
docker compose -f deploy/compose/compose.quickstart.yml up --build
```

開啟 dashboard：`http://localhost:4000`。

完整 container mock quickstart、真實 workflow container integration、volumes 和 credential handling，請參考 [`docs/deployment/container.md`](./docs/deployment/container.md)。

---

## 為什麼需要 Maestro

OpenAI Symphony 提出了一個關鍵理念：**管理工作，而不是管理一個個 Agent session**。

與其要求工程師逐一監督 coding agent 的聊天 session，Symphony 證明了 Linear 等專案管理系統可以成為自主 coding work 的入口。

Maestro 將這個模式繼續向前推進。

它把原始的 `Linear + Codex` reference implementation 泛化為一個 **tracker-driven、provider-neutral、面向真實工程流程的 AI Agent 營運與治理平台**。

實際上，Maestro 幫助團隊從：

```text
human-managed agent chats
```

轉向：

```text
tracker-driven agent operations
```

這個差異很重要。Demo 可以靠單一 agent、單一 issue 和單一 repository 成功；生產團隊需要 scheduling、isolation、credential control、quota awareness、evidence、logs、reviews、state transitions 和 failure recovery。

Maestro 就是為第二種世界而建。

---

## Maestro 能做什麼

Maestro 協調一個 agentic engineering task 的完整生命週期：

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

它把工作系統、agent provider、程式碼平台、runtime 環境和 observability 連接成一個操作層。

| 能力域 | Maestro 提供的能力 |
| --- | --- |
| Tracker | Linear、TAPD、Memory，並可擴展 Jira、YouTrack、飛書專案、GitHub Issues 等 |
| Agent Provider | Codex、Claude Code、CodeBuddy Code、OpenCode，並可擴展未來 CLI 或 remote agent |
| Repo | provider-neutral 的 Git 操作，例如 clone、branch、commit、diff 和 push |
| Repo Provider | GitHub、CNB、Memory，並可擴展 GitLab、Gitea、Bitbucket 和 Gerrit |
| Workflow | 可重用 profile，覆蓋 coding delivery、requirement analysis、refinement、review routing 和 triage |
| Runtime | Local、SSH 和 Worker Daemon 執行模式 |
| Tool Bridge | 暴露給 Agent 的 provider-neutral dynamic tools |
| Governance | accounts、credential store、lease、quota polling、redaction 和 human gates |
| Observability | structured events、JSON logs、event store、dashboard drilldown 和 production evidence |

---

## Maestro 解決的問題

Coding agent 正變得強大。但強大的 agent 不會自動變成可靠的工程系統。

| 沒有 Maestro | 使用 Maestro |
| --- | --- |
| Agent 工作發生在孤立的 chat session 中 | 工作從真實 tracker 派發並連結到真實 issue |
| 每個 provider 都有自己的 session model | Provider 被包在共享 lifecycle contract 後面 |
| Agent output 難以 audit | diff、PR、tool call、log、state transition 和 evidence 都會被捕獲 |
| 團隊被鎖在單一 tracker 或 code platform | Tracker 和 repo provider 都是 adapter-based |
| Workflow 被硬編碼在 scripts 裡 | Workflow Profile 定義 policy、state、routing 和 deliverables |
| Credential 和 quota 是 ad hoc | Accounts、leases、quota polling 和 redaction 變成平台能力 |
| 擴展需要人工監督 session | Worker Daemon 支援 capacity-aware execution 和營運控制 |

Maestro 的判斷很簡單：

> **未來不是某個完美 coding agent。未來是一個能在真實工程 workflow 中 schedule、observe 和 govern 多個 agent 的操作層。**

---

## 核心設計原則

### 1. Tracker 是調度入口

團隊本來就運行在專案管理系統上。Maestro 不把工作藏在私有 queue 裡，而是讓 Linear、TAPD、Memory 和未來 tracker 成為自主工作的 dispatch surface。

### 2. Agent 是執行單元

Codex、Claude Code、CodeBuddy Code、OpenCode 和未來 agent 都被視為可替換 provider。Maestro 標準化平台層真正需要的 lifecycle：session creation、turn execution、tool-call capture、evidence collection、quota awareness 和 cleanup。

### 3. Workflow Profile 表達業務意圖

Coding、requirement analysis、refinement、review routing 和 triage 是不同 workflow。Maestro 讓 profile 成為一等對象，讓團隊定義何時 dispatch、何時 wait、何時 stop、需要什麼 evidence，以及何時必須由人接手。

### 4. Evidence 優先於宣稱

「完成」不夠。Maestro 重視可檢查的 artifacts：branch、commit、diff、PR、review note、CI result、tracker comment、tool call、event 和 log。

### 5. Adapter 防止平台鎖定

每個外部系統都透過 contract 進入。Orchestrator 不應變成特定 provider 的分支邏輯堆疊。新的 integration 應透過 adapters、contract tests、smoke tests 和明確的 capability discovery 進入。

---

## 架構

Maestro 更適合被理解為一套工程營運與治理架構：
Orchestrator 持有調度狀態，workflow policy 持有業務語義，provider 透過明確 contract 接入。
Governance 和 evidence 貫穿整個執行過程。

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

### 核心架構分層

Maestro 的平台級核心架構可以歸納為八層。前六層構成主要執行路徑；
Governance 和 Evidence & Observability 是貫穿全流程的控制與審計層。

| 層級 | 組成 | 職責 |
| --- | --- | --- |
| Work Source Layer | Tracker / Issue / Story / Ticket | 定義工作從哪裡進入系統 |
| Workflow Policy Layer | `WORKFLOW.md` / Workflow Profile / Route Policy / Capabilities / Human Gate Declarations | 定義團隊希望 Agent 如何執行工作 |
| Control Plane Layer / 調度控制層 | Orchestrator / Scheduler / Dispatch / Retry / Reconciliation / State Tracking | 決定任務何時執行、重試、停止或對帳 |
| Execution Runtime Layer | Agent Runner / Workspace / Runtime / Local / SSH / Worker Daemon / Session Lifecycle | 在隔離執行邊界中執行每個工作項 |
| Agent Provider Layer | Codex / Claude Code / CodeBuddy Code / OpenCode / Mock / Future Agent Providers | 以統一 lifecycle 包裝可替換的 Agent 實作 |
| Provider & Tool Integration Layer | Dynamic Tool Bridge / Tracker Adapter / Repo Facade / Repo Provider | 透過 provider-neutral contract 接入外部系統 |
| Governance Layer | Credential / Lease / Quota / Redaction / Approval / Policy Enforcement | 控制 access、capacity、approval 和安全策略 |
| Evidence & Observability Layer | Events / JSON Logs / Diff / PR / CI / Evidence / Audit Trail / Dashboard | 記錄發生了什麼、為什麼發生，以及結果是否可信 |

### 主要邊界

| Boundary | Responsibility |
| --- | --- |
| `Workflow File` | 透過 YAML front matter 提供 runtime 設定，並用 Markdown 正文提供 Agent prompt |
| `Workflow Profile` | 定義 route policy、capabilities、completion contract、stop conditions 和 human gates |
| `Tracker Adapter` | 讀取候選 work item、同步 state、寫 comments、暴露 tracker typed tools |
| `Orchestrator` | polling、reconciliation、調度、retry、runtime state tracking 和 terminal cleanup |
| `Agent Runner` | 為單一 work item 建立 workspace、執行 hooks、啟動並驅動 Agent session |
| `Workspace` | 隔離每個 work item 的 runtime 目錄、workspace automation、repository copy 和本地 evidence |
| `Agent Provider` | start、drive、stream、stop 和清理 Codex / Claude Code / CodeBuddy Code / OpenCode / Mock session |
| `Agent Runtime` | 將 provider process 放置到 local、SSH 或 Worker Daemon，並解析 sandbox / executor context |
| `Repo` | provider-neutral 的本地 Git 操作：clone、branch、commit、diff、push |
| `Repo Provider` | GitHub、CNB、Memory 等 code platform 能力：PR / MR、review、checks、merge、comments、status updates |
| `Dynamic Tool Bridge` | 將 Tracker、Repo 和 Repo Provider 能力聚合為 session-scoped provider-neutral tools |
| `Observability` | structured events、JSON logs、event store、redaction、dashboard、evidence、audit trail |

---

## Workflow Profiles

Maestro 不限於「從 issue 寫程式碼」。它可以用同一個平台層承載多種工程 workflow。

| Profile | Purpose | Typical Evidence |
| --- | --- | --- |
| `coding_pr_delivery` | 將 work item 轉成 code changes 和 PR | branch、commit、diff、PR、CI result、review note |
| `requirement_analysis` | 將 requirement 轉成 structured analysis | scope、risks、impact、acceptance criteria、task breakdown |
| `requirement_refinement` | 在 implementation 前找出 ambiguity | clarification questions、blockers、assumptions、refined acceptance criteria |
| `review_routing` | 將 review 分派給合適的人或 agent | reviewer suggestions、risk tags、checklist |
| `triage` | 分類並路由 work items | priority、owner、type、risk、next state |

Profile 是 Maestro 從 automation script 走向 platform 的關鍵。它定義 agent 應該做什麼、不應該做什麼、必須產出什麼 evidence，以及何時應交還給人。

---

## 設定形態範例

目前實作透過 workflow Markdown file 的 YAML front matter 設定 runtime，Markdown 正文則作為 Agent prompt。下面是核心維度與目前欄位位置的示意，不是完整可執行設定：

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

Agent provider kind 是標準 runtime 字串。目前內建值是 `codex`、
`claude_code`、`codebuddy_code`、`opencode` 和 `mock`；支援的 alias 會先由 Elixir provider-kind owner 正規化，再進入 registry lookup。

Tracker、repo-provider 和 agent-provider 的標準 kind 字串分別由 Elixir 的 `Tracker.Kinds`、`RepoProvider.Kinds` 和 `AgentProvider.Kinds` 模組持有，確保 registry、defaults 和 documentation 保持一致。

一個 production deployment 可以獨立組合這些維度。例如：

```text
TAPD + CodeBuddy Code + CNB + Worker Daemon + requirement_analysis
Linear + Codex + GitHub + Local Runtime + coding_pr_delivery
Memory + Mock Agent + Memory Repo Provider + Contract Tests
```

---

## 快速開始

如果你是第一次執行 Maestro，建議先閱讀 [新人端到端執行指引](./elixir/docs/quickstart/zh-CN.md)。該指引涵蓋本機 `memory/no_repo/mock`、真實 `TAPD + CNB + CodeBuddy Code`、真實 `Linear + GitHub + OpenCode` 三條 workflow 路徑。

Clone repository：

```bash
git clone https://github.com/joosure/Maestro.git
cd Maestro
```

先準備 repository 固定的 Erlang / Elixir 工具鏈。建議使用 `mise`，版本由 `elixir/mise.toml` 固定：

```bash
cd elixir
mise trust
mise install
cd ..
```

安裝依賴並執行 test suite。如果目前 shell 已啟用 `mise` 工具鏈，可以直接使用 `make`：

```bash
make -C elixir deps
make -C elixir test
```

也可以從 `elixir/` 目錄使用 `mise exec -- mix setup` 和 `mise exec -- mix test`。

### 快速體驗 workflow template

建置 CLI，並從 `elixir/` 啟動本地 memory/mock workflow：

```bash
cd elixir
make build
mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

這會使用 `memory/no_repo/mock` template 啟動服務，並在 `http://localhost:4000` 暴露可選 dashboard/API。它使用記憶體 tracker、記憶體 repo provider 和 mock agent provider，不需要 Linear、GitHub、Codex、Claude Code、CodeBuddy Code、OpenCode 或 CNB 憑證。

如果要接入真實 tracker、repository 和 agent runtime，先設定所需憑證，再切換 template：

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

`SOURCE_REPO_BRANCH_WORK_PREFIX` 和 `SOURCE_REPO_PROVIDER_REQUIRED_PR_LABEL` 是可選項。`SYMPHONY_WORKSPACE_ROOT` 在本地 quick start 中可以省略；接入真實 tracker、真實 repository 或進行完整流程驗證前，建議明確設定到隔離的 workspace root，避免 workspace 落在本機開發路徑中且難以清理。接入真實 tracker 或 repository 前，請先閱讀 [workflow template aliases](./elixir/priv/workflow_templates/README.md) 和 [runtime configuration](./elixir/README.md)。

開 PR 前，先執行和 CI 一致的本地 gates：

```bash
make -C elixir all
make -C elixir secret-scan
```

`make -C elixir secret-scan` 會透過 `scripts/secret-scan.sh` 執行
`gitleaks`、`trufflehog` 和 `detect-secrets`。CI 會在 push 到 `main` 和 pull requests 時執行同一套 gate。

本地實驗建議按風險由低到高推進：

- 需要無外部憑證驗證執行流程時，配置 `tracker.kind: memory` 和 `repo.provider.kind: memory`。
- fake/simulated agent adapter 只透過 adapter registry 用於測試或擴展開發；目前內建 agent provider 是 `codex`、`claude_code`、`codebuddy_code` 和 `opencode`。
- memory 路徑穩定後，再接入 Linear/TAPD、GitHub/CNB 或 destructive smoke tests。

> 對外品牌使用 **Maestro**。早期版本可能仍包含繼承自 `symphony` 的 module names、CLI entrypoints 或 environment variables；這些可視為 compatibility names，後續會隨 project branding 和 platform boundaries 穩定而整理。

---

## 擴展模型

Maestro 傾向透過 contracts 成長，而不是透過 hardcoded branches。

### 新增 Tracker Adapter

為以下能力實作 tracker contract：

- listing candidate work items；
- reading title、description、labels、state、owner 和 metadata；
- claiming or locking work；
- writing comments and evidence；
- 將特定 provider 的 states 映射到 Maestro workflow model；
- passing contract tests and live smoke tests。

### 新增 Agent Provider

為以下能力實作 provider contract：

- session creation；
- prompt and context injection；
- turn execution；
- streaming events；
- tool-call capture；
- evidence extraction；
- cancellation and cleanup；
- capability reporting，例如 sandbox、tools、approval、quota 和 context window。

### 新增 Repo Provider

為以下能力實作 repo-provider contract：

- PR / MR creation；
- review comments；
- checks and statuses；
- merge gates；
- branch protection detection；
- evidence links；
- idempotent updates。

### 新增 Workflow Profile

定義：

- trigger states；
- dispatch policy；
- input context；
- agent instructions；
- allowed tools；
- required evidence；
- stop conditions；
- human approval gates；
- tracker transitions。

---

## Observability and Evidence

Maestro 將 observability 視為產品能力，而不是事後補丁。

每次 run 都應能透過以下資訊解釋：

- dispatch decision；
- workflow profile；
- selected provider；
- runtime and worker；
- session and turn history；
- tool calls；
- stdout / stderr / structured event stream；
- workspace and repository changes；
- PR or review artifacts；
- tracker comments and state changes；
- redacted logs；
- final evidence summary。

這讓 Maestro 不只可用於 automation，也可用於 evaluation、debugging、governance 和 production rollout。

---

## 專案狀態

Maestro 正在積極 platformization。

它適合：

- 研究 tracker-driven agent orchestration；
- 建立 adapter prototypes；
- 驗證 workflow profiles；
- 執行 memory-provider 或 local test loops；
- 在受控環境中實驗 real providers。

在以下場景前仍應加固：

- unrestricted production execution；
- destructive repository operations；
- high-privilege credentials；
- multi-tenant worker pools；
- unattended merge or deploy automation。

指導原則是：

> **大膽自動化。謹慎加 gate。保留 evidence。**

---

## Maestro 適合誰

Maestro 適合：

- 正在評估 Codex、Claude Code、CodeBuddy Code、OpenCode 或未來 coding agents 的 engineering teams；
- 建置內部 AI engineering infrastructure 的 platform teams；
- 建立 agent operations workflows 的 DevTools teams；
- 希望 agent 從既有 trackers 工作的 product and engineering organizations；
- 研究 agent reliability、evidence 和 orchestration 的 researchers；
- 想要 structured agent-driven contribution flows 的 open-source maintainers。

---

## Attribution

Maestro 始於 [OpenAI Symphony](https://github.com/openai/symphony) 的 fork。原始 Symphony reference implementation 聚焦 Linear-driven Codex orchestration。Maestro 將這個想法擴展為涵蓋 trackers、agent providers、repository providers、workflow profiles、runtimes、tools 和 evidence 的 broader platform architecture。

---

## 倉庫

- GitHub: <https://github.com/joosure/Maestro>
- Origin project: <https://github.com/openai/symphony>

---

## License

Maestro 使用 GNU Affero General Public License version 3 (AGPL-3.0-only) 授權。源自 OpenAI Symphony 的部分保留 Apache-2.0 attribution 和 notice 要求。使用或分發 Maestro 前，請檢查 `LICENSE`、`NOTICE`、`LICENSES/Apache-2.0.txt`、`MODIFICATIONS.md`、`SOURCE.md` 和 `THIRD_PARTY_LICENSES.md`。

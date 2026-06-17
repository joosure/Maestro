# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-early%20stage-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

語言：[English](./README.md) · [简体中文](./README.zh-CN.md) · [繁體中文](./README.zh-TW.md) · [日本語](./README.ja.md) · [한국어](./README.ko.md) · [Español](./README.es.md) · [Português](./README.pt-BR.md) · [更多語言](./LANGUAGES.md)

## 讓 AI Agent 從真實專案任務開始工作。

Maestro 是一個把**專案系統、Git 倉庫和 Coding Agent** 連接起來的工程任務執行平台。

你不需要一個一個盯著 Agent 聊天視窗。Maestro 可以從 Linear、TAPD 等專案管理平台讀取新增或待處理的任務，為每個任務建立獨立工作區，準備目標 Git 倉庫，啟動合適的 AI Agent，記錄執行過程，並把結果寫回專案系統。

它不是另一個 Coding Agent。

它解決的是團隊真正使用 Codex、Claude Code、OpenCode 等 Agent 時會遇到的問題：任務從哪裡來、程式碼從哪裡來、Agent 在哪裡執行、多個任務如何並行、結果是否可信、失敗後如何恢復、整個過程如何回顧。

> **Symphony 證明了專案任務可以驅動 Agent。Maestro 要做的是把這個模式變成一套真正可營運的工程平台。**

---

## 一個例子說明 Maestro 是什麼

假設 TAPD 或 Linear 裡新增了一個任務：

> 使用者同時使用兩張優惠券時，結帳頁會出錯。

使用 Maestro 後，這個任務可以變成一次可追蹤的 Agent 執行：

1. Maestro 從 TAPD、Linear 或其他專案系統同步到這個待處理任務。
2. Maestro 在自己的執行環境中為這個任務建立一個獨立工作區。
3. Maestro 依照設定把目標 Git 倉庫 clone / checkout 到這個工作區。
4. Maestro 啟動 Codex、Claude Code、OpenCode 或其他支援的 Agent，並提供任務內容、倉庫副本和可用工具。
5. Agent 在這個獨立倉庫副本中分析程式碼，準備程式碼變更、分析結論或評審建議。
6. Maestro 記錄 diff、日誌、工具呼叫、執行摘要和相關連結。
7. Maestro 把結果寫回專案系統，團隊可以繼續評審、修改或接手。

這裡的重點不是「讓 Agent 自己隨便跑」，而是：

> **一個專案任務變成了一次有隔離環境、有執行紀錄、可回顧、可接手的 Agent 工程執行。**

獨立工作區的意義在於：每個任務都有自己的目錄、倉庫副本、日誌和暫存檔。這樣多個專案、多個任務可以並行處理，彼此不會互相污染；失敗後也更容易清理、回顧和重新執行。

---

## 為什麼需要 Maestro

Coding Agent 越來越會寫程式碼，但團隊真正需要的不只是「讓 Agent 寫一段程式」。

團隊還需要回答這些問題：

- 任務從哪個專案系統來？
- 對應哪個 Git 倉庫和分支？
- 應該交給哪個 Agent？
- Agent 在哪裡執行？
- 多個任務如何並行且互不影響？
- 它到底改了什麼？
- 人能不能 review？
- 失敗後怎麼恢復？
- 怎麼知道整個過程發生了什麼？

Maestro 就是圍繞這些問題設計的。

---

## 你可以用 Maestro 做什麼？

### 1. 從 Bug 任務到 Pull Request

TAPD 或 Linear 裡出現一個 Bug。Maestro 讀取任務，建立獨立工作區，準備目標 Git 倉庫，啟動 Agent，讓 Agent 分析並修改程式碼，然後把 PR 連結、執行摘要和待確認事項寫回任務。

### 2. 先分析需求，而不是直接寫程式

如果一個需求還不清楚，Maestro 可以讓 Agent 先輸出影響範圍、風險、驗收標準和待確認問題，協助團隊判斷是否可以進入開發。

### 3. 澄清還不能開始的任務

如果任務缺少關鍵上下文，Maestro 可以協助列出假設、阻塞點和需要人工確認的問題，而不是讓 Agent 盲目開始寫程式。

### 4. 自動分診新任務

新任務進入專案系統後，Maestro 可以協助判斷它是 Bug、需求、技術債還是評審任務，並給出優先級、風險和下一步建議。

### 5. 比較不同 Coding Agent

同類任務可以分別交給 Codex、Claude Code 或 OpenCode，團隊可以比較結果、失敗原因、日誌和交付紀錄。

### 6. 先在本地安全體驗

使用本地 memory/mock 流程，不需要連接 Linear、TAPD、GitHub、CNB 或真實 Agent，就可以先理解 Maestro 如何調度任務。

---

## 目前已有的串接能力

下面說的是 Maestro 目前程式碼中已有的**適配能力和模板**，不是說這些外部系統被「內建在 Maestro 裡」。Linear、TAPD、GitHub、CNB、Codex、Claude Code 和 OpenCode 都是外部系統或外部工具；Maestro 負責連接和編排它們。

專案系統適配：

- Linear
- TAPD
- Memory，用於本地測試和展示

Agent 適配：

- Codex
- Claude Code
- OpenCode
- Mock，用於本地測試和展示

程式碼平台適配：

- GitHub
- CNB
- Memory，用於本地測試和展示

已有流程模板包括：

- `memory/no_repo/mock`
- `linear/github/codex`
- `linear/github/claude_code`
- `linear/github/opencode.canary`
- `tapd/github/codex`
- `tapd/cnb/opencode`
- `tapd/cnb/claude_code`

Maestro 也會繼續支援更多專案系統、程式碼平台、Agent 和任務流程。

---

## 它是怎麼工作的？

```text
專案系統裡的任務
   ↓
Maestro 讀取/同步任務，並判斷是否應該處理
   ↓
Maestro 在自己的執行環境中為該任務建立獨立工作區
   ↓
依照設定把目標 Git 倉庫準備到這個工作區
   ↓
啟動 AI Agent，並提供任務內容、倉庫副本和可用工具
   ↓
Agent 產出程式碼變更、分析結果或評審建議
   ↓
Maestro 記錄 diff、日誌、工具呼叫、摘要和相關連結
   ↓
Maestro 把結果寫回專案系統，供團隊繼續評審或接手
```

對開發者來說，可以把 Maestro 理解成幾個可擴展部分：

- **專案系統**：任務從哪裡來，例如 Linear 或 TAPD。
- **Git 倉庫和程式碼平台**：程式碼從哪裡 clone，分支、PR、評審和檢查在哪裡發生。
- **Agent**：誰來執行，例如 Codex、Claude Code 或 OpenCode。
- **任務流程**：這次是修 Bug、分析需求、澄清需求、分診任務，還是做評審建議。
- **工作區和執行環境**：每次 Agent 執行在哪裡運行，如何隔離，如何並行。
- **執行紀錄**：日誌、diff、任務評論、摘要和其他可回顧資訊。

---

## 快速開始

```bash
git clone https://github.com/joosure/Maestro.git
cd Maestro
cd elixir
mise trust
mise install
cd ..
make -C elixir deps
make -C elixir test
make -C elixir build
cd elixir
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

打開可選 dashboard：

```text
http://localhost:4000
```

這個 demo 使用記憶體資料和 Mock Agent，是理解專案最安全的方式。

> 對外品牌使用 **Maestro**。部分執行時名稱仍然保留 `symphony` 相容命名，包括 CLI 入口和部分環境變數。

---

## 連接真實系統

本地 demo 跑通後，可以再接入真實專案系統、Git 倉庫和 Coding Agent。

### 範例：TAPD + GitHub + Codex

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

### 範例：Linear + GitHub + Codex

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

連接真實倉庫或高權限憑據前，請先閱讀：

- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## Maestro 是什麼，不是什麼

Maestro 是：

- 連接專案系統、Git 倉庫和 Coding Agent 的工程任務執行平台；
- 讓 AI Agent 從真實專案任務開始工作的系統；
- 面向編碼、需求分析、需求澄清、任務分診和評審建議的流程層；
- 協助團隊安全試用、比較和管理不同 Coding Agent 的方式。

Maestro 不是：

- 不是新的大模型；
- 不是 Codex、Claude Code 或 OpenCode 的替代品；
- 不是替團隊跳過評審、測試和發布判斷的工具；
- 不是拿到倉庫權限後就可以放任不管的無人值守系統。

---

## 專案狀態

Maestro 仍處於早期活躍開發階段。

適合用於：

- 學習任務驅動的 Agent 工作流；
- 執行本地 memory/mock demo；
- 原型驗證新的系統接入；
- 在受控環境中試驗真實系統。

在以下場景需要額外謹慎：

- 允許 Agent 修改真實倉庫或推送分支；
- 允許 Agent 寫回真實專案系統的狀態或評論；
- 使用高權限憑據或個人 token；
- 讓多個團隊共用同一執行環境；
- 跳過人工評審直接進入測試、發布或上線流程。

基本原則是：

> **大膽自動化，謹慎加關卡，讓過程始終可見。**

---

## 了解更多

- [Roadmap](./ROADMAP.zh-TW.md)
- [Languages](./LANGUAGES.md)
- [Elixir runtime guide](./elixir/README.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.md)
- [Operations guide](./elixir/docs/operations.md)

---

## 來源說明

Maestro 始於 [OpenAI Symphony](https://github.com/openai/symphony) 的 fork。Symphony 證明了專案任務可以驅動 Coding Agent。Maestro 將這個想法擴展為面向真實工程流程的平台。

---

## License

Maestro 使用 GNU Affero General Public License version 3 (AGPL-3.0-only) 授權。源自 OpenAI Symphony 的部分保留 Apache-2.0 署名和 notice 要求。使用或分發 Maestro 前，請檢查 `LICENSE`、`NOTICE`、`LICENSES/Apache-2.0.txt`、`MODIFICATIONS.md`、`SOURCE.md` 和 `THIRD_PARTY_LICENSES.md`。

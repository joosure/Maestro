# Maestro

[![GitHub](https://img.shields.io/badge/GitHub-joosure%2FMaestro-black?logo=github)](https://github.com/joosure/Maestro)
[![Status](https://img.shields.io/badge/status-early%20stage-orange)](https://github.com/joosure/Maestro)
[![Origin](https://img.shields.io/badge/origin-openai%2Fsymphony-412991)](https://github.com/openai/symphony)

语言：[English](./README.md) · [简体中文](./README.zh-CN.md) · [日本語](./README.ja.md) · [한국어](./README.ko.md) · [Español](./README.es.md) · [Português](./README.pt-BR.md) · [更多语言](./LANGUAGES.md)

## 让 AI Agent 从真实项目任务开始工作。

Maestro 是一个把**项目系统、Git 仓库和 Coding Agent** 连接起来的工程任务执行平台。

你不需要一个个盯着 Agent 聊天窗口。Maestro 可以从 Linear、TAPD 等项目管理平台读取新增或待处理的任务，为每个任务创建独立工作区，准备目标 Git 仓库，启动合适的 AI Agent，记录执行过程，并把结果写回项目系统。

它不是另一个 Coding Agent。

它解决的是团队真正使用 Codex、Claude Code、OpenCode 等 Agent 时会遇到的问题：任务从哪里来、代码从哪里来、Agent 跑在哪里、多个任务如何并行、结果是否可信、失败后怎么恢复、过程如何复盘。

> **Symphony 证明了项目任务可以驱动 Agent。Maestro 要做的是把这个模式变成一套真正可运营的工程平台。**

---

## 一个例子说明 Maestro 是什么

假设 TAPD 或 Linear 里新增了一个任务：

> 用户同时使用两个优惠券时，结算页会报错。

使用 Maestro 后，这个任务可以变成一次可追踪的 Agent 执行：

1. Maestro 从 TAPD、Linear 或其他项目系统同步到这个待处理任务。
2. Maestro 在自己的运行环境中为这个任务创建一个独立工作区。
3. Maestro 根据配置把目标 Git 仓库 clone / checkout 到这个工作区。
4. Maestro 启动 Codex、Claude Code、OpenCode 或其他支持的 Agent，并提供任务内容、仓库副本和可用工具。
5. Agent 在这个独立仓库副本中分析代码，准备代码变更、分析结论或评审建议。
6. Maestro 记录 diff、日志、工具调用、执行摘要和相关链接。
7. Maestro 把结果写回项目系统，团队可以继续评审、修改或接手。

这里的关键不是“让 Agent 自己随便跑”，而是：

> **一个项目任务变成了一次有隔离环境、有执行记录、可复盘、可接手的 Agent 工程执行。**

独立工作区的意义在于：每个任务都有自己的目录、仓库副本、日志和临时文件。这样多个项目、多个任务可以并行处理，彼此不会互相污染；失败后也更容易清理、复盘和重新执行。

---

## 为什么需要 Maestro

Coding Agent 越来越会写代码，但团队真正需要的不只是“让 Agent 写一段代码”。

团队还需要回答这些问题：

- 任务从哪个项目系统来？
- 对应哪个 Git 仓库和分支？
- 应该交给哪个 Agent？
- Agent 在哪里运行？
- 多个任务如何并行且互不影响？
- 它到底改了什么？
- 人能不能 review？
- 失败后怎么恢复？
- 怎么知道整个过程发生了什么？

Maestro 围绕这些问题设计。

---

## 你可以用 Maestro 做什么？

### 1. 从 Bug 任务到 Pull Request

TAPD 或 Linear 里出现一个 Bug。Maestro 读取任务，创建独立工作区，准备目标 Git 仓库，启动 Agent，让 Agent 分析并修改代码，然后把 PR 链接、执行摘要和待确认事项写回任务。

### 2. 先分析需求，而不是直接写代码

如果一个需求还不清楚，Maestro 可以让 Agent 先输出影响范围、风险、验收标准和待确认问题，帮助团队决定是否可以进入开发。

### 3. 澄清还不能开始的任务

如果任务缺少关键上下文，Maestro 可以帮助列出假设、阻塞点和需要人工确认的问题，而不是让 Agent 盲目开始写代码。

### 4. 自动分诊新任务

新任务进入项目系统后，Maestro 可以帮助判断它是 Bug、需求、技术债还是评审任务，并给出优先级、风险和下一步建议。

### 5. 对比不同 Coding Agent

同类任务可以分别交给 Codex、Claude Code 或 OpenCode，团队可以比较结果、失败原因、日志和交付记录。

### 6. 先在本地安全体验

使用本地 memory/mock 流程，不需要连接 Linear、TAPD、GitHub、CNB 或真实 Agent，就可以先理解 Maestro 如何调度任务。

---

## 当前已有的接入能力

下面说的是 Maestro 当前代码中已有的**适配能力和模板**，不是说这些外部系统“内置在 Maestro 里”。Linear、TAPD、GitHub、CNB、Codex、Claude Code 和 OpenCode 都是外部系统或外部工具；Maestro 负责连接和编排它们。

项目系统适配：

- Linear
- TAPD
- Memory，用于本地测试和演示

Agent 适配：

- Codex
- Claude Code
- OpenCode
- Mock，用于本地测试和演示

代码平台适配：

- GitHub
- CNB
- Memory，用于本地测试和演示

已有流程模板包括：

- `memory/no_repo/mock`
- `linear/github/codex`
- `linear/github/claude_code`
- `linear/github/opencode.canary`
- `tapd/github/codex`
- `tapd/cnb/opencode`
- `tapd/cnb/claude_code`

Maestro 也会继续支持更多项目系统、代码平台、Agent 和任务流程。

---

## 它是怎么工作的？

```text
项目系统里的任务
   ↓
Maestro 读取/同步任务，并判断是否应该处理
   ↓
Maestro 在自己的运行环境中为该任务创建独立工作区
   ↓
根据配置把目标 Git 仓库准备到这个工作区
   ↓
启动 AI Agent，并提供任务内容、仓库副本和可用工具
   ↓
Agent 产出代码变更、分析结果或评审建议
   ↓
Maestro 记录 diff、日志、工具调用、摘要和相关链接
   ↓
Maestro 把结果写回项目系统，供团队继续评审或接手
```

对开发者来说，可以把 Maestro 理解成几个可扩展部分：

- **项目系统**：任务从哪里来，例如 Linear 或 TAPD。
- **Git 仓库和代码平台**：代码从哪里 clone，分支、PR、评审和检查在哪里发生。
- **Agent**：谁来执行，例如 Codex、Claude Code 或 OpenCode。
- **任务流程**：这次是修 Bug、分析需求、澄清需求、分诊任务，还是做评审建议。
- **工作区和运行环境**：每次 Agent 执行在哪里运行，如何隔离，如何并行。
- **执行记录**：日志、diff、任务评论、摘要和其他可复盘信息。

---

## 快速开始

克隆仓库：

```bash
git clone https://github.com/joosure/Maestro.git
cd Maestro
```

安装仓库固定的 Erlang / Elixir 工具链。推荐使用 `mise`：

```bash
cd elixir
mise trust
mise install
cd ..
```

安装依赖并运行测试：

```bash
make -C elixir deps
make -C elixir test
```

启动本地 demo：

```bash
make -C elixir build
cd elixir
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

打开可选 dashboard：

```text
http://localhost:4000
```

这个 demo 使用内存数据和 Mock Agent，是理解项目最安全的方式。

> 对外品牌使用 **Maestro**。部分运行时名称仍然保留 `symphony` 兼容命名，包括 CLI 入口和部分环境变量。

---

## 连接真实系统

本地 demo 跑通后，可以再接入真实项目系统、Git 仓库和 Coding Agent。

### 示例：TAPD + GitHub + Codex

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

### 示例：Linear + GitHub + Codex

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

在连接真实仓库或高权限凭据前，请先阅读：

- [Elixir 运行时指南](./elixir/README.zh-CN.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.zh-CN.md)
- [Operations guide](./elixir/docs/operations.zh-CN.md)

---

## Maestro 是什么，不是什么

Maestro 是：

- 连接项目系统、Git 仓库和 Coding Agent 的工程任务执行平台；
- 让 AI Agent 从真实项目任务开始工作的系统；
- 面向编码、需求分析、需求澄清、任务分诊和评审建议的流程层；
- 帮团队安全试用、比较和管理不同 Coding Agent 的方式。

Maestro 不是：

- 不是新的大模型；
- 不是 Codex、Claude Code 或 OpenCode 的替代品；
- 不是替团队跳过评审、测试和发布判断的工具；
- 不是拿到仓库权限后就可以放任不管的无人值守系统。

---

## 项目状态

Maestro 仍处于早期活跃开发阶段。

适合用于：

- 学习任务驱动的 Agent 工作流；
- 运行本地 memory/mock demo；
- 原型验证新的系统接入；
- 在受控环境中试验真实系统。

在以下场景需要额外谨慎：

- 允许 Agent 修改真实仓库或推送分支；
- 允许 Agent 写回真实项目系统的状态或评论；
- 使用高权限凭据或个人 token；
- 让多个团队共享同一执行环境；
- 跳过人工评审直接进入测试、发布或上线流程。

基本原则是：

> **大胆自动化，谨慎加关卡，让过程始终可见。**

---

## 了解更多

- [路线图](./ROADMAP.zh-CN.md)
- [多语言文档](./LANGUAGES.md)
- [Elixir 运行时指南](./elixir/README.zh-CN.md)
- [Workflow templates](./elixir/priv/workflow_templates/README.zh-CN.md)
- [Operations guide](./elixir/docs/operations.zh-CN.md)

---

## 来源说明

Maestro 始于 [OpenAI Symphony](https://github.com/openai/symphony) 的 fork。Symphony 证明了项目任务可以驱动 Coding Agent。Maestro 将这个想法扩展为面向真实工程流程的平台。

---

## License

Maestro 使用 GNU Affero General Public License version 3 (AGPL-3.0-only) 授权。源自 OpenAI Symphony 的部分保留 Apache-2.0 署名和 notice 要求。使用或分发 Maestro 前，请检查 `LICENSE`、`NOTICE`、`LICENSES/Apache-2.0.txt`、`MODIFICATIONS.md`、`SOURCE.md` 和 `THIRD_PARTY_LICENSES.md`。

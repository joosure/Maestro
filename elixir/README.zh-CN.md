# Maestro Elixir 运行时指南

这个目录包含 Maestro 真正运行的 Elixir/OTP 实现。

根目录 README 解释项目价值；这份文档解释如何启动运行时、体验本地 demo、接入真实系统，以及应该继续阅读哪些运维文档。

## 它做什么

Maestro 会把一个项目系统里的任务，变成一次可追踪的 AI Agent 执行过程：

```text
从 TAPD / Linear / Memory 读取或同步任务
  -> 在 Maestro 自己的运行环境中创建独立工作区
  -> 按配置把目标 Git 仓库准备到工作区
  -> 启动 Codex / Claude Code / OpenCode / Mock
  -> 让 Agent 在仓库副本中分析、修改或产出建议
  -> 记录日志、工具调用、diff、摘要和链接
  -> 把结果写回项目系统
```

独立工作区不是创建在 TAPD 或 GitHub 里，而是创建在 Maestro 运行所在的本机、SSH 机器或 worker 环境中。它的作用是让每个任务有自己的目录、代码副本、日志和临时文件，便于并行、隔离、清理和复盘。

Maestro 的目标不是替代某个 Coding Agent，而是让团队能从真实项目任务中调度和管理这些 Agent。

## 命名说明

对外项目名是 **Maestro**。

当前运行时中仍有一些来自 Symphony 的兼容命名：

- `SymphonyElixir` 模块名
- `./bin/symphony` CLI 入口
- `.symphony` 运行目录
- `SYMPHONY_*` 环境变量

运行当前代码时请继续使用这些名字。它们是兼容命名，不代表另一个产品。

## 当前状态

Maestro 仍处于早期阶段，适合可信评估、实验和试点部署。

建议先在本地或测试环境运行。接入真实项目系统、真实仓库或无人值守写入前，需要审查凭据、仓库权限、安全边界和合规要求。

## 快速开始：本地 demo

这是最安全的体验方式，不需要 Linear、TAPD、GitHub、CNB、Codex、Claude Code、OpenCode 或外部凭据。

```bash
git clone https://github.com/joosure/Maestro.git
cd Maestro/elixir

mise trust
mise install
mise exec -- mix setup
mise exec -- mix build

mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

打开：

```text
http://localhost:4000
```

这会启动一个本地流程，使用：

- 本地模拟任务源；
- 本地模拟代码平台；
- mock agent；
- 端口 `4000` 上的 dashboard/API。

## 选择模板

Workflow template 可以理解成“运行配方”。它决定：

```text
任务从哪里来 / Git 仓库或代码平台在哪里 / 用哪个 Agent 执行
```

| Template | 含义 | 适合场景 |
| --- | --- | --- |
| `memory/no_repo/mock` | 本地模拟任务 + 无真实仓库 + mock agent | 第一次安全体验 |
| `linear/github/codex` | Linear + GitHub + Codex | 用 Codex 处理 Linear/GitHub 任务 |
| `linear/github/claude_code` | Linear + GitHub + Claude Code | 用 Claude Code 处理 Linear/GitHub 任务 |
| `tapd/github/codex` | TAPD + GitHub + Codex | TAPD 任务 + GitHub 仓库 |
| `tapd/cnb/opencode` | TAPD + CNB + OpenCode | TAPD/CNB 流程 |
| `tapd/cnb/claude_code` | TAPD + CNB + Claude Code | TAPD/CNB 流程 |

完整说明见 [Workflow templates](./priv/workflow_templates/README.zh-CN.md)。

## 接入真实系统

只配置当前模板需要的凭据。

TAPD：

```bash
export TAPD_API_USER=...
export TAPD_API_PASSWORD=...
export TAPD_WORKSPACE_ID=...
```

Linear：

```bash
export LINEAR_API_KEY=...
export LINEAR_PROJECT_SLUG=...
```

仓库输入：

```bash
export SOURCE_REPO_URL=https://github.com/example-user/sample-repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=example-user/sample-repo
```

接入真实系统前，建议显式设置独立工作区目录：

```bash
export SYMPHONY_WORKSPACE_ROOT=/path/to/isolated/maestro-workspaces
```

## 启动真实模板

例如 TAPD + GitHub + Codex：

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template tapd/github/codex \
  --port 4000
```

例如 Linear + GitHub + Codex：

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template linear/github/codex \
  --port 4000
```

真实模板可能会更新项目系统、创建分支、推送 commit 或打开 PR。请只在可信测试环境或明确允许的生产环境中运行。

## Workflow 文件简述

一个 workflow 文件包含两部分：

1. YAML front matter：配置项目系统、仓库、Agent、工作区和限制。
2. Markdown 正文：给 Agent 的 prompt。

示意：

```yaml
---
tracker:
  kind: tapd
workspace:
  root: $SYMPHONY_WORKSPACE_ROOT
repo:
  provider:
    kind: github
agent_provider:
  kind: codex
---

You are working on {{ issue.identifier }}.
```

建议先使用模板，再写自定义 workflow。

## Dashboard 和 API

使用 `--port` 开启 dashboard/API。

| 路径 | 用途 |
| --- | --- |
| `/` | Dashboard |
| `/issues/:issue_identifier` | 任务详情页 |
| `/api/v1/state` | 运行状态 JSON |
| `/api/v1/<issue_identifier>` | 任务详情 JSON |
| `/api/v1/refresh` | 刷新接口 |

默认结构化日志在 `./log/symphony.log`。

## 测试

标准本地质量门禁：

```bash
make all
```

提交前运行 secret scan：

```bash
make secret-scan
```

Tracker smoke 示例：

```bash
mix tracker.smoke --template memory/no_repo/mock --issue local-memory-1 --json
```

Live test 和 destructive smoke 可能会创建真实任务、运行真实 Agent、推送分支或创建 PR。只应在一次性或明确批准的环境中运行。

## 继续阅读

- [Workflow templates](./priv/workflow_templates/README.zh-CN.md)：选择运行配方。
- [Operations guide](./docs/operations.zh-CN.md)：在真实环境中安全运行。
- [Logging guide](./docs/logging.md)：日志、事件、脱敏和 dashboard。
- [Repo provider guide](./docs/repo_provider.md)：GitHub/CNB 仓库与 PR 操作。
- [Testing guide](./docs/testing.md)：本地、live、smoke 和 destructive validation。
- [Agent provider docs](./docs/agent_providers/)：Codex、Claude Code、OpenCode 的 provider 说明。

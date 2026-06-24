# Workflow Templates

Workflow template 可以理解成 Maestro 的“运行配方”。

一个模板回答三个问题：

```text
任务从哪里来？
代码或代码平台在哪里？
用哪个 AI Agent 执行？
```

例如 `tapd/github/codex` 表示：

```text
TAPD 任务 -> GitHub 仓库 -> Codex Agent
```

例如 `linear/github/codex` 表示：

```text
Linear 任务 -> GitHub 仓库 -> Codex Agent
```

## 推荐从这里开始

第一次运行建议使用：

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

这个模板不需要外部账号或凭据，适合安全体验 Maestro 的基本流程。

## 模板命名规则

模板 alias 的格式是：

```text
<tracker>/<source>/<agent-provider>[.<variant>]
```

| 片段 | 含义 | 示例 |
| --- | --- | --- |
| `tracker` | 提供任务的项目系统或本地模拟任务源 | `linear`、`tapd`、`memory` |
| `source` | 仓库或代码平台来源；没有真实仓库时使用 `no_repo` | `github`、`cnb`、`no_repo` |
| `agent-provider` | 执行任务的 AI Agent 或本地 mock | `codex`、`claude_code`、`opencode`、`mock` |
| `variant` | 可选的特殊版本 | `canary` |

## 当前模板

| Template | 作用 | 适合场景 |
| --- | --- | --- |
| `memory/no_repo/mock` | 本地模拟任务 + 无真实仓库 + mock agent | 第一次安全体验 |
| `linear/github/codex` | Linear + GitHub + Codex | Linear 任务到 GitHub PR |
| `linear/github/claude_code` | Linear + GitHub + Claude Code | Linear/GitHub 流程 |
| `linear/github/opencode.canary` | Linear + GitHub + OpenCode canary | OpenCode 试验 |
| `tapd/github/codex` | TAPD + GitHub + Codex | TAPD 任务到 GitHub PR |
| `tapd/cnb/opencode` | TAPD + CNB + OpenCode | TAPD/CNB 流程 |
| `tapd/cnb/claude_code` | TAPD + CNB + Claude Code | TAPD/CNB 流程 |

这些模板连接的是外部系统，不代表 Linear、TAPD、GitHub、CNB 或 Agent 被“内置”在 Maestro 里。

## 该选哪个模板？

| 目标 | 推荐模板 |
| --- | --- |
| 不配置凭据，先理解 Maestro | `memory/no_repo/mock` |
| 用 Codex 跑 TAPD + GitHub 任务 | `tapd/github/codex` |
| 用 OpenCode 跑 TAPD + CNB 任务 | `tapd/cnb/opencode` |
| 用 Codex 跑 Linear + GitHub 任务 | `linear/github/codex` |
| 用 Claude Code 跑 Linear + GitHub 任务 | `linear/github/claude_code` |
| 新增集成 | 从最接近的模板复制修改 |

## 真实模板的注意事项

真实模板可能会：

- 从 TAPD 或 Linear 读取任务；
- clone 或 checkout 目标 Git 仓库；
- 创建分支；
- 推送 commit；
- 创建或更新 PR；
- 写回项目系统评论、状态或链接；
- 运行真实 Coding Agent。

运行真实模板前，请确认：

- 目标项目系统允许被更新；
- 目标仓库是测试仓库或已获批准；
- 凭据权限尽量小；
- `SYMPHONY_WORKSPACE_ROOT` 指向隔离目录；
- 有人知道如何查看、停止和清理运行；
- 重要变更仍然需要人工 review。

## 创建自己的模板

在本目录下创建新的 Markdown 文件，并使用同样的三段式命名：

```text
<tracker>/<source>/<agent-provider>[.<variant>].md
```

模板包含：

1. YAML front matter：运行配置。
2. Markdown 正文：Agent prompt。

简化示例：

```md
---
tracker:
  kind: memory
repo:
  provider:
    kind: memory
agent_provider:
  kind: mock
---

You are working on {{ issue.identifier }}.
Summarize the task and produce a safe local result.
```

## 模板作者检查清单

新增模板前，先回答：

- 任务来自哪个项目系统？
- 是否需要真实 Git 仓库？
- 使用哪个 Agent？
- 需要哪些凭据？
- 是否会写入项目系统、仓库或 PR？
- 适合本地 demo、可信评估、团队试点还是生产运行？
- Agent 应该产出什么？
- 任务完成后应该如何更新状态？
- 失败后如何清理工作区和测试数据？

## 相关文档

- [Elixir 运行时指南](../../../README.zh-CN.md)
- [Operations guide](../../operations.zh-CN.md)
- [Agent provider docs](../../agent_providers/)

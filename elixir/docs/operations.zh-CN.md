# Operations Guide

这份文档面向想在本地 demo 之外运行 Maestro 的人。

核心原则：

```text
先本地体验 -> 再接一个真实系统 -> 观察结果 -> 逐步增加权限。
```

Maestro 可以让 AI Agent 处理真实项目任务和真实 Git 仓库。能力越强，越需要谨慎处理凭据、仓库写入、项目系统更新和日志。

## 运行模式

| 模式 | 使用内容 | 适合场景 |
| --- | --- | --- |
| 本地 demo | 本地模拟任务 + mock agent | 第一次体验和学习 |
| 可信评估 | 测试项目/测试仓库 + 真实 Agent | 验证流程 |
| 团队试点 | 真实项目流程 + 人工 review | 小范围团队使用 |
| 生产运行 | 凭据、监控、审批、清理策略齐全 | 长期运行 |

不要从本地 demo 直接跳到无限制生产运行。

## 运行前先回答这些问题

1. 任务来自 TAPD、Linear 还是本地模拟数据？
2. 目标 Git 仓库在哪里？使用 GitHub、CNB 还是本地模拟代码平台？
3. 使用 Codex、Claude Code、OpenCode 还是 mock？
4. Agent 是否可以修改仓库或推送分支？
5. Agent 是否可以更新项目系统中的状态、评论或链接？
6. 独立工作区创建在哪里？
7. 谁来 review 结果？
8. 如何停止、清理和复盘一次运行？

如果答案不明确，先使用 `memory/no_repo/mock`。

## Runtime 前置条件

使用 `mise` 安装固定版本的 Erlang/Elixir：

```bash
cd elixir
mise trust
mise install
mise exec -- elixir --version
```

常用主机工具：

- `bash`
- `git`
- `gh`，用于 GitHub PR workflow
- 选中的 Agent CLI，例如 Codex、Claude Code、OpenCode
- `./bin/symphony` 或 `SYMPHONY_CLI`

provider 细节见：

```text
elixir/docs/agent_providers/
```

## 兼容命名

对外项目名是 **Maestro**。

当前运行时仍使用一些兼容命名：

- `symphony` CLI
- `SymphonyElixir` 模块名
- `.symphony` 目录
- `SYMPHONY_*` 环境变量

实际配置和运行时请继续使用这些名称。

## 凭据

只提供当前模板需要的凭据。

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

GitHub：

```bash
gh auth status
export SOURCE_REPO_PROVIDER_REPOSITORY=owner/repo
```

CNB：

```bash
export CNB_TOKEN=...
```

仓库输入：

```bash
export SOURCE_REPO_URL=https://github.com/owner/repo.git
export SOURCE_REPO_BASE_BRANCH=main
export SOURCE_REPO_PROVIDER_REPOSITORY=owner/repo
```

尽量使用最小权限凭据，避免把高权限个人 token 用于长期无人值守运行。

## 工作区

每个任务都应该有独立工作区。

接入真实系统前，设置：

```bash
export SYMPHONY_WORKSPACE_ROOT=/path/to/isolated/maestro-workspaces
```

工作区创建在 Maestro 的运行环境中，可以是本机目录、SSH 主机目录或 worker 环境目录。它不是创建在 TAPD、Linear、GitHub 或 CNB 里。

好的工作区做法：

- 使用专用目录；
- 不放在重要本地项目内；
- 每个任务有独立目录和仓库副本；
- 方便查看；
- 方便删除；
- 不和其他自动化混用。

独立工作区的价值：

- 多个任务可以并行执行；
- 不同任务的代码副本、日志和临时文件不会互相影响；
- 失败后可以单独查看和清理；
- reviewer 更容易复盘一次 Agent 执行。

## 安全 rollout 路径

### 第一步：本地 demo

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

目标：确认 runtime、dashboard 和本地任务流程正常。

### 第二步：低风险验证

先使用 smoke test 或一次性任务。

```bash
mix tracker.smoke --template memory/no_repo/mock --issue local-memory-1 --json
```

目标：在不影响真实用户的前提下验证配置。

### 第三步：真实项目系统 + 一次性仓库

使用测试项目、测试仓库或明确批准的 sandbox。

目标：验证真实集成的端到端行为。

### 第四步：团队试点

限制任务范围、review 人、凭据权限和并发量。

目标：了解失败模式，优化模板和 prompt。

### 第五步：生产加固

增加审批、监控、凭据轮换、清理策略和故障处理流程。

## Dashboard 和 API

使用 `--port` 或 `server.port` 开启。

| 路径 | 用途 |
| --- | --- |
| `/` | Dashboard |
| `/issues/:issue_identifier` | 任务详情页 |
| `/api/v1/state` | 运行状态 JSON |
| `/api/v1/<issue_identifier>` | 任务详情 JSON |
| `/api/v1/refresh` | 刷新接口 |

Dashboard 可用于查看：

- 哪些任务正在运行；
- 使用哪个 Agent；
- 最近事件；
- 工作区和 session 状态；
- 最终结果。

## 日志和交付记录

一次运行应该能回答：

- Maestro 为什么启动这个任务？
- 任务来自哪个项目系统？
- 使用了哪个 Git 仓库和分支？
- 使用了哪个模板和 Agent？
- 仓库发生了什么变化？
- Agent 调用了什么工具？
- 是否创建了分支或 PR？
- 哪里失败了？
- 人接下来应该 review 什么？

详细日志和脱敏行为见：

```text
elixir/docs/logging.md
```

## 仓库操作

Repo-backed workflow 可能 clone 仓库、创建分支、推送 commit、打开 PR、检查 checks 或观察合入状态。

开启仓库写入前，请确认：

- 先使用一次性仓库测试；
- base branch 和分支命名正确；
- 仓库权限合适；
- PR 或关键变更需要人工 review；
- 初期不要跳过测试、评审或发布判断。

更多细节见：

```text
elixir/docs/repo_provider.md
```

## Tracker lifecycle

Maestro 需要知道哪些任务状态可以执行，哪些状态应该停止。

| 概念 | 含义 |
| --- | --- |
| Active state | Maestro 可以接手这个任务 |
| Terminal state | Maestro 应该停止或清理这个任务 |
| Route state | workflow 的下一步，例如 planning 或 review |
| Human review state | 需要人检查结果的状态 |

TAPD 的原始 API 状态可能和人看到的流程名不同，需要谨慎配置映射，并先在一次性任务上测试。

## SSH 和 worker 执行

有些 workflow 可以把 Agent 运行在 SSH host 或 worker 服务上，而不是本机。

建议等本地和单机路径稳定后再启用。

启用远程 worker 前，确认：

- SSH 可以无交互认证；
- host key 策略明确；
- workspace root 隔离；
- cleanup 经过测试；
- 并发限制已设置；
- operator 能看到日志和错误。

## 停止和清理清单

运行真实任务前，应该知道如何：

- 停止 Maestro 进程；
- 找到对应任务的工作区；
- 查看日志和 dashboard；
- 撤销或删除测试分支；
- 清理临时工作区；
- 回滚项目系统里的测试状态或评论。

## 相关文档

- [Elixir 运行时指南](../README.zh-CN.md)
- [Workflow templates](../priv/workflow_templates/README.zh-CN.md)
- [Logging guide](./logging.md)
- [Repo provider guide](./repo_provider.md)
- [Testing guide](./testing.md)

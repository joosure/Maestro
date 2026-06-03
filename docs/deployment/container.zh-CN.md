# 容器部署指南：先跑模拟环境，再接真实 workflow

语言：[English](./container.md) | [简体中文](./container.zh-CN.md)

这份文档说明如何用 Docker/Compose 运行 `elixir/` 中的 Maestro/Symphony Elixir OTP runtime。目标是：**新人第一次阅读就能按步骤跑起来，维护者也能清楚理解镜像、配置和安全边界**。

> **命名说明**
>
> 当前产品名是 **Maestro**。由于已有 CLI、镜像入口、模块名和环境变量仍使用旧名称，命令、容器服务、release 名称和环境变量继续保留 `symphony` / `SYMPHONY_*`。这是预期行为，不是文档错误。运行命令时请使用本文里的实际名称。

## 你应该读哪一部分？

| 你的目标 | 建议阅读章节 |
| --- | --- |
| 第一次用容器跑起来，不想准备任何外部账号或 token | 只看[容器 Mock Quickstart](#容器-mock-quickstart) |
| 已经跑通 Quickstart，想理解下一步 | 看[Mock Quickstart 之后怎么走](#8-mock-quickstart-之后怎么走) |
| 接入真实 Linear/GitHub/OpenCode | 看[Linear + GitHub + OpenCode 最小示例](#31-linear--github--opencode-最小示例) |
| 接入真实 Linear/GitHub/Codex | 看[Linear + GitHub + Codex 最小示例](#32-linear--github--codex-最小示例) |
| 接入真实 Linear/GitHub/Claude Code | 看[Linear + GitHub + Claude Code 最小示例](#33-linear--github--claude-code-最小示例) |
| 接入 TAPD/CNB/CodeBuddy Code | 看[TAPD + CNB + CodeBuddy Code 最小示例](#34-tapd--cnb--codebuddy-code-最小示例) |
| 维护 Dockerfile、Compose 或 provider 镜像 | 看[镜像](#镜像) |
| 负责生产发布、安全扫描或平台治理 | 看[运行时安全控制](#运行时安全控制)、[安全注意事项](#安全注意事项)和[附录 B 供应链检查](#附录-b-供应链检查) |
| 修改环境变量、镜像 target 或 provider 版本 | 看[维护者修改检查清单](#维护者修改检查清单)和[附录 C 环境变量参考](#附录-c-环境变量参考) |
| 只想查变量 | 看[附录 C 环境变量参考](#附录-c-环境变量参考) |

如果你不确定该选哪条路径，请从 **容器 Mock Quickstart** 开始。它不需要真实 Tracker、代码仓库、Agent Provider 或模型 API key。

## 概念速览

| 概念 | 含义 |
| --- | --- |
| Tracker | 任务系统，例如 Linear 或 TAPD。 |
| Repo provider | 代码仓库平台，例如 GitHub 或 CNB。 |
| Agent provider | 执行代码任务的 Agent/模型工具，例如 OpenCode、Codex、Claude Code 或 CodeBuddy Code。 |
| Template | 一组 workflow 预设组合，例如 `memory/no_repo/mock` 或 `linear/github/opencode`。 |
| Mock Quickstart | 不连接外部系统的本地模拟流程，用来验证容器镜像、OTP release、HTTP server 和 Dashboard。 |
| OTP release | Elixir 应用的发布包。容器内通过 release 启动，不需要宿主机安装 Mix、Elixir 或 Erlang。 |
| Dashboard | 容器启动后暴露的 Web UI，默认访问 `http://localhost:4000`。 |
| Managed credential | Maestro/Symphony 管理的 Agent Provider 凭据。workflow 中出现 `credential_ref` 时需要初始化；Integration Compose 默认会在启动前自动 login + verify。 |

容器运行路径分为两类：

- **容器 Mock Quickstart**：运行 `memory/no_repo/mock`，不连接真实 Tracker、代码仓库或 Agent Provider，不需要任何外部凭据，适合新人第一次验证 Dashboard、OTP release 和容器运行方式。
- **真实 workflow 集成**：运行真实 workflow template，通过 `.env`、环境变量或只读文件挂载提供 Tracker、代码仓库和 Agent Provider 凭据。它是接入真实系统的容器运行方式，**不等同于完整生产发布标准**。

## 容器 Mock Quickstart

如果你是第一次接触 Maestro/Symphony，或者只想确认容器镜像、OTP release、HTTP server 和 Dashboard 能正常工作，请先走这条路径。

它和[新人端到端运行指引](../../elixir/docs/quickstart/zh-CN.md)推荐的低风险路径一致，都是运行 `memory/no_repo/mock`，但容器版不要求本机安装 Elixir、Erlang 或 `mise`。

### 这条 Quickstart 会运行什么

| 维度 | 值 |
| --- | --- |
| Docker target | `runtime-base` |
| Tracker | `memory` |
| Repo provider | `memory` |
| Agent provider | `mock` |
| Template | `memory/no_repo/mock` |
| 外部凭据 | 不需要 |
| 宿主机端口 | `4000` |

这一步不需要 Linear、TAPD、GitHub、CNB、Codex、Claude Code、OpenCode、模型 API key 或仓库 token。

### 1. 准备 Docker

先安装并启动 Docker：

- macOS/Windows：使用 Docker Desktop，并启用 Compose v2。
- Linux：安装 Docker Engine 和 Docker Compose plugin。

确认 Docker 可用：

```bash
docker --version
docker compose version
```

克隆仓库并进入仓库根目录：

```bash
git clone https://github.com/joosure/Maestro.git maestro
cd maestro
```

如果你已经有仓库，下面所有命令都请在仓库根目录执行，不是在 `elixir/` 目录执行。

### 2. 启动容器 Mock Quickstart

```bash
docker compose -f deploy/compose/compose.quickstart.yml up --build
```

第一次构建可能需要几分钟，因为 Docker 需要下载基础镜像、获取 Hex/Rebar 依赖、编译 Elixir 应用并生成 OTP release。后续构建通常会因为 Docker layer cache 变快。

Mock Quickstart Compose 文件会提供这些运行时配置：

```text
SYMPHONY_TEMPLATE=memory/no_repo/mock
HOST=0.0.0.0
PORT=4000
SYMPHONY_WORKSPACE_ROOT=/workspaces
```

`HOST=0.0.0.0` 是为了让宿主机可以访问容器中的服务；运行时本地安全默认值通常是 `127.0.0.1`。Quickstart 固定把宿主机 `4000` 端口映射到容器内 `4000` 端口。

### 3. 打开 Dashboard

浏览器打开：

```text
http://localhost:4000
```

你应该能看到 Dashboard。终端中也会出现类似输出：

```text
Dashboard: http://127.0.0.1:4000/
MEM-1 [classifying]
Local memory/mock workflow completed one ...
```

容器内运行的是 OTP release 入口：

```text
/app/bin/symphony eval "SymphonyElixir.Release.Runner.serve_from_env()"
```

镜像入口脚本会把默认的 `serve` 命令转换成上面的 release 调用。其他命令会直接传给 `/app/bin/symphony`，因此后文的 `accounts`、`repo-provider smoke` 等运维命令都可以通过 `docker compose run ... symphony <command>` 执行。这里的 `symphony` 是 Compose service 名称，`<command>` 才是传给容器内 release CLI 的参数；宿主机不需要安装 Mix、Elixir，也不需要先构建本地 `elixir/bin/symphony` CLI。

### 4. 验证健康检查和运行状态

另开一个终端，在仓库根目录执行：

```bash
curl -fsS http://localhost:4000/healthz
```

预期结果：

```json
{"status":"ok"}
```

也可以查看当前编排状态：

```bash
curl -fsS http://localhost:4000/api/v1/state
```

如果响应里能看到 `mock`、`memory`、`MEM-1`、issues 或 recent events 等字段，就说明容器 Mock Quickstart 已经正常运行。

### 5. 查看容器状态和日志

查看服务是否 healthy：

```bash
docker compose -f deploy/compose/compose.quickstart.yml ps
```

跟随日志：

```bash
docker compose -f deploy/compose/compose.quickstart.yml logs -f symphony
```

需要排查文件或权限时，可以进入容器：

```bash
docker compose -f deploy/compose/compose.quickstart.yml exec symphony bash
```

容器内常用检查：

```bash
id
ls -la /app /app/.symphony /app/log /workspaces
```

运行用户应是非 root 的 `symphony` 用户，默认 UID/GID 是 `10001:10001`。

### 6. 停止和清理

停止容器但保留 named volumes：

```bash
docker compose -f deploy/compose/compose.quickstart.yml down
```

如果想完全清理本地 quickstart 状态，包括 workspace、runtime state 和日志 volume：

```bash
docker compose -f deploy/compose/compose.quickstart.yml down -v
```

谨慎使用 `down -v`，它会删除 Compose 创建的 Docker volumes。

### 7. 成功标准和常见问题

完成 Quickstart 后，你应该能确认：

- `docker compose -f deploy/compose/compose.quickstart.yml ps` 显示 `symphony` 服务处于 running/healthy；
- 浏览器可以打开 `http://localhost:4000`；
- `curl -fsS http://localhost:4000/healthz` 返回 `{"status":"ok"}`；
- `curl -fsS http://localhost:4000/api/v1/state` 中能看到 `mock`、`memory`、`MEM-1`、issues 或 recent events 等模拟 workflow 状态。

| 现象 | 常见原因 | 处理方式 |
| --- | --- | --- |
| `docker compose` 不存在 | Compose v2 未安装，或 Docker Desktop 未启动 | 启动 Docker Desktop，或安装 Docker Compose plugin |
| 构建时下载基础镜像失败 | 网络或 registry 访问问题 | 网络稳定后重试；公司网络下可配置 registry mirror |
| 获取 Hex/Rebar 依赖失败 | 访问 Hex/Rebar 受限 | 重试，或配置公司代理/镜像 |
| `4000` 端口被占用 | 本机已有服务占用端口 | 停止占用服务；Quickstart Compose 固定使用 `4000:4000`，如需改端口请调整 `compose.quickstart.yml` 的端口映射 |
| Dashboard 打不开 | 容器未启动、仍在构建或不健康 | 运行 `docker compose -f deploy/compose/compose.quickstart.yml ps` 并查看 logs |
| `/healthz` 失败 | HTTP server 未启动或端口不可用 | 查看 logs，确认 `HOST=0.0.0.0` 和 `PORT=4000` |
| `/workspaces` 或 `/app/log` 权限问题 | 老 volume 权限和当前 UID/GID 不一致 | 可以 `down -v` 重建 volume，或用匹配的 `SYMPHONY_UID`/`SYMPHONY_GID` build args 重建镜像 |

### 8. Mock Quickstart 之后怎么走

如果你不确定选哪条，建议按表格从上到下逐步推进。

| 目标 | 下一步 |
| --- | --- |
| 先理解本地 runtime 和真实 workflow 概念 | 阅读[新人端到端运行指引](../../elixir/docs/quickstart/zh-CN.md) |
| 验证 OpenCode 集成镜像，但仍不用真实凭据 | 使用 `SYMPHONY_OPENCODE_TEMPLATE=memory/no_repo/mock` 和 `--profile opencode` |
| 验证 Codex 集成镜像，但仍不用真实凭据 | 使用 `SYMPHONY_CODEX_TEMPLATE=memory/no_repo/mock` 和 `--profile codex` |
| 验证 Claude Code 集成镜像，但仍不用真实凭据 | 使用 `SYMPHONY_CLAUDE_CODE_TEMPLATE=memory/no_repo/mock` 和 `--profile claude-code` |
| 验证 CodeBuddy Code 集成镜像，但仍不用真实凭据 | 使用 `SYMPHONY_CODEBUDDY_TEMPLATE=memory/no_repo/mock` 和 `--profile codebuddy` |
| 接入真实 Linear/GitHub/OpenCode | 准备 `.env`，设置 `SYMPHONY_OPENCODE_TEMPLATE=linear/github/opencode`，再使用 `compose.integration.yml --profile opencode` |
| 接入真实 Linear/GitHub/Codex | 准备 `.env`，设置 `SYMPHONY_CODEX_TEMPLATE=linear/github/codex`，再使用 `compose.integration.yml --profile codex` |
| 接入真实 Linear/GitHub/Claude Code | 准备 `.env`，设置 `SYMPHONY_CLAUDE_CODE_TEMPLATE=linear/github/claude_code`，再使用 `compose.integration.yml --profile claude-code` |
| 接入真实 TAPD/CNB/CodeBuddy Code | 先按[新人端到端运行指引](../../elixir/docs/quickstart/zh-CN.md)准备 TAPD/CNB/CodeBuddy；使用 `compose.integration.yml --profile codebuddy` 构建 `runtime-agent-codebuddy` |
| 准备生产镜像发布 | 看[附录 B 供应链检查](#附录-b-供应链检查)，运行 `scripts/container-security-scan.sh` 并检查 Trivy/SBOM 产物 |

第一次真实集成请使用测试 Tracker、测试仓库、低权限 token 和可丢弃 workspace volume。真实 workflow 可能 clone 仓库、push 分支、创建 PR/MR、修改 Tracker 状态并写评论。

## 真实 workflow 集成

> **注意**
>
> 真实 workflow 会连接真实 Tracker、代码仓库和 Agent Provider，可能读取或更新工单、clone 仓库、创建分支、push 代码、创建或更新 PR/MR、写评论并调用模型 API。第一次验证请使用测试项目、测试仓库、低权限 token 和可删除的 workspace volume。`compose.integration.yml` 必须显式选择 `opencode`、`codex`、`claude-code` 或 `codebuddy` profile，用于验证和运行真实系统集成；是否达到生产发布标准还取决于你的镜像扫描、凭据管理、网络策略、审计、备份、告警和发布流程。

在真实 workflow 集成中，常见组合是：

- Tracker：任务来源，例如 Linear 或 TAPD；
- Repo provider：代码仓库，例如 GitHub 或 CNB；
- Agent provider：实际执行代码任务的工具，例如 OpenCode、Codex、Claude Code 或 CodeBuddy Code；
- Template：把上述系统组合起来的一套预设配置，例如 `linear/github/opencode`。

### 开始前：先做三个选择

真实 workflow 的配置有几个分叉。新人第一次接入时，先按下表选路径，再去复制后面的 `.env` 示例。

| 选择 | 新人推荐 | 什么时候改选 |
| --- | --- | --- |
| Workflow 来源 | 选择 provider profile 对应 template，例如 `SYMPHONY_OPENCODE_TEMPLATE=linear/github/opencode` 或 `SYMPHONY_CODEX_TEMPLATE=linear/github/codex` | 已经按 quickstart 生成本地 workflow 文件，或 workflow 中需要 `credential_ref` 时，改用 `SYMPHONY_WORKFLOW_PATH` |
| Provider 凭据 | 内置 template 没有 `credential_ref` 时，使用 provider 自己的配置文件或环境变量 | workflow 明确使用 `credential://provider/account` 时，改用 managed credential，由启动前 preflight 自动 login + verify |
| Agent 镜像 | 只选择一个 provider profile：`opencode`、`codex`、`claude-code` 或 `codebuddy` | 不要把多个 provider CLI 混进通用 `runtime-agent` 镜像 |

如果你只是第一次接 Linear + GitHub + OpenCode，建议先走内置 template + `OPENCODE_CONFIG` 这条路径。它不需要生成本地 workflow，也不需要先理解 managed credential store。等这条路径跑通后，再按 [附录 A 高级凭据和本地 workflow 文件](#附录-a-高级凭据和本地-workflow-文件)切换到 `SYMPHONY_WORKFLOW_PATH` 和 `credential_ref`。

### 1. 先验证 Agent 集成镜像

`compose.integration.yml` 不再提供无 profile 的默认服务。必须显式选择一个 profile：`--profile opencode`、`--profile codex`、`--profile claude-code` 或 `--profile codebuddy`。每个 profile 都会构建匹配的 `runtime-agent-*` target，并把 provider 专属 template 变量映射成容器内的 `SYMPHONY_TEMPLATE`。所有 provider target 都基于 provider-neutral 的 `runtime-agent` 工具镜像，只额外安装各自需要的固定版本 CLI。

接真实系统前，可以仍然用 mock template 验证对应 provider 镜像能启动。只跑你准备使用的 profile 即可。

OpenCode 镜像：

```bash
SYMPHONY_OPENCODE_TEMPLATE=memory/no_repo/mock docker compose -f deploy/compose/compose.integration.yml --profile opencode up -d --build
curl -fsS http://localhost:4000/healthz
docker compose -f deploy/compose/compose.integration.yml --profile opencode down
```

Codex 镜像：

```bash
SYMPHONY_CODEX_TEMPLATE=memory/no_repo/mock docker compose -f deploy/compose/compose.integration.yml --profile codex up -d --build
curl -fsS http://localhost:4000/healthz
docker compose -f deploy/compose/compose.integration.yml --profile codex down
```

Claude Code 镜像：

```bash
SYMPHONY_CLAUDE_CODE_TEMPLATE=memory/no_repo/mock docker compose -f deploy/compose/compose.integration.yml --profile claude-code up -d --build
curl -fsS http://localhost:4000/healthz
docker compose -f deploy/compose/compose.integration.yml --profile claude-code down
```

CodeBuddy Code 镜像：

```bash
SYMPHONY_CODEBUDDY_TEMPLATE=memory/no_repo/mock docker compose -f deploy/compose/compose.integration.yml --profile codebuddy up -d --build
curl -fsS http://localhost:4000/healthz
docker compose -f deploy/compose/compose.integration.yml --profile codebuddy down
```

### 2. 准备 `.env`

从仓库根目录创建本地 `.env`：

```bash
cp .env.example .env
```

编辑 `.env`，只填写你选择的 template 需要的变量。不要把真实 `.env` 提交到 git。

仓库根目录 `.env` 专门给 Docker Compose 使用，和 `elixir/` 下的本机 quickstart 文件是分开的，例如 `elixir/.env.tapd.local` 和 `elixir/.env.linear.local`。如果你已经按 quickstart 生成了本地 workflow 文件，请继续把 workflow 文件放在 `elixir/quickstart/` 下，并按附录 A 用 `SYMPHONY_WORKFLOW_FILE` 挂载进容器。

`.env.example` 为各 integration profile 分别设置 template：

```env
SYMPHONY_OPENCODE_TEMPLATE=linear/github/opencode
SYMPHONY_CODEX_TEMPLATE=linear/github/codex
SYMPHONY_CLAUDE_CODE_TEMPLATE=linear/github/claude_code
SYMPHONY_CODEBUDDY_TEMPLATE=tapd/cnb/codebuddy_code
```

Docker Compose 会自动读取仓库根目录的 `.env`。不要在 integration profile 中直接复用一个全局 `SYMPHONY_TEMPLATE`；使用 provider 专属变量可以避免选择了 `opencode` profile 却传入 CodeBuddy template 这类错配。只有临时 smoke 测试时，才建议在命令前一次性覆盖，例如 `SYMPHONY_OPENCODE_TEMPLATE=memory/no_repo/mock`。

`compose.integration.yml` 的每个 profile 都会在容器内设置 `SYMPHONY_TEMPLATE` 来启动内置 template。如果你已经按[新人端到端运行指引](../../elixir/docs/quickstart/zh-CN.md)生成了本地 workflow 文件，并且想让容器运行这份文件而不是内置 template，请使用 [附录 A](#附录-a-高级凭据和本地-workflow-文件)的 `SYMPHONY_WORKFLOW_PATH` 方式。

接真实系统前，先自查这三点：

- `.env` 里的 provider 专属 template 变量与所选 profile 匹配，或者已经设置 `SYMPHONY_WORKFLOW_PATH`；
- 只设置 `OPENCODE_CONFIG=./secrets/opencode.json` 不会自动把文件放进容器，还需要打开 `compose.integration.yml` 的 `symphony-opencode` 服务中对应的只读 mount；
- 如果使用 `SYMPHONY_WORKFLOW_PATH`，也需要打开 `SYMPHONY_WORKFLOW_FILE` 对应的只读 mount，让容器内真的存在 `/app/WORKFLOW.local.md`。

### 3. 按 provider 准备 `.env` 示例

下面这些路径是平级的 provider profile 示例。选择 `opencode` profile 时看 3.1；选择 `codex` profile 时看 3.2；选择 `claude-code` profile 时看 3.3；选择 `codebuddy` profile 时看 3.4。

#### 3.1 Linear + GitHub + OpenCode 最小示例

`deploy/compose/compose.integration.yml` 的 `opencode` profile 会把下面这个 `.env` 变量映射成容器内的 `SYMPHONY_TEMPLATE`：

```text
SYMPHONY_OPENCODE_TEMPLATE=linear/github/opencode
```

最小 `.env` 通常包括：

```env
# 必填：选择 OpenCode profile 的 workflow template
SYMPHONY_OPENCODE_TEMPLATE=linear/github/opencode

# 必填：Linear
LINEAR_API_KEY=<linear api key>
LINEAR_PROJECT_SLUG=<linear project slug>

# 必填：目标仓库
SOURCE_REPO_URL=https://github.com/<owner>/<repo>.git
SOURCE_REPO_BASE_BRANCH=main

# 推荐：显式声明 provider repository name，通常是 owner/repo
SOURCE_REPO_PROVIDER_REPOSITORY=<owner>/<repo>

# 必填：OpenCode provider access，二选一
# 方式 A：新人推荐。使用 OpenCode 自己的配置文件；见附录 A 的 OPENCODE_CONFIG 挂载
OPENCODE_CONFIG=./secrets/opencode.json
# 方式 B：使用带 credential_ref 的本地 workflow；见附录 A 的 SYMPHONY_WORKFLOW_PATH 和自动 preflight
# ZAI_API_KEY=<zai api key>

# 二选一：GitHub token。如果不确定，建议只设置其中一个，避免混淆。
GH_TOKEN=<github token>
# GITHUB_TOKEN=<github token>
```

如果 OpenCode 或仓库访问使用文件凭据，可以把 `deploy/compose/compose.integration.yml` 中的只读 mount 打开并调整路径：

```yaml
# - ${OPENCODE_CONFIG:-../../secrets/opencode.json}:/home/symphony/.config/opencode/opencode.json:ro
# - ${SSH_PRIVATE_KEY:-../../secrets/id_rsa}:/home/symphony/.ssh/id_rsa:ro
```

如果 workflow 使用 `credential_ref`，或者你要挂载本地生成的 workflow 文件，请跳到 [附录 A 高级凭据和本地 workflow 文件](#附录-a-高级凭据和本地-workflow-文件)。主流程只保留新人推荐的内置 template + `OPENCODE_CONFIG` 路径。

#### 3.2 Linear + GitHub + Codex 最小示例

`codex` profile 会把下面这个 `.env` 变量映射成容器内的 `SYMPHONY_TEMPLATE`：

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

#### 3.3 Linear + GitHub + Claude Code 最小示例

`claude-code` profile 会把下面这个 `.env` 变量映射成容器内的 `SYMPHONY_TEMPLATE`：

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

#### 3.4 TAPD + CNB + CodeBuddy Code 最小示例

[新人端到端运行指引](../../elixir/docs/quickstart/zh-CN.md)中的另一条新人真实 workflow 是 `tapd/cnb/codebuddy_code`。项目支持 `codebuddy_code` provider，Dockerfile 也提供 `runtime-agent-codebuddy` target：它基于 `runtime-agent`，安装固定版本的 `@tencent-ai/codebuddy-code`，设置 `CODEBUDDY_CONFIG_DIR=/home/symphony/.codebuddy`，并用 `DISABLE_AUTOUPDATER=1` 关闭运行时自动更新，避免镜像运行后版本漂移。

要跑这条路径，请使用 `compose.integration.yml --profile codebuddy`，并设置：

```env
SYMPHONY_CODEBUDDY_TEMPLATE=tapd/cnb/codebuddy_code
TAPD_API_USER=<tapd api user>
TAPD_API_PASSWORD=<tapd api password>
TAPD_WORKSPACE_ID=<tapd workspace id>
CNB_TOKEN=<cnb token>
SOURCE_REPO_URL=https://cnb.cool/<org>/<team>/<repo>
CODEBUDDY_API_KEY=<codebuddy api key，仅首次 credential login 需要>
```

```bash
docker compose -f deploy/compose/compose.integration.yml --profile codebuddy up -d --build
```

如果你的 CodeBuddy 账号需要中国版或 iOA 环境，请设置 `CODEBUDDY_INTERNET_ENVIRONMENT=internal` 或 `CODEBUDDY_INTERNET_ENVIRONMENT=ioa`。如果团队使用自定义 CodeBuddy API endpoint，再设置 `CODEBUDDY_BASE_URL`。首次 managed credential 登录仍请参考[附录 A](#附录-a-高级凭据和本地-workflow-文件)。

### 4. 启动真实 workflow 容器

OpenCode 路径：

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode up -d --build
```

CodeBuddy Code 路径：

```bash
docker compose -f deploy/compose/compose.integration.yml --profile codebuddy up -d --build
```

Codex 路径：

```bash
docker compose -f deploy/compose/compose.integration.yml --profile codex up -d --build
```

Claude Code 路径：

```bash
docker compose -f deploy/compose/compose.integration.yml --profile claude-code up -d --build
```

验证：

```bash
curl -fsS http://localhost:4000/healthz
docker compose -f deploy/compose/compose.integration.yml --profile opencode ps
docker compose -f deploy/compose/compose.integration.yml --profile opencode logs -f symphony-opencode
```

后续命令以 OpenCode profile 为例；如果你走其他路径，把 profile 和服务名改成对应值，例如 `codex` / `symphony-codex`、`claude-code` / `symphony-claude-code` 或 `codebuddy` / `symphony-codebuddy`。

`/healthz` 只说明容器内 HTTP server 已启动，不等于 Tracker、Repo provider 和 Agent provider 凭据都已经验证通过。首次接真实系统时，继续看 logs，确认没有缺少环境变量、CLI 不存在、认证失败或权限不足等错误。

可选做一次 repo provider 只读 smoke。它默认只验证 provider 类型和认证状态，不 clone、不 push、不创建 PR/MR：

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode run --rm --no-deps symphony-opencode \
  repo-provider smoke --provider github --json
```

如果接入 CNB，把 `github` 改成 `cnb`：

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode run --rm --no-deps symphony-opencode \
  repo-provider smoke --provider cnb --json
```

停止：

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode down
```

### 5. 真实 workflow 成功标准

完成首次真实集成验证后，至少确认：

- `.env` 中所选 provider 的 template 变量是目标真实 template，不是 `memory/no_repo/mock`；
- 所选 profile 的服务处于 running/healthy，例如 `symphony-opencode`、`symphony-codex`、`symphony-claude-code` 或 `symphony-codebuddy`；
- `curl -fsS http://localhost:4000/healthz` 返回 `{"status":"ok"}`；
- logs 中没有缺失变量、provider CLI 不存在、认证失败、仓库权限不足或模型 provider 凭据失败；
- repo provider 只读 smoke 通过，或已经按[新人端到端运行指引](../../elixir/docs/quickstart/zh-CN.md)中的对应路径完成等价 smoke；
- 如果 workflow 使用 `credential_ref`，启动日志里能看到 managed credential preflight 通过；这一步会在服务启动前自动完成凭据初始化与校验；
- Dashboard / `/api/v1/state` 不再只出现 `MEM-1`、`mock`、`memory` 等 mock-only 状态；如果真实 Tracker 中已有符合扫描条件的任务，应能看到对应 issue 或 event。

如果真实 Tracker 里暂时没有符合 workflow 扫描条件的任务，Dashboard 可能不会出现新 issue；这不一定是容器错误。此时优先确认 Tracker 项目、状态流转、label/gate 和 token 权限是否与对应 quickstart 文档一致。

### 6. 真实 workflow 风险边界

真实 workflow 属于受信任运行配置，可能执行：

- 读取并更新 Linear/TAPD 工单；
- clone 目标仓库；
- 创建工作分支；
- push 分支；
- 创建或更新 PR/MR；
- 写 Tracker 评论；
- 调用 Agent Provider 和模型 API。

首次验证请使用测试项目、测试仓库和低权限 token，不要直接连接生产 Tracker 或生产仓库。

## 镜像

Dockerfile 暴露分层 runtime target：

| Target | 用途 |
| --- | --- |
| `runtime-base` | 最小 OTP release runtime，用于 mock/local validation。不包含 Mix 或 Elixir toolchain。 |
| `runtime-agent` | Provider-neutral 的 OTP release runtime，加常用 agent/repository 工具，例如 Node.js、`gh`、`ripgrep` 和 Python。它刻意不安装任何具体 Agent Provider CLI。 |
| `runtime-agent-opencode` | OpenCode 专用镜像，基于 `runtime-agent` 构建，并额外安装固定版本 `opencode-ai`。`compose.integration.yml --profile opencode` 使用它。 |
| `runtime-agent-codex` | Codex 专用镜像，基于 `runtime-agent` 构建，并额外安装固定版本 `@openai/codex`。`compose.integration.yml --profile codex` 使用它。 |
| `runtime-agent-claude-code` | Claude Code 专用镜像，基于 `runtime-agent` 构建，并额外安装固定版本 `@anthropic-ai/claude-code`。`compose.integration.yml --profile claude-code` 使用它。 |
| `runtime-agent-codebuddy` | CodeBuddy Code 专用镜像，基于 `runtime-agent` 构建，并额外安装固定版本 `@tencent-ai/codebuddy-code`。`compose.integration.yml --profile codebuddy` 使用它。 |

不要把所有支持的 provider CLI 都塞进 `runtime-agent`。不同 provider CLI 的安装来源、版本节奏、认证目录和供应链风险都不同。更推荐一个 provider 一个最终 target，并在 `compose.integration.yml` 中给每个 provider 一个显式 profile。本仓库内置 OpenCode、Codex、Claude Code 和 CodeBuddy Code 的独立 target；如果以后新增 provider，也应按同样模式新增独立 target、独立 profile 和独立版本 pin。

release 在 build stage 中通过 `mix release symphony --overwrite` 构建，然后复制到 Debian runtime image。因为 release 包含 ERTS，并依赖构建环境的 libc ABI，建议构建镜像和运行镜像保持 Debian 系列一致。

runtime 镜像会创建稳定的非 root 用户 `symphony`，默认 UID/GID 是 `10001:10001`。如果运行平台的 volume 权限需要不同 UID/GID，可以通过 Docker build args 覆盖 `SYMPHONY_UID` 和 `SYMPHONY_GID`。

手动构建：

```bash
docker build -f docker/app/Dockerfile --target runtime-base -t symphony:quickstart .
docker build -f docker/app/Dockerfile --target runtime-agent -t symphony:agent-tools .
docker build -f docker/app/Dockerfile --target runtime-agent-opencode --build-arg OPENCODE_VERSION=1.14.33 -t symphony:agent-opencode .
docker build -f docker/app/Dockerfile --target runtime-agent-codex --build-arg CODEX_VERSION=0.135.0 -t symphony:agent-codex .
docker build -f docker/app/Dockerfile --target runtime-agent-claude-code --build-arg CLAUDE_CODE_VERSION=2.1.158 -t symphony:agent-claude-code .
docker build -f docker/app/Dockerfile --target runtime-agent-codebuddy --build-arg CODEBUDDY_VERSION=2.99.1 -t symphony:agent-codebuddy .
```

`OPENCODE_VERSION`、`CODEX_VERSION`、`CLAUDE_CODE_VERSION` 和 `CODEBUDDY_VERSION` 默认值由 `docker/app/Dockerfile` 中的 build args 定义。本文示例分别使用 `1.14.33`、`0.135.0`、`2.1.158` 和 `2.99.1`；如果更新 provider CLI 版本，请同时检查 Dockerfile、`deploy/compose/compose.integration.yml`、`scripts/container-security-scan.sh`、`.github/workflows/container-security.yml` 和本文示例。可以用 `rg "OPENCODE_VERSION|CODEX_VERSION|CLAUDE_CODE_VERSION|CODEBUDDY_VERSION"` 避免漏改。

生产镜像的 digest pinning、Trivy/SBOM 和 provenance 要求见 [附录 B 供应链检查](#附录-b-供应链检查)。完整环境变量参考见 [附录 C 环境变量参考](#附录-c-环境变量参考)。

## 维护者修改检查清单

修改容器部署相关行为时，至少同步检查：

- `docker/app/Dockerfile`：镜像 target、base image、provider CLI 安装和 build args；
- `deploy/compose/compose.quickstart.yml`：Mock Quickstart 是否仍能无外部凭据启动；
- `deploy/compose/compose.integration.yml`：profile、环境变量、volume mount、默认 template 和 runtime target；
- `.env.example`：安全默认值、变量名称和注释是否与 Compose 一致；
- `scripts/container-security-scan.sh` 和 `.github/workflows/container-security.yml`：扫描 target、build args、触发路径和版本 pin；
- `docs/deployment/container.md` 与本文：中英文文档是否表达同一套运行路径；
- `elixir/docs/quickstart/en.md` 和 `elixir/docs/quickstart/zh-CN.md`：本机 quickstart 的 workflow 名称、生成文件路径和凭据步骤是否仍与容器交接路径一致；
- Elixir 启动入口和测试：如果新增 `SYMPHONY_*` 变量或改变 template/workflow 优先级，补充对应 release runner 或 CLI 测试。

更新 provider CLI 版本、base image digest 或 provider CLI 安装方式时，优先用 `rg "OPENCODE_VERSION|CODEX_VERSION|CLAUDE_CODE_VERSION|CODEBUDDY_VERSION|runtime-agent-|SYMPHONY_WORKFLOW_PATH"` 检查是否存在多处引用。

## 运行时安全控制

Quickstart Compose 和 integration profiles 默认使用：

- 镜像内非 root `symphony` 用户，默认 UID/GID `10001:10001`；
- Docker `init: true`，用于进程回收；
- `no-new-privileges:true`；
- `cap_drop: [ALL]`；
- `stop_grace_period: 30s`；
- 镜像级 `HEALTHCHECK`，访问 `http://127.0.0.1:4000/healthz`。

如果未来某个 provider CLI 确实需要 Linux capability，应记录原因，并只加回必要 capability，而不是直接删除 `cap_drop: [ALL]`。

## Volumes

| Volume | 容器路径 | 用途 |
| --- | --- | --- |
| `symphony-workspaces` | 默认 `/workspaces` | 隔离的 issue/story workspace。 |
| `symphony-state` | `/app/.symphony` | 运行状态；Integration 默认也把 managed credential store 放在 `/app/.symphony/agent_credentials`。 |
| `symphony-logs` | `/app/log` | 运行日志。 |

## 安全注意事项

- 不要把 secrets bake 进镜像。
- 不要把真实 `.env` 提交到 git。
- 使用 `.env`、Docker secrets 或只读文件挂载提供凭据。
- 容器默认以非 root `symphony` 用户运行，UID/GID 为 `10001:10001`。
- 保持 `SYMPHONY_WORKSPACE_ROOT` 与宿主机开发目录隔离。
- 使用真实 Tracker、仓库或 Provider 凭据前，请先 review workflow template。
- 会启用广泛文件系统、仓库、Tracker 或 Provider 权限的 template 只应在受信任环境运行。

## 清理

停止 quickstart：

```bash
docker compose -f deploy/compose/compose.quickstart.yml down
```

删除 quickstart volumes：

```bash
docker compose -f deploy/compose/compose.quickstart.yml down -v
```

停止真实集成容器：

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode down
```

如需删除真实集成使用的 named volumes，也可以执行：

```bash
docker compose -f deploy/compose/compose.integration.yml --profile opencode down -v
```

谨慎使用 `down -v`，它会删除 Compose 创建的 Docker volumes，包括 workspace、runtime state 和日志。

## 附录 A 高级凭据和本地 workflow 文件

容器里有两种 Agent Provider 凭据方式，先选一种，不要混用：

| 方式 | 适合场景 | 要做什么 |
| --- | --- | --- |
| Provider 自己的配置文件 | 使用内置 `linear/github/opencode` template，或团队已经有 OpenCode 配置文件 | 打开 `compose.integration.yml` 的 `symphony-opencode` 服务里的 `OPENCODE_CONFIG` 只读挂载，让 OpenCode CLI 自己读取配置 |
| Maestro managed credential | workflow 中有 `credential_ref`，例如 `credential://opencode/zai`、`credential://codex/default`、`credential://claude_code/default` 或 `credential://codebuddy_code/default` | 在 `.env` 提供对应 API key；`compose.integration.yml` 默认会在服务启动前自动执行 login + verify preflight |

`compose.integration.yml` 的各 integration profile 默认把 managed credential store 放在：

```text
/app/.symphony/agent_credentials
```

这个路径位于 `symphony-state` named volume 中，容器重建后仍会保留。可通过 `.env` 覆盖：

```env
SYMPHONY_AGENT_CREDENTIALS_STORE_ROOT=/app/.symphony/agent_credentials
SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT=auto
```

`SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT=auto` 是 Integration Compose 的默认值。容器启动时会先解析当前 `SYMPHONY_TEMPLATE` 或 `SYMPHONY_WORKFLOW_PATH`，只有发现 `agent_provider.options.credential_ref` 时才会处理 managed credential。有对应 API key 时，preflight 会创建/更新 credential 后校验可用性；没有 API key 时，会直接验证 named volume 中已经持久化的 credential。如果 workflow 没有 `credential_ref`，preflight 会跳过；如果设置为 `required`，没有 `credential_ref` 也会失败；如果确实要完全关闭，可设为 `off`。

CodeBuddy Code 的内置 `tapd/cnb/codebuddy_code` template 默认使用 `credential://codebuddy_code/default`。首次启动空 credential store 时，需要在 `.env` 中提供 `CODEBUDDY_API_KEY`，容器启动前会自动写入并校验这份 `default` credential。credential 已写入 `symphony-state` named volume 后，后续重启可以不再长期保留 API key；preflight 会验证已有 credential。如果你的 CodeBuddy 账号需要内网或 IOA 环境，设置：

```env
CODEBUDDY_INTERNET_ENVIRONMENT=internal
# 或
# CODEBUDDY_INTERNET_ENVIRONMENT=ioa
```

如果你使用内置 `linear/github/opencode` template，它默认不带 `credential_ref`，因此不需要 managed credential preflight；请使用 OpenCode 自己的配置文件、环境变量或你们团队批准的认证方式。如果你改用带 `credential://opencode/zai` 的本地 workflow，`.env` 中提供 `ZAI_API_KEY` 后，启动前 preflight 会自动登录并验证。OpenCode 使用非 ZAI 账号时，可通过 `SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME` 指定 managed credential 注入给 OpenCode 的环境变量名。

内置 `linear/github/codex` 和 `linear/github/claude_code` template 通常直接从环境变量读取 provider token：Codex 使用 `OPENAI_API_KEY`，Claude Code 使用 `CLAUDE_CODE_OAUTH_TOKEN`。如果你改用带 `credential://codex/default` 或 `credential://claude_code/default` 的本地 workflow，启动前 preflight 也会按同一套机制自动写入并验证 managed credential。

如果你使用 quickstart 初始化脚本生成的本地 workflow，并且这份 workflow 带 `credential_ref`，先在 `.env` 中设置：

```env
SYMPHONY_WORKFLOW_PATH=/app/WORKFLOW.local.md
# OpenCode:
SYMPHONY_WORKFLOW_FILE=./elixir/quickstart/WORKFLOW.linear-github-opencode.local.md
# CodeBuddy Code:
# SYMPHONY_WORKFLOW_FILE=./elixir/quickstart/WORKFLOW.tapd-cnb-codebuddy.local.md
```

然后打开 `deploy/compose/compose.integration.yml` 中所选服务对应的只读挂载：OpenCode 用 `symphony-opencode`，Codex 用 `symphony-codex`，Claude Code 用 `symphony-claude-code`，CodeBuddy Code 用 `symphony-codebuddy`。

```yaml
# - ${SYMPHONY_WORKFLOW_FILE:?set SYMPHONY_WORKFLOW_FILE to the selected provider workflow file}:/app/WORKFLOW.local.md:ro
```

`SYMPHONY_WORKFLOW_PATH` 有值时，容器会优先运行该 workflow 文件；否则才使用 `SYMPHONY_TEMPLATE`。启动前 preflight 和服务运行使用同一个解析结果，因此 credential store 不会出现“登录写到一个路径、运行读取另一个路径”的问题。

正常路径不需要在文档中手动执行账号命令。启动失败时优先看容器日志中的 `Managed credential preflight failed` 提示：如果是首次初始化或轮换凭据，补齐 `CODEBUDDY_API_KEY`、`ZAI_API_KEY`、`OPENAI_API_KEY`、`CLAUDE_CODE_OAUTH_TOKEN` 或对应 `SYMPHONY_*_TOKEN_ENV` 指向的变量后重新 `docker compose up`；如果是 CodeBuddy 内网或 IOA 环境，设置 `CODEBUDDY_INTERNET_ENVIRONMENT=internal` 或 `CODEBUDDY_INTERNET_ENVIRONMENT=ioa` 后重启。

## 附录 B 供应链检查

本地或 CI 发布生产镜像前运行：

```bash
scripts/container-security-scan.sh
```

脚本默认构建 `runtime-agent-opencode`，运行 Trivy `HIGH,CRITICAL` 漏洞门禁，并输出 Trivy JSON 与 Syft SPDX/CycloneDX SBOM。可以用 `CONTAINER_SECURITY_TARGET` 扫描其他 provider 镜像，例如 `runtime-agent-codex`、`runtime-agent-claude-code` 或 `runtime-agent-codebuddy`。

常用覆盖：

```bash
CONTAINER_SECURITY_TARGET=runtime-base scripts/container-security-scan.sh
CONTAINER_SECURITY_TARGET=runtime-agent-codex scripts/container-security-scan.sh
CONTAINER_SECURITY_TARGET=runtime-agent-claude-code scripts/container-security-scan.sh
CONTAINER_SECURITY_TARGET=runtime-agent-codebuddy scripts/container-security-scan.sh
CONTAINER_SECURITY_IMAGE=registry.example.com/symphony:candidate scripts/container-security-scan.sh
TRIVY_SEVERITY=CRITICAL scripts/container-security-scan.sh
```

PR 修改 Docker、Compose、Elixir release 或容器部署文档相关文件时，`.github/workflows/container-security.yml` 会构建 `runtime-base`、`runtime-agent`、`runtime-agent-opencode`、`runtime-agent-codex`、`runtime-agent-claude-code` 和 `runtime-agent-codebuddy`，运行 Trivy，并上传 SBOM artifacts。

严格生产 CI 建议使用 digest-pinned base images：

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

生产 CI 建议同时要求：

- `ELIXIR_IMAGE` 和 `RUNTIME_IMAGE` 使用 digest pinning；
- 保留 `trivy-image.json`、`sbom.spdx.json` 和 `sbom.cyclonedx.json` artifacts；
- 扫描通过后对镜像做签名和 provenance，例如 Cosign/Sigstore；
- 在镜像仓库启用持续漏洞监控。

## 附录 C 环境变量参考

### 按 template 的最小变量

| Template | 适用场景 | 最小变量 |
| --- | --- | --- |
| `memory/no_repo/mock` | Mock Quickstart / 本地验证 | 不需要外部凭据；Quickstart Compose 已设置 `SYMPHONY_TEMPLATE=memory/no_repo/mock` |
| `linear/github/opencode` | Linear + GitHub + OpenCode | `SYMPHONY_OPENCODE_TEMPLATE` 或 `SYMPHONY_WORKFLOW_PATH`、`LINEAR_API_KEY`、`LINEAR_PROJECT_SLUG`、`SOURCE_REPO_URL`、`SOURCE_REPO_BASE_BRANCH`、`GH_TOKEN` 或 `GITHUB_TOKEN`；OpenCode 凭据用 `OPENCODE_CONFIG`、OpenCode 可读取的环境变量，或带 `credential_ref` 的 workflow + `ZAI_API_KEY` 自动 preflight；推荐设置 `SOURCE_REPO_PROVIDER_REPOSITORY` |
| `linear/github/codex` | Linear + GitHub + Codex | `SYMPHONY_CODEX_TEMPLATE` 或 `SYMPHONY_WORKFLOW_PATH`、`LINEAR_API_KEY`、`LINEAR_PROJECT_SLUG`、`SOURCE_REPO_URL`、`SOURCE_REPO_BASE_BRANCH`、`GH_TOKEN` 或 `GITHUB_TOKEN`、`OPENAI_API_KEY`；使用 `compose.integration.yml --profile codex` / `runtime-agent-codex` |
| `linear/github/claude_code` | Linear + GitHub + Claude Code | `SYMPHONY_CLAUDE_CODE_TEMPLATE` 或 `SYMPHONY_WORKFLOW_PATH`、`LINEAR_API_KEY`、`LINEAR_PROJECT_SLUG`、`SOURCE_REPO_URL`、`SOURCE_REPO_BASE_BRANCH`、`GH_TOKEN` 或 `GITHUB_TOKEN`、`CLAUDE_CODE_OAUTH_TOKEN`；使用 `compose.integration.yml --profile claude-code` / `runtime-agent-claude-code` |
| `tapd/cnb/codebuddy_code` | TAPD + CNB + CodeBuddy Code | `SYMPHONY_CODEBUDDY_TEMPLATE` 或 `SYMPHONY_WORKFLOW_PATH`、`TAPD_API_USER`、`TAPD_API_PASSWORD`、`TAPD_WORKSPACE_ID`、`CNB_TOKEN`、`SOURCE_REPO_URL`、`CODEBUDDY_API_KEY`；使用 `compose.integration.yml --profile codebuddy` / `runtime-agent-codebuddy`；默认会自动完成 managed credential preflight |

### 常用变量

| 变量 | 是否必需 | 说明 |
| --- | --- | --- |
| `SYMPHONY_PORT` | Integration 可选 | Dashboard 宿主机端口，`compose.integration.yml` 的 profile 默认 `4000`。Quickstart Compose 固定使用 `4000:4000`。 |
| `PORT` | 通常不需要手动设置 | 容器内应用监听端口，Compose 默认设置为 `4000`。镜像 `HEALTHCHECK` 也使用该端口。 |
| `HOST` | 通常不需要手动设置 | 容器内应用监听地址，Compose 设置为 `0.0.0.0`，以便宿主机访问容器服务。 |
| `SYMPHONY_OPENCODE_TEMPLATE` | OpenCode profile 需要 | OpenCode profile 的 workflow template alias，默认 `linear/github/opencode`。Compose 会把它映射成容器内 `SYMPHONY_TEMPLATE`。 |
| `SYMPHONY_CODEX_TEMPLATE` | Codex profile 需要 | Codex profile 的 workflow template alias，默认 `linear/github/codex`。Compose 会把它映射成容器内 `SYMPHONY_TEMPLATE`。 |
| `SYMPHONY_CLAUDE_CODE_TEMPLATE` | Claude Code profile 需要 | Claude Code profile 的 workflow template alias，默认 `linear/github/claude_code`。Compose 会把它映射成容器内 `SYMPHONY_TEMPLATE`。 |
| `SYMPHONY_CODEBUDDY_TEMPLATE` | CodeBuddy profile 需要 | CodeBuddy profile 的 workflow template alias，默认 `tapd/cnb/codebuddy_code`。Compose 会把它映射成容器内 `SYMPHONY_TEMPLATE`。 |
| `SYMPHONY_TEMPLATE` | 通常不直接设置 | 容器内实际读取的 workflow template 变量。使用 integration profiles 时由 provider 专属变量生成；直接设置全局 `SYMPHONY_TEMPLATE` 容易造成 profile/template 错配。 |
| `SYMPHONY_WORKFLOW_PATH` | 可选 | 容器内 workflow 文件路径。有值时优先于 `SYMPHONY_TEMPLATE`，例如 `/app/WORKFLOW.local.md`。 |
| `SYMPHONY_WORKFLOW_FILE` | 可选 | 宿主机 workflow 文件路径，用于只读挂载到 `SYMPHONY_WORKFLOW_PATH`。 |
| `SYMPHONY_WORKSPACE_ROOT` | 推荐 | 容器内 workspace root，默认 `/workspaces`。 |
| `SYMPHONY_AGENT_CREDENTIALS_STORE_ROOT` | 推荐 | Managed credential store 路径，Integration Compose 默认 `/app/.symphony/agent_credentials`。 |
| `SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT` | 推荐 | Integration Compose 默认 `auto`。有 `credential_ref` 时，容器启动前自动创建/更新并验证 managed credential；没有 API key 时会验证已持久化的 credential。可设为 `off` 或 `required`。 |
| `SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT_VERIFY_MODE` | 可选 | 默认 `auth`，credential login 后会执行最小 non-interactive provider probe，可能产生一次很小的 provider API/model 调用。设为 `command` 时只做 provider command 级检查。 |
| `SYMPHONY_AGENT_CREDENTIAL_PREFLIGHT_VERIFY_PROMPT` | 可选 | `auth` preflight probe 使用的 prompt，默认 `Reply with exactly OK.`。 |
| `SYMPHONY_AGENT_CREDENTIAL_ACCOUNT_ID` | 可选 | 当 workflow 使用 credential pool 引用而不是具体账号 id 时，指定容器 preflight 要初始化的账号 id。常规 `credential://provider/id` 不需要。 |

### Tracker 凭据

| 变量 | 用途 |
| --- | --- |
| `LINEAR_API_KEY` | Linear templates |
| `LINEAR_PROJECT_SLUG` | Linear templates |
| `TAPD_API_USER` | TAPD templates |
| `TAPD_API_PASSWORD` | TAPD templates |
| `TAPD_WORKSPACE_ID` | TAPD templates |
| `TAPD_COMMENT_AUTHOR` | 可选 TAPD 评论作者覆盖。 |
| `TAPD_WORKITEM_TYPE_ID` | 可选 TAPD Story / workitem 类型过滤，用于 TAPD workflow 准备。 |

### 仓库输入

| 变量 | 说明 |
| --- | --- |
| `SOURCE_REPO_URL` | 目标仓库 clone URL。 |
| `SOURCE_REPO_BASE_BRANCH` | 基线分支，通常是 `main`。 |
| `SOURCE_REPO_BRANCH_WORK_PREFIX` | 可选工作分支前缀，quickstart 示例使用 `maestro/`。 |
| `SOURCE_REPO_PROVIDER_REPOSITORY` | 可选显式 provider repository name，例如 GitHub 的 `<owner>/<repo>`。 |
| `SOURCE_REPO_PROVIDER_REQUIRED_PR_LABEL` | 可选 GitHub PR label enforcement。 |
| `GH_TOKEN` | GitHub token。与 `GITHUB_TOKEN` 二选一即可；建议只设置一个，避免混淆。 |
| `GITHUB_TOKEN` | GitHub token。与 `GH_TOKEN` 二选一即可；建议只设置一个，避免混淆。 |
| `CNB_TOKEN` | CNB token。 |
| `CNB_GIT_USER_NAME` | 可选 CNB workspace 中配置的 Git author name。 |
| `CNB_GIT_USER_EMAIL` | 可选 CNB workspace 中配置的 Git author email。 |

### Provider 凭据和构建变量

| 变量 | 说明 |
| --- | --- |
| `ZAI_API_KEY` | 使用 `credential://opencode/zai` managed credential 时，容器启动前 preflight 可读取的 ZAI token。首次写入或轮换 credential 时需要。 |
| `SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME` | OpenCode managed credential 可选覆盖。默认按账号 id 推断：`zai` -> `ZAI_API_KEY`、`openrouter` -> `OPENROUTER_API_KEY`、`anthropic` -> `ANTHROPIC_API_KEY`、`google` / `gemini` -> `GOOGLE_GENERATIVE_AI_API_KEY`。 |
| `SYMPHONY_OPENCODE_TOKEN_ENV` | OpenCode managed credential 可选覆盖。默认从 `SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME` 指向的同名环境变量读取 token。未知 OpenCode 账号 id 仍必须设置 `SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME`。 |
| `CODEBUDDY_API_KEY` | 使用 `credential://codebuddy_code/default` managed credential 时，容器启动前 preflight 可读取的 CodeBuddy Code API key。首次写入或轮换 credential 时需要。 |
| `SYMPHONY_CODEBUDDY_TOKEN_ENV` | CodeBuddy managed credential 可选覆盖，默认 `CODEBUDDY_API_KEY`。 |
| `CODEBUDDY_INTERNET_ENVIRONMENT` | CodeBuddy Code 可选网络环境；中国版常用 `internal`，iOA 环境用 `ioa`，海外/默认场景可留空。 |
| `CODEBUDDY_BASE_URL` | CodeBuddy Code 可选自定义 API endpoint。多数场景不需要设置。 |
| `CODEBUDDY_CONFIG_DIR` | CodeBuddy Code 配置目录，`runtime-agent-codebuddy` 默认 `/home/symphony/.codebuddy`，Compose 会用 named volume 持久化。 |
| `OPENAI_API_KEY` | 使用 `credential://codex/default` managed credential 时，容器启动前 preflight 可读取的 Codex API key。首次写入或轮换 credential 时需要。 |
| `SYMPHONY_CODEX_TOKEN_ENV` | Codex managed credential 可选覆盖，默认 `OPENAI_API_KEY`。 |
| `SYMPHONY_CODEX_VERIFY_COMMAND` | Codex verify command 可选覆盖，默认 `codex`。 |
| `CODEX_HOME` | Codex 配置目录，`runtime-agent-codex` 默认 `/home/symphony/.codex`，Compose 会用 named volume 持久化。 |
| `CLAUDE_CODE_OAUTH_TOKEN` | 使用 `credential://claude_code/default` managed credential 时，容器启动前 preflight 可读取的 Claude Code OAuth token。Claude Code managed credential 使用这个 token 形态，不是 `ANTHROPIC_API_KEY`。 |
| `SYMPHONY_CLAUDE_CODE_TOKEN_ENV` | Claude Code managed credential 可选覆盖，默认 `CLAUDE_CODE_OAUTH_TOKEN`。 |
| `SYMPHONY_CLAUDE_CODE_VERIFY_COMMAND` | Claude Code verify command 可选覆盖，默认 `claude`。 |
| `CLAUDE_CONFIG_DIR` | Claude Code 配置目录，`runtime-agent-claude-code` 默认 `/home/symphony/.claude`，Compose 会用 named volume 持久化。 |
| `ANTHROPIC_API_KEY` | OpenCode managed credential 或选定 provider 使用 Anthropic-compatible API access 时可选。 |
| `OPENROUTER_API_KEY` | OpenCode managed credential 使用 OpenRouter 时可选。 |
| `GOOGLE_GENERATIVE_AI_API_KEY` | OpenCode managed credential 使用 Google Gemini 时可选。 |
| `OPENCODE_CONFIG` | 可选本地文件路径，挂载到 `/home/symphony/.config/opencode/opencode.json`。 |
| `SSH_PRIVATE_KEY` | 可选本地 SSH 私钥路径，挂载到 `/home/symphony/.ssh/id_rsa`。 |
| `OPENCODE_VERSION` | 构建 `runtime-agent-opencode` 时使用的 OpenCode CLI 版本，默认值见 `docker/app/Dockerfile`。 |
| `CODEX_VERSION` | 构建 `runtime-agent-codex` 时使用的 Codex CLI 版本，默认值见 `docker/app/Dockerfile`。 |
| `CLAUDE_CODE_VERSION` | 构建 `runtime-agent-claude-code` 时使用的 Claude Code CLI 版本，默认值见 `docker/app/Dockerfile`。 |
| `CODEBUDDY_VERSION` | 构建 `runtime-agent-codebuddy` 时使用的 CodeBuddy Code CLI 版本，默认值见 `docker/app/Dockerfile`。 |

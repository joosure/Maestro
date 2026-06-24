# Platform Workflow Template Assets

This directory contains platform-owned workflow template assets. It is not the
global template directory for every workflow extension.

Current platform-owned aliases:

```text
memory/no_repo/mock
```

Registered workflow extensions may contribute additional template assets from
their own asset roots, for example
`priv/workflow_extensions/<extension-id>/templates/`. Those extension-owned
templates are selected with the same CLI `--template <alias>` option, but the
assets do not live in this directory.

The following block lists every currently registered alias across platform and
built-in extensions. Tests use this as a documentation contract.

Current aliases:

```text
memory/no_repo/mock
linear/github/codex
linear/github/claude_code
linear/github/codebuddy_code
linear/github/opencode
tapd/cnb/opencode
tapd/cnb/claude_code
tapd/cnb/codebuddy_code
tapd/github/codex
```

See [`../workflow_extensions/README.md`](../workflow_extensions/README.md) for
the built-in extension asset boundary.

## Runtime Asset Boundary

`priv/` is used for release-safe runtime assets. It is not a platform business
context and must not contain extension execution logic, provider adapters,
readiness rules, storage adapters, or registration code. Built-in extensions may
keep Markdown templates and prompt partials under `priv/workflow_extensions/`;
future external plugin applications should keep their assets in their own OTP
application `priv/` directory.

Template assets are configuration and prompt artifacts, not plugin code. Runtime
registration happens through trusted Elixir extension contributions today and
can be replaced by trusted plugin manifests later. Extension-owned template
catalogs contribute public `Workflow.Template.Entry` records through
`Workflow.Template.entry!/1`, while registry internals stay platform-owned.
Repository-authored template front matter may select registered profile/template
identities, but it must not register Elixir modules or become the authority for
route, readiness, approval, completion, or typed-tool safety decisions.

## Alias Shape

Template aliases are registered asset aliases without the `.md` extension. New
templates should use this stable three-segment structure:

```text
<tracker>/<source>/<agent-provider>[.<variant>].md
```

Segments:

- `tracker`: the issue/story system that drives orchestration, such as `linear`,
  `tapd`, or `memory`.
- `source`: the workflow's external work source. Use repo provider names such as
  `github` or `cnb` for workflows that clone, push, open PRs, or merge code.
  Use `no_repo` for workflows that do not perform repo clone, push, PR, or merge
  operations.
- `agent-provider`: the canonical agent runtime/provider kind, such as `codex`,
  `opencode`, `claude_code`, `codebuddy_code`, or `mock`.
- `variant`: optional detail for a specialized template that shares the same
  tracker, source, and agent provider.

## Prompt Partials

Prompt partials live under `_partials/` beside the owning template assets. A
platform-owned template may use `_partials/` under this directory if needed.
Extension-owned templates use `_partials/` under their own asset root.

Partial includes are expanded by `SymphonyElixir.Workflow.load/1` before the
prompt is parsed by Solid. Includes are intentionally restricted to Markdown
files under the registered asset root's `_partials/`, so shared runtime guidance
can be maintained without allowing arbitrary filesystem reads.

Use partials sparingly. A partial should be a stable contract or flow shared by
more than one template in the same owning asset root. Keep one-off,
experimental, agent-provider-specific, and workflow-alias-only text inline in
the concrete workflow template.

## Composition Pattern

- Concrete workflow templates own the front matter, issue/story context,
  provider runtime section, workspace boundary, and top-level section headings.
- Concrete workflow templates answer when the current issue should do work:
  route-policy handling, handoff/rework/merge behavior, completion bars,
  tracker/repo-provider pairing, and agent-provider runtime prerequisites.
  They should not restate detailed typed-tool argument schemas that are already
  owned by bundled skills or runtime schemas.
- Bundled skills under `priv/workspace_automation/skills/` answer how a class
  of action is performed: typed capability semantics, argument shape, access
  boundaries, helper/diagnostics path rules, and safe operational recipes.
- Runtime code and typed-tool schemas enforce non-negotiable invariants such as
  workpad identity, typed tool validation, gate failure policy, candidate
  lifecycle, and provider adapter behavior. Prompt prose may explain these
  invariants to the agent, but must not be the only enforcement layer.

## Rendering

To inspect the final expanded prompt body for a template alias, run:

```sh
mix symphony.workflow.render memory/no_repo/mock
```

To inspect the original front matter followed by the expanded prompt body, run:

```sh
mix symphony.workflow.render --with-front-matter-source memory/no_repo/mock
```

## Safety Notes

`memory/no_repo/mock` is the local Quick Start template. It uses the memory
tracker, memory repo provider, and mock agent provider, so it starts without
Linear, GitHub, CNB, Codex, Claude Code, OpenCode, CodeBuddy Code, or any other
external credentials.

## 中文说明

Workflow template 可以理解成 Maestro 的“运行配方”。

本目录只放平台拥有的模板资产，不再是所有 workflow extension 的全局模板目录。

当前平台拥有的 alias：

```text
memory/no_repo/mock
```

内置 workflow extension 可以从自己的 asset root 贡献额外模板，例如
`priv/workflow_extensions/<extension-id>/templates/`。这些模板仍然通过统一的
`--template <alias>` 选择，但资产不放在本目录。

当前平台与内置 extension 合计注册的 alias：

```text
memory/no_repo/mock
linear/github/codex
linear/github/claude_code
linear/github/codebuddy_code
linear/github/opencode
tapd/cnb/opencode
tapd/cnb/claude_code
tapd/cnb/codebuddy_code
tapd/github/codex
```

内置 extension 资产边界见
[`../workflow_extensions/README.md`](../workflow_extensions/README.md)。

### 运行期资产边界

这里使用 `priv/` 是因为模板和 partial 是运行期资产，不是 Elixir 编译模块。
`priv/` 不是平台业务 context，不应放 extension 执行逻辑、注册逻辑、provider
adapter、readiness rule 或 storage adapter。

`priv/workflow_extensions/` 只适合放内置 extension 的 Markdown 模板、prompt
partial 等静态资产。未来如果某个内置 extension 拆成外部 plugin，应把资产迁到
该 plugin 自己的 OTP app `priv/` 目录，并通过 manifest 或 registry source 注册。

模板资产是配置和 prompt 资产，不是 plugin 代码。当前由可信 Elixir extension
contribution 注册；未来可以替换为可信 plugin manifest。仓库里的 `WORKFLOW.md`
可以选择已注册的 profile/template identity，但不能注册 Elixir 模块，也不能成为
route、readiness、approval、completion 或 typed-tool safety 决策的权威来源。

### 模板命名规则

模板 alias 的格式是：

```text
<tracker>/<source>/<agent-provider>[.<variant>]
```

| 片段 | 含义 | 示例 |
| --- | --- | --- |
| `tracker` | 提供任务的项目系统或本地模拟任务源 | `linear`、`tapd`、`memory` |
| `source` | 仓库或代码平台来源；没有真实仓库时使用 `no_repo` | `github`、`cnb`、`no_repo` |
| `agent-provider` | 执行任务的 AI Agent 或本地 mock | `codex`、`claude_code`、`opencode`、`codebuddy_code`、`mock` |
| `variant` | 可选的特殊版本 | `canary` |

### 推荐从这里开始

第一次运行建议使用：

```bash
./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  --template memory/no_repo/mock \
  --port 4000
```

这个模板不需要外部账号或凭据，适合安全体验 Maestro 的基本流程。

### Prompt partial

Prompt partial 应放在拥有该模板的 asset root 的 `_partials/` 下。平台模板如果需要
partial，可以使用本目录下的 `_partials/`；extension 模板应使用该 extension 自己
asset root 下的 `_partials/`。

`SymphonyElixir.Workflow.load/1` 会在 Solid 解析 prompt 前展开 partial。Include
被限制在注册 asset root 的 `_partials/` 下，避免任意文件读取。

### 模板职责

- 具体 workflow template 负责 front matter、issue/story context、provider runtime
  section、workspace boundary 和顶层 heading。
- 具体 workflow template 回答当前 issue 什么时候应该执行工作：route policy、
  handoff/rework/merge 行为、completion bar、tracker/repo-provider 组合和
  agent-provider runtime 前置条件。
- 模板不应重复 bundled skills 或 runtime schema 已经拥有的 typed-tool 参数细节。
- `priv/workspace_automation/skills/` 负责说明一类动作如何执行。
- runtime code 和 typed-tool schema 负责强制执行不可协商的不变量。

### 渲染

查看模板 alias 的最终展开 prompt：

```sh
mix symphony.workflow.render memory/no_repo/mock
```

查看原始 front matter 和展开后的 prompt：

```sh
mix symphony.workflow.render --with-front-matter-source memory/no_repo/mock
```

### 安全说明

`memory/no_repo/mock` 是本地 Quick Start 模板。它使用 memory tracker、memory
repo provider 和 mock agent provider，因此不需要 Linear、GitHub、CNB、Codex、
Claude Code、OpenCode、CodeBuddy Code 或其他外部凭据。

### 创建自己的模板

平台模板可以在本目录下创建新的 Markdown 文件。具体 workflow extension 的模板
应放在该 extension 自己的模板资产目录，并通过 extension 注册。

### 相关文档

- [Elixir 运行时指南](../../README.zh-CN.md)
- [Operations guide](../../docs/operations.zh-CN.md)
- [Agent provider docs](../../docs/agent_providers/)

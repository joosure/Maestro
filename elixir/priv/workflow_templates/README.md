# Workflow Templates

Bundled workflow templates live under this directory and are selected with the
CLI `--template` option.

Template aliases are the relative path below this directory without the `.md`
extension. New templates should use this stable three-segment structure:

```text
<tracker>/<source>/<agent-provider>[.<variant>].md
```

Segments:

- `tracker`: the issue/story system that drives orchestration, such as `linear`
  or `tapd`.
- `source`: the workflow's external work source. Use repo provider names such as
  `github` or `cnb` for workflows that clone, push, open PRs, or merge code.
  Use `no_repo` for workflows that do not perform repo clone, push, PR, or merge
  operations.
- `agent-provider`: the canonical agent runtime/provider kind, such as `codex`,
  `opencode`, `claude_code`, or `codebuddy_code`. The Elixir runtime owns these
  strings and supported aliases in `SymphonyElixir.AgentProvider.Kinds`.
- `variant`: optional detail for a specialized template that shares the same
  tracker, source, and agent provider. Keep variants as a suffix on the file
  name, for example `opencode.canary.md`, before adding another directory level.

Current aliases:

```text
memory/no_repo/mock
tapd/cnb/opencode
tapd/cnb/claude_code
tapd/cnb/codebuddy_code
tapd/github/codex
linear/github/codex
linear/github/claude_code
linear/github/codebuddy_code
linear/github/opencode.canary
```

Template safety notes:

- `memory/no_repo/mock` is the local Quick Start template. It uses the memory
  tracker, memory repo provider, and mock agent provider, so it starts without
  Linear, GitHub, CNB, Codex, Claude Code, OpenCode, or any other external
  credentials.
- `linear/github/codex` and `tapd/github/codex` run Codex with
  `approval_policy: never` and a `danger-full-access` sandbox. Use them only in
  trusted evaluation or production environments whose repository, tracker, and
  credential boundaries are explicitly prepared for unattended write access.
- `tapd/cnb/claude_code` and `linear/github/claude_code` run Claude Code with
  `bypassPermissions`; treat them as the same trusted-environment class.
- `linear/github/codebuddy_code` and `tapd/cnb/codebuddy_code` run CodeBuddy
  Code over ACP stdio with `permission_mode: bypass_permissions`,
  session-scoped generated MCP Dynamic Tools, and a managed credential
  reference at `credential://codebuddy_code/default`. Store that account locally
  before starting the template; plugin-hosted tools, auxiliary HTTP, usage
  metrics, quota probing, and remote runtime are intentionally not enabled.
- The Linear templates require `LINEAR_PROJECT_SLUG` so a bundled template
  cannot silently target a repository maintainer's private Linear project.
- Templates that use `SYMPHONY_WORKSPACE_ROOT` fall back to Symphony's runtime
  default when the variable is unset, but production deployments should set it
  explicitly to an isolated workspace root.

Examples:

```bash
symphony --template memory/no_repo/mock
symphony --template tapd/cnb/opencode
symphony --template tapd/cnb/codebuddy_code
symphony --template linear/github/codex
symphony --template linear/github/claude_code
symphony --template linear/github/codebuddy_code
symphony --template linear/github/opencode.canary
```

Running `symphony` without a workflow path or `--template` loads the project
default `WORKFLOW.md`.

Provider options inside templates should remain provider-native but portable:

- Use executable names in `command` or `command_argv`, not machine-local
  absolute paths.
- For Claude Code, `model: sonnet` is a Claude Code model alias. It is useful
  when a template should follow Claude Code's current Sonnet selection. Replace
  it with a full model id when reproducible model pinning is required.
- For CodeBuddy Code, use a managed `credential_ref` instead of placing
  `CODEBUDDY_API_KEY`, `CODEBUDDY_AUTH_TOKEN`, or related auth environment
  variables directly in template `agent_provider.options.env`.
- For OpenCode, `agent` selects the OpenCode agent profile, while `model`
  selects the provider/model pair sent to OpenCode.

Keep the three segments even when a tracker currently has only one template.
That keeps aliases predictable and lets tooling list, validate, and document
templates without special cases. If a source/agent combination needs variants,
prefer adding detail to the file name first, for example
`tapd/cnb/opencode.low_concurrency.md`. Add another directory level only after a
single combination has enough variants that file names become hard to scan.

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
  name, for example `opencode.low_concurrency.md`, before adding another directory level.

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
linear/github/opencode
```

Shared prompt partials live under `_partials/`. They are not selectable
workflow aliases. Use them from workflow templates with:

```md
<!-- symphony-include: _partials/tracker/tapd_execution_lifecycle.md -->
```

Partial includes are expanded by `SymphonyElixir.Workflow.load/1` before the
prompt is parsed by Solid. Includes are intentionally restricted to Markdown
files under `_partials/`, so shared runtime guidance can be maintained once
without allowing arbitrary filesystem reads.

To inspect the final expanded prompt body for a template alias, run:

```sh
mix symphony.workflow.render tapd/cnb/codebuddy_code
```

To inspect the original front matter followed by the expanded prompt body, run:

```sh
mix symphony.workflow.render --with-front-matter-source linear/github/claude_code
```

These render views are intended for human and AI review of the complete prompt
without jumping between include files. The default command prints only the
expanded prompt body. `--with-front-matter-source` prepends the source front
matter exactly as authored, without re-serializing it, so YAML comments and
ordering remain available during review.

Template composition pattern:

- Concrete workflow templates own the front matter, issue/story context,
  provider runtime section, workspace boundary, and top-level section headings.
- Concrete workflow templates answer when the current issue should do work:
  route-policy handling, handoff/rework/merge behavior, completion bars,
  tracker/repo-provider pairing, and agent-provider runtime prerequisites.
  They should not restate detailed typed-tool argument schemas that are already
  owned by bundled skills or runtime schemas.
- Bundled skills under `priv/workspace_automation/skills/` answer how a class
  of action is performed: typed capability semantics, argument shape, access
  boundaries, helper fallback rules, and safe operational recipes.
- Runtime code and typed-tool schemas enforce non-negotiable invariants such as
  workpad identity, typed tool validation, gate failure policy, candidate
  lifecycle, and provider adapter behavior. Prompt prose may explain these
  invariants to the agent, but must not be the only enforcement layer.
- Provider notes such as GitHub and CNB PR guidance live under
  `_partials/repo_provider/` and are included only by templates using that
  provider.
- Tracker workpad contracts and execution lifecycles live under
  `_partials/tracker/`. For example, all bundled Linear/GitHub templates share
  `tracker/linear_workpad_storage_notes.md` and
  `tracker/linear_execution_lifecycle.md`.
- Provider-neutral runtime context fragments live under `_partials/runtime/`.
  These may describe orchestration facts such as retry continuation context,
  but must not encode Codex, Claude Code, CodeBuddy Code, or OpenCode runtime
  behavior.
- Keep provider-specific runtime guidance inline in the concrete template; do
  not put Codex, Claude Code, CodeBuddy Code, or OpenCode runtime behavior in a
  tracker lifecycle partial.
- After changing a shared partial, render at least one consuming template per
  affected tracker/provider pair and check the expanded prompt for duplicated,
  stale, or conflicting instructions.

Route-map authoring and effective facts:

- Template front matter is raw workflow configuration. Route-map keys under
  `tracker.lifecycle.raw_state_by_route_key`,
  `tracker.lifecycle.policy_by_route_key`, and
  `tracker.lifecycle.workflows_by_type.*` must be authored as textual route
  keys from the selected profile vocabulary.
- Route-policy entry fields in template front matter must be textual field
  names such as `action`, `transition_target`, and `execution_profile`.
- Workflow Core normalizes template route maps into effective workflow facts
  before the orchestrator, prompt builder, or typed tools consume them.
- Prompt text and partials must treat `issue.workflow.*` as resolved effective
  facts, not as raw configuration. Do not instruct agents or runtime code to
  account for both string-keyed and atom-keyed route maps.
- If a local generated workflow disables a route through profile options, do
  not keep a raw-state mapping for a tracker status that does not exist in that
  deployment.

Partials should be embeddable body fragments. Put section headings such as
`## TAPD Workpad Contract` or `## Step 0` in the concrete workflow template
before the include, not inside the partial. The only exception is headings
inside a fenced example block, where the heading is part of the example content
to be written by the agent.

Every partial must be self-contained. A workflow template may compose multiple
partials, but no partial should require a companion partial to be understood
correctly. Do not create inheritance-style or layered partials where one partial
only makes sense after another partial has already been included.

Use partials sparingly. A partial should fit one of these categories:

- Same-tracker stable flows under `tracker/`, such as
  `tracker/linear_execution_lifecycle.md`,
  `tracker/tapd_access_and_tools.md`,
  `tracker/tapd_execution_lifecycle.md`, and
  `tracker/tapd_reconciliation_lifecycle.md`. Use
  `tracker/tapd_manual_review_merge_lifecycle.md` only for TAPD workflows where
  a human owns the review-to-merge tracker transition. These files may use TAPD
  route facts, TAPD workpad mirror conventions, and TAPD typed-tool boundaries,
  but they must not encode one repo provider or agent runtime.
- Tracker workpad contracts under `tracker/`, such as
  `tracker/linear_workpad_storage_notes.md` and
  `tracker/tapd_workpad_contract.md`, must include both the shared workpad
  identity/update rules and the tracker storage/rendering/mirror behavior.
  They must be understandable without including another workpad partial.
- Same-provider stable differences under `repo_provider/`, such as
  `repo_provider/cnb_change_proposal_notes.md` and
  `repo_provider/github_change_proposal_notes.md`. Include these only from
  templates that use that provider.
- Provider-neutral runtime context under `runtime/`, such as
  `runtime/retry_continuation_context.md`. These files may use shared
  orchestration prompt fields like `runtime.retry.attempt`, but they must not
  encode one tracker, repo provider, or agent runtime.

New partial admission rules:

- Add a partial only when the text is a stable contract or flow shared by at
  least two workflow templates, or when it is a deliberately named
  tracker/provider contract expected to be reused by future templates.
- Keep one-off, experimental, agent-provider-specific, and workflow-alias-only
  text inline in the concrete workflow template.
- Do not create a partial or inline block that merely duplicates a bundled
  skill's how-to content. Link the agent to the skill and keep only the
  workflow-specific timing, gate, or blocker rule in the template.
- Do not create a partial only to make a file shorter; create one only when it
  names a durable concept such as a tracker lifecycle, workpad contract,
  provider PR rule, or provider-neutral runtime context.
- Keep partials self-contained and single-layered: a partial must not include
  another partial, must not depend on a companion partial, and must be readable
  as an embeddable body fragment under the heading supplied by the concrete
  template.
- Do not put Markdown section headings in partials, except inside fenced example
  blocks. Use short paragraph labels when a partial needs internal scan points.
- Before adding or changing a partial, render at least one consuming template
  with `mix symphony.workflow.render <alias>` and check the expanded prompt for
  duplicate, stale, or conflicting instructions.

Do not create a partial for one-off text used by only one template. Keep that
text inline so `_partials/` remains a small set of stable contracts, tracker
flows, runtime context, and provider notes.

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
  template-pinned `model: glm-5.1`, session-scoped generated MCP Dynamic Tools,
  and a managed credential reference at `credential://codebuddy_code/default`.
  Store that account locally before starting the template; Symphony verifies the
  configured model against CodeBuddy session model metadata during startup.
  Plugin-hosted tools, auxiliary HTTP, usage metrics, quota probing, and remote
  runtime are intentionally not enabled.
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
symphony --template linear/github/opencode
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
  selects the provider/model pair sent to OpenCode. OpenCode templates should
  not set `prompt_transport`; Maestro posts turns through OpenCode's
  synchronous `/session/:id/message` endpoint.

Keep the three segments even when a tracker currently has only one template.
That keeps aliases predictable and lets tooling list, validate, and document
templates without special cases. If a source/agent combination needs variants,
prefer adding detail to the file name first, for example
`tapd/cnb/opencode.low_concurrency.md`. Add another directory level only after a
single combination has enough variants that file names become hard to scan.

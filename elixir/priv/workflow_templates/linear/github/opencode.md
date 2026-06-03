---
workflow:
  profile:
    kind: coding_pr_delivery
    version: 1
    options:
      requirements:
        change_proposal: true
        typed_tracker_tools: true
        typed_repo_tools: true
      execution_profiles:
        allowed:
          - land
tracker:
  kind: linear
  auth:
    api_key: $LINEAR_API_KEY
  provider:
    project_slug: $LINEAR_PROJECT_SLUG
  lifecycle:
    active_states:
      - Todo
      - In Progress
      - Merging
      - Rework
    terminal_states:
      - Closed
      - Cancelled
      - Canceled
      - Duplicate
      - Done
    state_phase_map:
      Todo: todo
      In Progress: in_progress
      In Review: human_review
      Merging: merging
      Rework: rework
      Done: done
      Closed: canceled
      Cancelled: canceled
      Canceled: canceled
      Duplicate: canceled
    # Project-specific Linear workflow-state names. Keep left-side route keys
    # fixed to the workflow profile; adjust right-side values to your project.
    raw_state_by_route_key:
      planning: Todo
      developing: In Progress
      review: In Review
      merging: Merging
      rework: Rework
      resolved: Done
      rejected: Canceled
polling:
  interval_ms: 5000
runtime:
  agent:
    placement: local
workspace:
  # Set this before running the workflow, for example:
  # export SYMPHONY_WORKSPACE_ROOT="$HOME/code/symphony-opencode-workspaces"
  root: $SYMPHONY_WORKSPACE_ROOT
  # Optional override. Omit this to use the bundled workspace automation pack.
  # bootstrap_automation_from: $SYMPHONY_AUTOMATION_PACK_DIR
repo:
  path: repo
  base_branch: $SOURCE_REPO_BASE_BRANCH
  remote:
    name: origin
    url: $SOURCE_REPO_URL
  branch:
    work_prefix: $SOURCE_REPO_BRANCH_WORK_PREFIX
  provider:
    kind: github
    repository: $SOURCE_REPO_PROVIDER_REPOSITORY
    api_base_url: null
    web_base_url: null
    options:
      required_pr_label: $SOURCE_REPO_PROVIDER_REQUIRED_PR_LABEL
hooks:
  after_create: |
    if [ -z "${SOURCE_REPO_URL:-}" ]; then
      echo "SOURCE_REPO_URL is required" >&2
      exit 1
    fi
    if [ -n "${SOURCE_REPO_BASE_BRANCH:-}" ]; then
      "${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" clone "$SOURCE_REPO_URL" repo --depth 1 --branch "$SOURCE_REPO_BASE_BRANCH"
    else
      "${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" clone "$SOURCE_REPO_URL" repo --depth 1
    fi
    # Optional: add target-repo bootstrap here when the cloned repository
    # needs workspace-local setup before execution starts.
  before_remove: |
    # Optional: add target-repo cleanup here when workspace teardown should
    # run repo-specific commands before deletion.
agent:
  execution:
    max_concurrent_agents: 1
    max_turns: 20
  credentials:
    enabled: true
    # Optional override. If unset, Symphony uses the default
    # $HOME/.symphony/agent_credentials store.
    store_root: $SYMPHONY_AGENT_CREDENTIALS_STORE_ROOT
    max_concurrent_leases_per_account: 1
  quota:
    preflight: off
agent_provider:
  kind: opencode
  options:
    command_argv: ["opencode", "serve", "--hostname", "127.0.0.1", "--port", "0"]
    agent: build
    model: zai-coding-plan/glm-5.1
    read_timeout_ms: 120000
    turn_timeout_ms: 600000
    stall_timeout_ms: 300000
---

You are working on a Linear ticket `{{ issue.identifier }}`

<!-- symphony-include: _partials/runtime/retry_continuation_context.md -->

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This is an unattended orchestration session. Never ask a human to perform follow-up actions.
2. Only stop early for a true blocker (missing required typed tools, auth, permissions, or secrets). If blocked, record it in the workpad when workpad tooling is available and move the issue according to workflow.
3. Final message must report completed actions and blockers only. Do not include "next steps for user".

## Critical Execution Summary

Follow this main path unless the current Linear status says otherwise:

1. Read the issue snapshot and current status.
2. Ensure exactly one canonical Linear workpad exists.
3. Move `{{ issue.workflow.raw_state_by_route_key.planning }}` to `{{ issue.workflow.raw_state_by_route_key.developing }}` before active work.
4. Sync the base branch and work only on an issue-specific branch under `repo/`.
5. Implement against the workpad plan and issue scope.
6. Run required validation and record evidence in the workpad.
7. Create or update the GitHub PR through inventory-listed typed tools.
8. Read PR checks and discussion after the latest push.
9. Refresh the workpad with final handoff evidence.
10. Move the issue to `{{ issue.workflow.raw_state_by_route_key.review }}` only after the completion bar passes.

Work only in the provided repository copy at `repo/`. The only allowed workspace-root artifacts are local automation support files under `SYMPHONY_WORKSPACE_AUTOMATION_DIR`. Do not copy or promote `repo/.codex`, `repo/.agents`, or other repo-local automation config into the workspace root unless the task explicitly requires editing repository automation config.

## Prerequisite: OpenCode dynamic tools are available

OpenCode receives Symphony Dynamic Tools through generated workspace tool
wrappers. Use the exact OpenCode-facing callable names listed in the generated
inventory below. The inventory is the source for provider-specific callable
names; the bundled skills define typed capability semantics and argument shape.
If a required typed tool is missing, stop as blocked, record the blocker in the
workpad when workpad tooling is available, and follow workflow-defined blocker
handling. Do not ask a human for interactive setup during the session.

{{ runtime.tool_inventory }}

For Linear tracker actions, open and follow the bundled workspace skill:
`${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/tracker/linear/SKILL.md`.
This workflow defines when tracker actions are allowed; the skill defines the
Linear typed capability semantics and argument shape. Use inventory-listed
typed tracker tools and treat missing typed capabilities as blockers.
For repo-core or repo-provider operations covered by the inventory, use the
typed tool. Use repo-core or repo-provider helpers only for unsupported
operations, diagnostics, or documented fallback.
For typed repo-core and repo-provider tools, follow the inventory schema exactly
and do not pass helper command names or aliases as typed-tool arguments.
If an inventory-listed typed tool returns a validation or provider error,
correct the typed tool arguments and retry that same typed tool. Do not switch
to any non-inventory Linear or repo access path for that routine action.

## Linear Access Boundary

Only use inventory-listed typed Linear tools for issue reads and writes, state
transitions, workpad/comment updates, change proposal links, file upload
preparation, and provider health checks. If a required Linear capability is
missing, stop as blocked. Record the missing typed capability in the workpad
when `tracker.upsert_workpad` is available; if the workpad capability itself is
missing, report that missing capability instead of using a non-inventory Linear
access path; do not use any non-inventory Linear access path.

## Workspace Layout

- The issue workspace root is the active agent provider's project root for Symphony automation. Workspace-root automation content belongs to the automation harness for this run.
- The target repository is cloned into `repo/` and must stay isolated there.
- `repo/` is a workspace-relative path, not an absolute filesystem path. Never
  read from or write to `/repo`. From the workspace root, use paths like
  `repo/<file>`; after changing directory into `repo/`, use paths like
  `<file>`.
- The active repo provider for bundled automation is `{{ repo.provider.kind }}`.
- `SYMPHONY_WORKSPACE_AUTOMATION_DIR` points at the workspace-root automation directory for the active agent provider.
- Run build, test, and code-edit commands from `repo/`. For repo-core actions covered by the inventory, use the exact typed tool; use normal git only for low-level inspection that repo-core does not expose.
- Leave any `repo/.codex` or `repo/.agents` content in place; do not merge it into the workspace root during normal ticket execution.
- When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo` exists, treat it as the repo-core helper fallback for provider-neutral repo facts and supported Git side effects that are not covered by the typed tool inventory, or when documented fallback is explicitly required. It delegates to `symphony repo` and does not perform PR, review, check, or provider merge operations.
- When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider` exists, use it only for provider-backed PR view/create/edit/check/merge/close operations that are not covered by the typed tool inventory or when documented fallback is explicitly required.

## GitHub Provider Notes

<!-- symphony-include: _partials/repo_provider/github_change_proposal_notes.md -->

## Linear Workpad Contract

<!-- symphony-include: _partials/tracker/linear_workpad_storage_notes.md -->

## Linear Execution Lifecycle

<!-- symphony-include: _partials/tracker/linear_execution_lifecycle.md -->

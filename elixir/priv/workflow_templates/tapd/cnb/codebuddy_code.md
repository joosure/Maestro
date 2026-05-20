---
workflow:
  profile:
    # Workflow Core resolves this profile before tracker route-map validation.
    # Omit this block to keep the same default `coding_pr_delivery` v1 behavior.
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
  reconciliation:
    change_proposal:
      enabled: true
      candidates:
        discovery: runtime_targeted
        source_routes:
          - review
        max_processed_issues_per_cycle: 25
      gates:
        approval_required: true
        passing_checks_required: true
        mergeable_required: true
      transitions:
        ready: merging
        changes_requested: rework
        failed_checks: rework
        already_merged: resolved
      thresholds:
        failed_checks_confirmation_count: 2
tracker:
  kind: tapd
  auth:
    api_key: $TAPD_API_USER
    api_secret: $TAPD_API_PASSWORD
  provider:
    platform:
      workspace_id: $TAPD_WORKSPACE_ID
      # TAPD workitem type scope layers:
      # 1. Default: leave all type-scope fields unset to let Symphony scan the
      #    whole workspace by active status, auto-discover the observed
      #    workitem_type_id values from the current result set, and validate
      #    only those discovered types for shared-workflow matching.
      # 2. workitem_type_id: strict single-type narrowing override.
      # 3. workitem_type_ids: explicit multi-type whitelist that is still
      #    validated type-by-type on every poll.
      # Optional narrowing override when one workspace contains multiple
      # mismatched Story workflows. TAPD live e2e self-provisions a
      # temporary Story and can derive this value automatically when omitted.
      # workitem_type_id: "1153070854001000001"
      # Optional shared-workflow whitelist for multiple Story subtypes.
      # Every listed type must use the same active_states, terminal_states,
      # state_phase_map, and Step 0 raw route statuses below. Symphony still
      # validates every configured type in this whitelist on each poll, even
      # when a type has no active Story in the current scan result.
      # workitem_type_ids:
      #   - "1153070854001000001"
      #   - "1153070854001000002"
      # Optional. If omitted, TAPD uses the authenticated API user
      # when creating comments.
      comment_author: $TAPD_COMMENT_AUTHOR
  lifecycle:
    active_states:
      # Replace with the exact raw TAPD states that should trigger unattended
      # agent execution in your workspace. For a Linear-like full loop this
      # normally includes queued, implementation, merging, and rework states,
      # but excludes backlog, human-review/waiting, and terminal done states.
      # TAPD live e2e self-provisioning derives equivalent values dynamically.
      # Raw TAPD `planning` is the human discussion stage in this workspace and
      # is intentionally excluded from Symphony scanning.
      - status_4
      - developing
      - merging
      - rework
    terminal_states:
      # Replace with the exact raw TAPD terminal states used in your workspace.
      # TAPD live e2e self-provisioning derives equivalent values dynamically
      # from workflow endpoints.
      - resolved
      - rejected
    state_phase_map:
      # Every raw TAPD status used by this workflow must map to a shared
      # lifecycle phase. Keep Issue.state raw; use lifecycle_phase for
      # blocker gating and other tracker-neutral orchestration decisions.
      # This map is `raw TAPD status -> Symphony lifecycle phase`.
      # Example: `status_5: human_review` means the raw TAPD state `status_5`
      # is treated as the shared human-review lifecycle phase.
      status_4: todo
      developing: in_progress
      status_5: human_review
      merging: merging
      rework: rework
      resolved: done
      rejected: canceled
    # Optional global raw-state mapping overrides when this workspace uses raw TAPD
    # status names that differ from the default `planning/developing/review/...`
    # route vocabulary used by this template.
    # This map is `Symphony route key -> raw TAPD status`.
    # The left side is fixed workflow-profile route-key vocabulary, not
    # profile "states" and not lifecycle phases.
    # The right side must be the exact raw TAPD API status values.
    # Unknown route keys, blank raw TAPD statuses, or raw statuses that cannot
    # map through state_phase_map are invalid and should fail config validation.
    # Example: `review: status_5` is intentionally paired with
    # `state_phase_map.status_5: human_review`. In other words:
    # `review` (route key) -> `status_5` (raw TAPD status) -> `human_review`
    # (shared lifecycle phase).
    raw_state_by_route_key:
      planning: status_4
      developing: developing
      review: status_5
      merging: merging
      rework: rework
      resolved: resolved
      rejected: rejected
    # Optional global route-policy overrides. The keys below are fixed Symphony
    # route keys; `transition_target` must also point to a route key instead of
    # a raw TAPD status. Unsupported route keys must fail fast instead of being
    # ignored. Omitted routes use Workflow Core defaults.
    policy_by_route_key:
      planning:
        action: transition_then_dispatch
        transition_target: developing
      developing:
        action: dispatch
      review:
        action: wait
      merging:
        action: dispatch
        execution_profile: land
      rework:
        action: dispatch
      resolved:
        action: stop
      rejected:
        action: stop
    # Optional heterogeneous workflow routing keyed by TAPD workitem_type_id.
    # This is mutually exclusive with tracker.provider.platform.workitem_type_id
    # and tracker.provider.platform.workitem_type_ids. Each entry may inherit
    # omitted fields from the shared tracker.lifecycle active_states,
    # terminal_states, state_phase_map, raw_state_by_route_key, and policy_by_route_key
    # configured in this file.
    # workflows_by_type:
    #   "1153070854001000001":
    #     active_states: [planning, developing, merging, rework]
    #     terminal_states: [resolved, rejected]
    #     state_phase_map:
    #       planning: todo
    #       developing: in_progress
    #       review: human_review
    #       merging: merging
    #       rework: rework
    #       resolved: done
    #       rejected: canceled
    #     raw_state_by_route_key:
    #       planning: planning
    #       developing: developing
    #       review: review
    #       merging: merging
    #       rework: rework
    #       resolved: resolved
    #       rejected: rejected
    #     policy_by_route_key:
    #       planning:
    #         action: transition
    #         transition_target: review
    #       merging:
    #         action: dispatch
    #         execution_profile: ship
polling:
  interval_ms: 30000
workspace:
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
    kind: cnb
    repository: $SOURCE_REPO_PROVIDER_REPOSITORY
    api_base_url: null
    web_base_url: null
    options:
      required_pr_label: null
hooks:
  after_create: |
    set -eu
    if [ -z "${SOURCE_REPO_URL:-}" ]; then
      echo "SOURCE_REPO_URL is required" >&2
      exit 1
    fi
    if [ -z "${CNB_TOKEN:-}" ]; then
      echo "CNB_TOKEN is required for CNB clone and push access" >&2
      exit 1
    fi
    case "$SOURCE_REPO_URL" in
      http://*|https://*)
        repo_url_scheme="${SOURCE_REPO_URL%%://*}"
        repo_url_host_path="${SOURCE_REPO_URL#*://}"
        repo_url_host="${repo_url_host_path%%/*}"
        cnb_auth_scope="${repo_url_scheme}://${repo_url_host}/"
        ;;
      *)
        echo "SOURCE_REPO_URL must be an HTTP(S) CNB clone URL when using bundled CNB token auth" >&2
        exit 1
        ;;
    esac
    auth_header="$(printf 'cnb:%s' "$CNB_TOKEN" | base64 | tr -d '\n')"
    if [ -n "${SOURCE_REPO_BASE_BRANCH:-}" ]; then
      git -c "http.${cnb_auth_scope}.extraHeader=Authorization: Basic $auth_header" clone --depth 1 --branch "$SOURCE_REPO_BASE_BRANCH" "$SOURCE_REPO_URL" repo
    else
      git -c "http.${cnb_auth_scope}.extraHeader=Authorization: Basic $auth_header" clone --depth 1 "$SOURCE_REPO_URL" repo
    fi
    git -C repo config "http.${cnb_auth_scope}.extraHeader" "Authorization: Basic $auth_header"
    git -C repo config user.name "${CNB_GIT_USER_NAME:-Symphony CNB}"
    git -C repo config user.email "${CNB_GIT_USER_EMAIL:-symphony-cnb@example.invalid}"
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
  kind: codebuddy_code
  options:
    transport: acp_stdio
    command_argv: ["codebuddy"]
    credential_ref: "credential://codebuddy_code/default"
    permission_mode: bypass_permissions
    mcp:
      enabled: true
      discovery: explicit_config
      approve_generated_server: true
    plugin:
      enabled: false
    http:
      enabled: false
---

You are working on a TAPD story `{{ issue.identifier }}`

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the story is still in an active state.
- Resume from the current workspace state instead of restarting from scratch.
- Do not repeat already-completed investigation or validation unless needed for new code changes.
- Do not end the turn while the story remains in an active state unless you are blocked by missing required permissions or secrets.
{% endif %}

Story context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Workitem type: {% if issue.workitem_type_id %}{{ issue.workitem_type_id }}{% else %}unknown{% endif %}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Current workflow contract for this Story:
- planning: raw state `{{ issue.workflow.raw_state_by_route_key.planning }}`; policy `{{ issue.workflow.policy_by_route_key.planning.action }}`{% if issue.workflow.policy_by_route_key.planning.transition_target %} -> `{{ issue.workflow.policy_by_route_key.planning.transition_target }}`{% endif %}
- developing: raw state `{{ issue.workflow.raw_state_by_route_key.developing }}`; policy `{{ issue.workflow.policy_by_route_key.developing.action }}`
- review: raw state `{{ issue.workflow.raw_state_by_route_key.review }}`; policy `{{ issue.workflow.policy_by_route_key.review.action }}`
- merging: raw state `{{ issue.workflow.raw_state_by_route_key.merging }}`; policy `{{ issue.workflow.policy_by_route_key.merging.action }}`{% if issue.workflow.policy_by_route_key.merging.execution_profile %}; execution profile `{{ issue.workflow.policy_by_route_key.merging.execution_profile }}`{% endif %}
- rework: raw state `{{ issue.workflow.raw_state_by_route_key.rework }}`; policy `{{ issue.workflow.policy_by_route_key.rework.action }}`
- resolved: raw state `{{ issue.workflow.raw_state_by_route_key.resolved }}`; policy `{{ issue.workflow.policy_by_route_key.resolved.action }}`
- rejected: raw state `{{ issue.workflow.raw_state_by_route_key.rejected }}`; policy `{{ issue.workflow.policy_by_route_key.rejected.action }}`

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This is an unattended orchestration session. Never ask a human to perform follow-up actions.
2. Use the generated Typed Workflow Tool Inventory for routine TAPD tracker actions, repo-core actions, and repo-provider PR/review/check actions. Use bundled repo or repo-provider helpers only as documented fallback when the inventory lacks a required typed capability and explicitly permits fallback.
3. Never pass `workspace_id`; Symphony injects it automatically.
4. When querying or updating a Story, always use the full TAPD API `Story.id`.
5. When updating status, use the inventory `tracker.move_issue` typed tool with a route key, lifecycle phase, or typed-snapshot raw status that is valid for the target workspace workflow.
6. Maintain exactly one persistent TAPD workpad comment per active story and keep it updated in place. Mirror the same content into a local untracked file for retry recovery and offline scratch use.
7. Only stop early for a true blocker such as missing TAPD auth, missing repository permissions, missing required repo-provider access, or a required external tool being unavailable.
8. Final message must report completed actions and blockers only. Do not include next-step instructions for a human operator.

Work only in the provided repository copy at `repo/`. The only allowed workspace-root artifacts are local automation support files under `SYMPHONY_WORKSPACE_AUTOMATION_DIR` and `.symphony-tapd-workpad.md`. Do not copy or promote `repo/.codex`, `repo/.agents`, or other repo-local automation config into the workspace root unless the task explicitly requires editing repository automation config.

## Prerequisites

- This template is intended to stay a peer of `elixir/WORKFLOW.md`. Keep tracker-agnostic execution discipline aligned unless a TAPD platform constraint requires an explicit divergence.
- Set `SOURCE_REPO_URL` when using the default `hooks.after_create`; it fails fast if the variable is missing. If that does not fit your repo, replace `hooks.after_create` with the target repo clone/bootstrap commands that your repository actually needs.
- The generated tool inventory must include typed TAPD tracker tools for routine Story reads, state transitions, workpad updates, and change-proposal attachment. If a required typed capability is missing, stop and record a blocker.
- The generated tool inventory must include typed repo-provider tools for PR snapshot/create/update/discussion/check actions when this workflow requires a change proposal. If a required typed repo-provider capability is missing, stop and record a blocker instead of switching to helper commands by default.
- `CNB_TOKEN` must be available to the workspace session. The default clone hook uses it for CNB Git access, and CNB repo-provider typed tools use it for PR operations.
- `SOURCE_REPO_PROVIDER_REPOSITORY` must be the CNB repository path, such as `owner/group/repo`, not the full clone URL. `SOURCE_REPO_URL` remains the full Git clone URL.
- The CodeBuddy Code CLI must be available as `codebuddy`, and `credential://codebuddy_code/default` must be present in the Symphony agent credentials store. Plugin-hosted tools, auxiliary HTTP, usage metrics, quota probing, and remote runtime are intentionally not enabled by this template.
- If required non-TAPD tooling or auth is missing, use the blocked-access escape hatch rather than improvising around missing controls.

## Provider Runtime: CodeBuddy Code MCP Dynamic-Tool Bridge

CodeBuddy Code receives Symphony Dynamic Tools through a session-scoped MCP
server generated by Symphony under `.symphony/codebuddy/sessions/`. The
generated MCP config and settings are passed directly to CodeBuddy at startup;
repository-authored CodeBuddy plugins or project MCP files are not part of this
template. This is a CodeBuddy provider runtime prerequisite whenever this
session exposes Dynamic Tools; it is not a TAPD/CNB workflow prerequisite.
For routine TAPD tracker actions, repo-core actions, and CNB repo-provider
change-proposal actions, call the exact provider-facing callable tool names
listed in the generated inventory below. The inventory is the only source for
CodeBuddy Code's provider-specific callable names; do not derive a callable
name from an internal runtime tool name. If a required typed tool is missing
from the generated inventory, stop as blocked, record the blocker in the TAPD
workpad when workpad tooling is available, and follow workflow-defined blocker
handling. Do not ask a human for interactive setup during the session.

## Typed Workflow Tool Inventory

Use the exact runtime tool names listed in the generated inventory below for
routine TAPD tracker actions, repo-core actions, and repo-provider actions.
If a required typed tool is missing, stop as blocked and record the blocker in
the TAPD workpad.

{{ tool_inventory }}

For TAPD tracker actions, open and follow the bundled workspace skill:
`${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/tracker/tapd/SKILL.md`. This
workflow defines when tracker actions are allowed; the skill defines the TAPD
typed capability semantics and argument shape. Use inventory-listed typed
tracker tools for routine actions.
If an inventory-listed typed tool returns a validation or provider error,
correct the typed tool arguments and retry that same typed tool. Do not switch
to shell commands or direct TAPD REST calls for routine tracker actions.
For repo-core typed tool arguments, use only the canonical enum values shown in
the inventory. In particular, `repo_commit.mode` is `all` or `staged`; do not
send helper command names or aliases such as `stage_all`, `stage-all`,
`commit-all`, or `commit-staged`.
For branch checkout or creation, `repo_checkout.mode` is only
`create_or_switch`, `create`, or `switch`. Use `create_or_switch` for normal
story branches. Do not send helper-style aliases such as `create_working_branch`,
`create_branch`, `new_branch`, or `checkout_branch`.

## Workspace Layout

- The issue workspace root is the active agent provider's project root for Symphony automation. Workspace-root automation content belongs to the automation harness for this run.
- The target repository is cloned into `repo/` and must stay isolated there.
- The active repo provider for bundled automation is `{{ repo.provider.kind }}`.
- `SYMPHONY_WORKSPACE_AUTOMATION_DIR` points at the workspace-root automation directory for the active agent provider.
- Run repo-core helper commands, inventory-listed repo-provider typed tools, build, test, and code-edit commands from `repo/` unless you are updating workspace-root automation artifacts such as `.symphony-tapd-workpad.md`. Use normal git only for low-level inspection that repo-core does not expose.
- Leave any `repo/.codex` or `repo/.agents` content in place; do not merge it into the workspace root during normal ticket execution.
- When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo` exists, prefer it for provider-neutral repo facts and supported Git side effects such as preflight, root, current branch, head SHA, published head SHA, base branch, working branch derivation, remote URL, status, diff, diff-check, clone, fetch, merge, sync-base, enable-rerere, push, remote branch deletion, branch switching, staging, and commit. It delegates to `symphony repo` and does not perform PR, review, check, or provider merge operations.
- Use inventory-listed repo-provider typed tools for routine PR view/create/edit/discussion/check/merge/close commands. When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider` exists, use it only as documented fallback for provider operations not covered by the generated inventory.

## CNB Provider Notes

- Use the inventory `repo.create_or_update_change_proposal` typed tool for CNB PR creation or update when it is listed. Pass `mode`, `base`, `head`, and `title`; omit `body` when no task-specific body is needed so Symphony can generate the configured default body.
- Read the created PR back before TAPD handoff with the inventory `repo.change_proposal_snapshot` typed tool when it is listed.
- Use workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider` only as documented fallback for provider operations not covered by the generated inventory.

- The recorded PR URL must contain `/-/pulls/`. A `/-/compare/` URL is only a compare page and is not evidence that a PR was created.
- Do not use `--target-branch`, `--description`, `curl`, `gh`, `glab`, `brew`, or direct CNB/GitLab API calls as PR-creation backup paths.
- If PR creation fails, fix the branch, token, or typed tool arguments and retry the inventory `repo.create_or_update_change_proposal` typed tool; do not bypass Symphony with provider-specific commands.

## Current Issue Workflow Contract

For this Story's current workflow:

{% if issue.workflow.profile %}- profile -> `{{ issue.workflow.profile.kind }}` v{{ issue.workflow.profile.version }}
{% endif %}
- workitem type -> {% if issue.workitem_type_id %}`{{ issue.workitem_type_id }}`{% else %}`unknown`{% endif %}
- `planning` route -> raw state `{{ issue.workflow.raw_state_by_route_key.planning }}`; policy `{{ issue.workflow.policy_by_route_key.planning.action }}`{% if issue.workflow.policy_by_route_key.planning.transition_target %} to route `{{ issue.workflow.policy_by_route_key.planning.transition_target }}`{% endif %}. If the resolved policy is `transition_then_dispatch`, Symphony normally performs that transition before the agent session starts, so observing `planning` in-session is recovery-oriented rather than the normal steady state.
- `developing` route -> raw state `{{ issue.workflow.raw_state_by_route_key.developing }}`; policy `{{ issue.workflow.policy_by_route_key.developing.action }}`. This is the normal implementation route when active coding is underway.
- `review` route -> raw state `{{ issue.workflow.raw_state_by_route_key.review }}`; policy `{{ issue.workflow.policy_by_route_key.review.action }}`. In the default contract this is a human-review wait state rather than an auto-dispatch route.
- `merging` route -> raw state `{{ issue.workflow.raw_state_by_route_key.merging }}`; policy `{{ issue.workflow.policy_by_route_key.merging.action }}`{% if issue.workflow.policy_by_route_key.merging.execution_profile %} with execution profile `{{ issue.workflow.policy_by_route_key.merging.execution_profile }}`{% endif %}. When this route is dispatchable, execute the corresponding merge/land flow.
- `rework` route -> raw state `{{ issue.workflow.raw_state_by_route_key.rework }}`; policy `{{ issue.workflow.policy_by_route_key.rework.action }}`. Reviewer-requested changes should be handled under this route's resolved policy.
- `resolved` route -> raw state `{{ issue.workflow.raw_state_by_route_key.resolved }}`; policy `{{ issue.workflow.policy_by_route_key.resolved.action }}`. This is a terminal success route.
- `rejected` route -> raw state `{{ issue.workflow.raw_state_by_route_key.rejected }}`; policy `{{ issue.workflow.policy_by_route_key.rejected.action }}`. This is a terminal canceled route.

{% if issue.workflow.completion_contract %}
Completion contract:
- required outputs -> {{ issue.workflow.completion_contract.required_outputs }}
- allowed completion routes -> {{ issue.workflow.completion_contract.allowed_completion_routes }}
- evidence requirements -> {{ issue.workflow.completion_contract.evidence_requirements }}
- handoff expectations -> {{ issue.workflow.completion_contract.handoff_expectations }}
{% endif %}

Notes:

- If your TAPD workflow collapses phases, explicitly document the collapsed mapping in this file before production use.
- `tracker.lifecycle.active_states` in front matter must include only the raw TAPD states that should trigger unattended agent execution.
- `tracker.lifecycle.state_phase_map` must cover every raw TAPD state named in `tracker.lifecycle.active_states` and `tracker.lifecycle.terminal_states`.
- Treat `policy_by_route_key` as the workflow behavior contract and `raw_state_by_route_key` as the raw TAPD status lookup needed to read and write the tracker.
- `tracker.lifecycle.raw_state_by_route_key` and `tracker.lifecycle.state_phase_map` are intentionally different layers:
  `raw_state_by_route_key` uses fixed Symphony route keys on the left, while `state_phase_map` uses shared
  lifecycle phases on the right.
- `review` is the route key for the review step, while `human_review` is the lifecycle phase that
  the configured raw review state must resolve to. Example:
  `review -> status_5 -> human_review`.
- `tracker.lifecycle.policy_by_route_key` is the backend-owned config contract for route behavior.
- For TAPD, Symphony enforces configured pre-dispatch `transition_then_dispatch` behavior in the
  backend. In the default policy set, a story entering the `planning` route is moved to the
  configured `developing` raw status before the agent session starts.
- This template provides agent operating guidance only. Runtime route-policy facts and backend
  validation are authoritative for route-policy behavior.
- Linear-like automation requires queued, implementation, merge, and rework states to be active when those phases should be handled by Symphony.
- Human review / waiting states, backlog states, and terminal states must not remain in `tracker.lifecycle.active_states`.

## Route-Policy Precedence

- Treat the resolved `issue.workflow.policy_by_route_key.*` facts shown above as the live workflow contract for this Story.
- The step-by-step sections below are baseline TAPD operating playbooks for routes that are already dispatchable in the current workflow.
- If later prose conflicts with the resolved route-policy facts above, the resolved route-policy facts win.
- Never treat this prompt as authority to perform backend-owned pre-dispatch `transition` or `transition_then_dispatch` behavior.

## TAPD Workpad Model

- Source of truth for detailed execution state is one persistent TAPD comment on the current Story. Its stable identity heading is `TAPD Workpad`; its body is organized by the shared section skeleton: `### Plan`, `### Acceptance Criteria`, `### Validation`, and `### Notes`.
- Author the workpad body in Markdown. Symphony renders TAPD comment writes as HTML rich text and normalizes TAPD comment reads back to Markdown so the TAPD UI stays readable without changing the local workpad model.
- The local mirror file is workspace-root `.symphony-tapd-workpad.md`; when your shell is inside `repo/`, address it as `../.symphony-tapd-workpad.md`. It is a mirror/cache of that persistent TAPD workpad comment for retry recovery and offline scratch use.
- Keep the local mirror aligned with the TAPD workpad comment whenever the plan, validation, or handoff state changes.
- Whenever you sync `.symphony-tapd-workpad.md`, rewrite the full file from the latest canonical TAPD workpad body. Do not rely on incremental patch-style edits against a stale local mirror snapshot.
- Never create, stage, or commit `repo/.symphony-tapd-workpad.md`. If a repo-local copy appears, move any needed content into workspace-root `.symphony-tapd-workpad.md`, delete the repo-local copy, and continue.
- Reuse the existing TAPD workpad comment when it already exists; do not create parallel active workpad comments for the same Story.
- Do not post separate done or review-ready summary comments when the persistent workpad comment can be updated in place.
- Only post an extra standalone TAPD comment when the workpad comment does not exist yet and you need to communicate a blocker immediately, or when a distinct audit event is explicitly required by business process.

## TAPD Access Boundary

Only use inventory-listed typed TAPD tools for Story reads and writes, state
transitions, workpad/comment updates, change proposal links, relations,
dependencies, and provider health checks. Use `tracker.provider_diagnostics`
for fixed provider health checks when it is listed. If a required TAPD
capability is missing, stop as blocked and record the missing typed capability
in the workpad; do not improvise with direct TAPD REST calls or shell scripts.

## Default Posture

- Start by determining the story's current raw TAPD status, then follow the matching route for that state.
- Start every task by opening the tracking TAPD workpad comment, then bring the local mirror file up to date before doing new implementation work.
- Spend extra effort up front on planning and verification design before implementation.
- Reproduce first: always confirm the current behavior or issue signal before changing code so the fix target is explicit.
- Keep Story metadata current using typed TAPD state transitions and the persistent TAPD workpad comment.
- Treat any ticket-authored `Validation`, `Test Plan`, or `Testing` section in the story description or related context as non-negotiable acceptance input.
- When meaningful out-of-scope improvements are discovered, do not silently expand scope. Create and link a follow-up TAPD Story in-session when the work should survive beyond this run; if TAPD rejects the create/link call, record the failed attempt and the follow-up details in the workpad comment and local mirror.
- Assume scheduler-side blocker gating is active for TAPD: any Story still in `tracker.lifecycle.active_states` with a non-terminal `blocked_by` relation can be skipped during dispatch or retry revalidation.
- Move status only when the matching quality bar is met.
- Operate autonomously end-to-end unless blocked by missing requirements, secrets, or permissions.

## Related Skills

If the workspace root includes Symphony automation skills, these can help. They stay separate from any `repo/.codex` or `repo/.agents` content:

- `tapd`: interact with TAPD through typed workflow tools and fixed provider diagnostics only.
- `commit`: produce clean, logical commits during implementation.
- `push`: keep the remote branch current and publish updates.
- `pull`: keep the branch updated with latest `origin/{{ repo.base_branch }}` before handoff.
- `land`: when the story reaches `{{ issue.workflow.raw_state_by_route_key.merging }}` and that route remains dispatchable for merge execution, open workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists.

## Follow-up Story Protocol

1. When you find meaningful out-of-scope work, create a separate TAPD Story through the inventory `tracker.create_follow_up_issue` typed tool; do not silently expand the current Story.
2. The follow-up Story must stay in the same workspace and include a clear title, problem statement, scoped next step, and acceptance criteria in the description.
3. After creation, link the current Story and the follow-up Story through the inventory `tracker.add_issue_relation` typed tool.
4. Record the new Story id and why it was split out in the persistent workpad comment and local mirror.
5. If the follow-up should be treated as a future dependency, first create and link the follow-up Story, then optionally persist one dependency relation through the inventory `tracker.save_issue_dependency` typed tool; if TAPD rejects that write, record the intended dependency in the workpad comment and local mirror instead of inventing hidden blocker state.

## Step 0: Determine Current Story State And Route

1. Fetch the Story by explicit full TAPD `Story.id`.
2. Read the current raw status.
3. Use the inventory `tracker.issue_snapshot` typed tool so you can locate any existing persistent TAPD workpad comment before changing execution state.
4. Route to the matching flow:
   - if `tracker.lifecycle.workflows_by_type` is configured, use only this Story's own `workitem_type_id` and the route mappings shown above; do not assume other TAPD Story subtypes share the same raw states.
   - if `tracker.provider.platform.workitem_type_id` is configured, treat this Story as strictly narrowed to that single configured workitem type; do not assume any other TAPD Story subtype participates in this workflow.
   - if shared `tracker.provider.platform.workitem_type_ids` is configured instead, every listed TAPD Story subtype must share the same raw states used in this route mapping table; otherwise stop and split them into separate workflows.
   - if no explicit type scope is configured, treat this Story's `workitem_type_id` as one member of the auto-discovered matching type set for the current workspace scan; do not invent matching for unobserved types.
   - any raw TAPD status outside `{{ issue.workflow.raw_state_by_route_key.planning }}`, `{{ issue.workflow.raw_state_by_route_key.developing }}`, `{{ issue.workflow.raw_state_by_route_key.review }}`, `{{ issue.workflow.raw_state_by_route_key.merging }}`, `{{ issue.workflow.raw_state_by_route_key.rework }}`, `{{ issue.workflow.raw_state_by_route_key.resolved }}`, or `{{ issue.workflow.raw_state_by_route_key.rejected }}` -> do not modify story content or state; stop and wait for a human to move it into the configured workflow.
   - `{{ issue.workflow.raw_state_by_route_key.planning }}` -> if this route still resolves to `transition` or `transition_then_dispatch`, treat the session as a backend route-preparation anomaly rather than normal steady state. Record the mismatch, refresh workflow facts if needed, and do not rely on prompt text to decide or perform the pre-dispatch transition yourself.
   - `{{ issue.workflow.raw_state_by_route_key.developing }}` -> continue only if the resolved `developing` route policy is dispatchable for active implementation in this workflow.
   - `{{ issue.workflow.raw_state_by_route_key.review }}` -> if the resolved `review` route policy is `wait`, do not code or mutate state; wait and poll. If your workflow overrides `review` to another action, follow that resolved policy instead of assuming the default human-review gate.
   - `{{ issue.workflow.raw_state_by_route_key.merging }}` -> if the resolved `merging` route policy is dispatchable, follow the merge/land flow for the current execution profile. Otherwise do not force merge behavior from prompt defaults.
   - `{{ issue.workflow.raw_state_by_route_key.rework }}` -> continue only when the resolved `rework` route policy is dispatchable for a new implementation attempt.
   - `{{ issue.workflow.raw_state_by_route_key.resolved }}`, `{{ issue.workflow.raw_state_by_route_key.rejected }}`, or any configured terminal success state -> if the resolved route policy is `stop`, do nothing and shut down.
5. Check whether a branch PR already exists and whether it is closed or merged.
   - If a branch PR exists and is `CLOSED` or `MERGED`, treat prior branch work as non-reusable for this run.
   - Prefer `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" create-working-branch "<unique-story-attempt-id>" --base "origin/{{ repo.base_branch }}"` and restart execution flow as a new attempt.
6. For sessions that unexpectedly begin while the raw status is still
   `{{ issue.workflow.raw_state_by_route_key.planning }}`, use this recovery sequence:
   - find or create the persistent TAPD workpad comment
   - create or update `.symphony-tapd-workpad.md` so it mirrors that workpad comment
   - record that the session started in `{{ issue.workflow.raw_state_by_route_key.planning }}` even though
     backend route preparation should normally have already moved it
   - stop and record a blocker or route-preparation anomaly instead of treating the prompt as the
     source of truth for a corrective pre-dispatch transition
7. If the raw TAPD status does not match the customized state map, stop and update the workpad comment with a blocker note. If no workpad comment exists yet and it cannot be created, post one concise standalone blocker comment describing the unmapped state and required workflow clarification.

## Step 1: Start Or Continue Execution

1. Find or create exactly one persistent TAPD workpad comment for the current Story:
   - use the inventory `tracker.issue_snapshot` typed tool to read comments and workpad candidates
   - prefer the typed snapshot's workpad candidate; for legacy recovery, search returned comments for one that starts with `## TAPD Workpad` or contains `### Plan`, `### Acceptance Criteria`, `### Validation`, and `### Notes`
   - if found, reuse that comment; do not create a parallel active workpad comment
   - if not found, create one comment through the inventory `tracker.upsert_workpad` typed tool and use it for all progress and handoff updates
2. Create or update `.symphony-tapd-workpad.md` so it mirrors the current TAPD workpad comment body for retry recovery and offline scratch use.
   - Rewrite the entire mirror file from that latest comment body every time you sync it.
3. If the session began while the Story was still in `{{ issue.workflow.raw_state_by_route_key.planning }}`,
   treat that as recovery mode only. Under normal backend route preparation, the Story should
   already have reached the backend-confirmed dispatchable route before this step begins.
4. Immediately reconcile the workpad before new edits:
   - check off items that are already done
   - expand or fix the plan so it is comprehensive for current scope
   - ensure `Acceptance Criteria` and `Validation` are current and still make sense for the task
5. Start work by writing or updating a hierarchical plan in the persistent workpad comment, then mirror that content into `.symphony-tapd-workpad.md`.
6. Add explicit acceptance criteria and TODOs in checklist form in the same workpad comment.
   - if changes are user-facing, include a UI walkthrough acceptance criterion that describes the end-to-end user path to validate
   - if changes touch app files or app behavior, add explicit app-specific flow checks to `Acceptance Criteria`
   - if story context includes `Validation`, `Test Plan`, or `Testing` sections, copy those requirements into `Acceptance Criteria` and `Validation` as required checkboxes
7. Run a principal-style self-review of the plan and refine it in the workpad.
8. Before implementing, capture a concrete reproduction signal and record it in the workpad `Notes` section.
9. From `repo/`, run the workspace-root `pull` skill if it exists. Otherwise, use `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" sync-base` when available before any code edits, and record the sync result in the workpad `Notes`.
10. Before code edits or commits, ensure you are on a story-specific working branch rather than `{{ repo.base_branch }}`. Prefer `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" create-working-branch "<unique-story-attempt-id>" --base "origin/{{ repo.base_branch }}"`, then record the branch name in the workpad. Never commit directly on `{{ repo.base_branch }}`.
11. Update the same TAPD workpad comment in place after each meaningful milestone. Keep the local mirror synchronized after each update.
12. Compact context and proceed to execution.

## PR Feedback Sweep Protocol

Use this protocol before moving a story into its next non-dispatch handoff route.

- In the common TAPD baseline, that handoff route is `{{ issue.workflow.raw_state_by_route_key.review }}`.
- If your workflow uses a different resolved non-dispatch handoff route, apply the same sweep
  before entering that route instead of assuming the baseline review state.

1. Identify the PR number from issue links, branch naming, or existing repo state.
2. Read feedback through the inventory `repo.read_change_proposal_discussion`
   typed tool. Treat `unresolvedFeedbackSummary.unresolvedItems` and
   `nextResponseActions` as the canonical response queue for top-level comments,
   change requests, and inline review threads. Use `actionableItems` for full
   item context and `reviewThreads` for grouped inline context. Check
   `feedbackActionPolicy` before submitting review decisions or replies;
   unsupported actions are not fallback invitations.
3. Do not interpret raw provider payloads directly. Prefer each item
   `responseAction`: call `responseAction.tool`, keep its
   `prefilledArguments`, and supply only its `requiredArguments`. Fall back to
   `responseTool` only when `responseAction` is absent. The normal response
   tools are `repo_add_change_proposal_comment` for top-level/change-request
   responses and `repo_reply_change_proposal_review_comment` for inline thread
   replies.
   CNB does not advertise `repo_submit_change_proposal_review`; do not guess a
   CNB review-submit endpoint when that tool is absent.
4. Treat every actionable reviewer comment, human or bot, as blocking until it
   has both a work change or justified pushback and a typed-tool response on the
   original PR/thread. Do not rely only on a new PR, commit message, or workpad
   note to close out human feedback.
5. Update the persistent workpad comment plan and checklist to include each feedback item and its resolution status, then mirror the update locally.
6. Re-run validation after feedback-driven changes, push updates, and confirm
   the typed response was posted through the listed `responseAction.tool` or
   `responseTool`.
7. Repeat this sweep until `unresolvedFeedbackSummary.hasUnresolvedFeedback` is
   false, or every `actionableItems` entry has an explicit completed or
   justified-response entry in the workpad plus a provider-side typed response.

## Blocked-Access Escape Hatch

Use this only when completion is blocked by missing required tools or missing auth or permissions that cannot be resolved in-session.

- Active repo-provider access is not a valid blocker by default. Always try backup strategies first.
- Do not move a story into a non-dispatch handoff route such as `{{ issue.workflow.raw_state_by_route_key.review }}` for active repo-provider access issues until backup strategies have been attempted and documented in the workpad comment.
- If a required non-repo-provider tool is missing, or required non-repo-provider auth is unavailable, update the workpad comment and local mirror with:
  - what is missing
  - why it blocks required acceptance or validation
  - exact human action needed to unblock
- Post one concise standalone TAPD blocker comment only when the workpad comment does not yet exist or cannot be updated.

## Step 2: Execution Phase

This section assumes the current route is dispatchable for implementation work and that any
handoff to `review` still follows the baseline TAPD human-review gate. If the resolved
`review` route policy above differs from that baseline, keep the workpad and validation
discipline here but follow the resolved route-policy contract instead of the default review
handoff described below.

1. From `repo/`, determine current repo state through `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo"` for repo-core covered facts (`preflight`, `status`, and published head when needed), and verify the kickoff `pull` sync result is already recorded in the workpad comment and local mirror before implementation continues.
   - If the current branch is `{{ repo.base_branch }}` or points at `origin/{{ repo.base_branch }}`, create or switch to a story-specific working branch before editing. Do not commit or push implementation changes on the base branch.
2. If the current story state has been moved back to `{{ issue.workflow.raw_state_by_route_key.planning }}`
   during an active session, treat that as a route divergence. Record it in the workpad and stop
   instead of performing a prompt-driven corrective pre-dispatch transition.
3. Load the existing persistent TAPD workpad comment and treat it as the active execution checklist. Keep `.symphony-tapd-workpad.md` synchronized as a local mirror.
4. Implement against the hierarchical TODOs and keep the workpad current:
   - check off completed items
   - add newly discovered items in the appropriate section
   - keep parent-child structure intact as scope evolves
   - update the workpad comment immediately after each meaningful milestone, then mirror it locally
   - never leave completed work unchecked in the plan
   - if the story started with an attached PR, run the PR feedback sweep immediately after kickoff and before new feature work
5. Run validation and tests required for the scope.
   - mandatory gate: execute all ticket-provided `Validation`, `Test Plan`, or `Testing` requirements when present
   - prefer a targeted proof that directly demonstrates the behavior you changed
   - temporary proof edits are allowed for local verification only and must be reverted before commit or push
   - document proof steps and outcomes in the workpad `Validation` and `Notes` sections, then mirror them locally
6. Re-check all acceptance criteria and close any gaps.
7. Before every push attempt, run the required validation for your scope and confirm it passes.
8. Create or update the PR through the inventory `repo.create_or_update_change_proposal` typed tool when it is listed. Confirm the resulting PR with `repo.change_proposal_snapshot` when it is listed.{% if repo.provider.kind == "github" %}{% if repo.provider.options.required_pr_label %}
   - Ensure the PR has label `{{ repo.provider.options.required_pr_label }}`.
   - Prefer workspace-root `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider" pr-add-label "{{ repo.provider.options.required_pr_label }}"` after the PR exists. Pass an explicit PR selector only when the current branch is not the PR branch.
{% endif %}{% endif %}
   - Use the inventory `tracker.attach_change_proposal` typed tool to attach the PR URL. TAPD stores this through the canonical workpad comment until a structured attachment API is available.
   - Mirror the PR URL in `.symphony-tapd-workpad.md`. Symphony publishes TAPD comment links as clickable rich-text hyperlinks for human review flow.
   - Treat this as sufficient for reviewer navigation, while recognizing it is still not a structured attachment/link field equivalent to Linear attachments.
9. Use `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" sync-base` when available to merge latest `origin/{{ repo.base_branch }}` into the branch, resolve conflicts, and rerun checks.
10. Update the persistent workpad comment and local mirror with final checklist status and validation notes.
11. Before moving into the baseline handoff route `{{ issue.workflow.raw_state_by_route_key.review }}` when
    that route remains the resolved handoff target:
   - read the PR `Manual QA Plan` comment when present
   - run the full PR feedback sweep
   - confirm PR checks are green
   - confirm every required validation item is explicitly marked complete in the workpad comment
   - update the persistent workpad comment and local mirror with final PR URL, latest commit SHA, validation summary, and intended review handoff status
   - repeat until no outstanding comments remain and checks are fully passing
12. Only then, when `{{ issue.workflow.raw_state_by_route_key.review }}` remains the resolved handoff route:
   - move the story to `{{ issue.workflow.raw_state_by_route_key.review }}`
   - stop after the state update succeeds; do not rely on another workpad update after `{{ issue.workflow.raw_state_by_route_key.review }}`, because the orchestrator may stop the active agent as soon as the Story leaves `active_states`
13. For stories that already had a PR attached at kickoff:
   - ensure all existing PR feedback was reviewed and resolved, including inline review comments
   - ensure the branch was pushed with any required updates
   - update the persistent workpad comment and local mirror with final validation and handoff state
   - then move the story to `{{ issue.workflow.raw_state_by_route_key.review }}` only when that route remains the resolved handoff target

## Step 3: Baseline Review And Merge Handling

This section describes the common TAPD baseline where `review` remains a non-dispatch wait
route and `merging` remains a dispatchable merge route. If the resolved `review` or
`merging` route policies above differ, the resolved route-policy facts win and this baseline
section must not override them.

1. When the story is in `{{ issue.workflow.raw_state_by_route_key.review }}`, do not code or change the story body.
2. Poll for updates as needed, including active-provider PR review comments from humans and bots plus raw TAPD state changes.
3. If review feedback requires changes, move the story to `{{ issue.workflow.raw_state_by_route_key.rework }}` and follow the rework flow.
4. If approved and PR checks/mergeability are ready, backend change-proposal reconciliation moves the story to `{{ issue.workflow.raw_state_by_route_key.merging }}`. A human may also move it there manually when the local process requires a manual tracker transition.
5. When the story is in `{{ issue.workflow.raw_state_by_route_key.merging }}`, open workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists and follow its loop. Otherwise, merge the PR with the repository's normal repo-core/repo-provider flow after required approvals and checks pass.
6. After merge is complete:
   - update the same workpad comment and local mirror with merge or closure state
   - move the story to `{{ issue.workflow.raw_state_by_route_key.resolved }}` or another configured terminal success state
   - stop after the state update succeeds; do not assume another workpad update will be possible after the Story leaves `active_states`
   - post a short standalone closure comment only when the workpad comment cannot be updated and human traceability still requires a distinct audit event

## Step 4: Baseline Rework Handling

This section assumes `rework` remains a dispatchable route for a fresh implementation
attempt. If the resolved `rework` route policy above differs, follow the resolved
route-policy contract instead of this baseline playbook.

1. Treat `{{ issue.workflow.raw_state_by_route_key.rework }}` as a full approach reset, not incremental patching.
2. Re-read the full story body and all human comments; explicitly identify what will be done differently this attempt.
3. Close the existing PR tied to the story.
4. Keep one active TAPD workpad comment. Reset its `Plan`, `Acceptance Criteria`, `Validation`, and `Notes` sections for the new attempt instead of creating a parallel active workpad comment.
5. Prefer `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" create-working-branch "<unique-story-attempt-id>" --base "origin/{{ repo.base_branch }}"`.
6. Rewrite `.symphony-tapd-workpad.md` from the reset workpad comment so the local mirror matches the new attempt.
7. Restart from the normal kickoff flow.
8. If your raw rework state is not also the active coding state in that workspace, move the story back to `{{ issue.workflow.raw_state_by_route_key.developing }}` before active implementation resumes.

## Completion Bar Before Non-Dispatch Handoff

Use this bar before moving a story into its next non-dispatch handoff route.

- In the common TAPD baseline, that handoff route is `{{ issue.workflow.raw_state_by_route_key.review }}`.

- Step 1 and Step 2 checklist is fully complete and accurately reflected in the persistent TAPD workpad comment and local mirror.
- Acceptance criteria and required ticket-provided validation items are complete.
- Validation and tests are green for the latest commit.
- PR feedback sweep is complete and no actionable comments remain.
- PR checks are green, branch is pushed, and the PR URL is recorded in the workpad comment and local mirror.
{% if repo.provider.kind == "github" %}{% if repo.provider.options.required_pr_label %}- Required PR metadata is present (`{{ repo.provider.options.required_pr_label }}` label), or the repository-specific GitHub workflow has explicitly validated/enforced it outside the helper.
{% endif %}{% endif %}
- If app-touching, runtime validation or media requirements are complete.

## Guardrails

- If the branch PR is already closed or merged, do not reuse that branch or prior implementation state for continuation.
- If the story state is outside the configured TAPD workflow states above, do not modify it automatically.
- Do not treat this prompt as the authoritative source of route-policy side effects; backend
  `tracker.lifecycle.policy_by_route_key` owns normal pre-dispatch route preparation.
- Do not edit the story body or description for planning or progress tracking unless the task explicitly requires a content change.
- Use exactly one persistent TAPD workpad comment per Story.
- Use exactly one local mirror file (`.symphony-tapd-workpad.md`) per active attempt.
- Never stage or commit the local TAPD workpad file.
- The persistent TAPD workpad comment is the source of truth for detailed execution state.
- `.symphony-tapd-workpad.md` is a mirror/cache, not the source of truth.
- Do not copy, move, or merge `repo/.codex` or `repo/.agents` into workspace-root automation directories during normal task execution.
- Do not post extra standalone TAPD progress comments when the workpad comment can be updated in place.
- If comment creation fails because of `platform.comment_author`, use the authenticated API user when business constraints allow it; otherwise treat it as a blocker.
- Temporary proof edits are allowed only for local verification and must be reverted before commit.
- If out-of-scope improvements are found, create and link a follow-up TAPD Story in-session instead of expanding current scope. If TAPD rejects the create/link operation, document the failure plus the intended follow-up clearly in the workpad comment and local mirror.
- Do not move a story into a non-dispatch handoff route such as `{{ issue.workflow.raw_state_by_route_key.review }}` unless the completion bar is satisfied.
- When the current route is a non-dispatch wait route such as the baseline `{{ issue.workflow.raw_state_by_route_key.review }}` route, do not make changes; wait and poll.
- If state is terminal, do nothing and shut down.
- Keep the persistent TAPD workpad concise, specific, and reviewer-oriented.
- Keep the TAPD-side comment body Markdown-friendly and within the supported workpad structure so Symphony can round-trip it cleanly through TAPD HTML rendering.
- If blocked and no workpad comment exists yet, create one before posting a standalone blocker comment when possible.

## Local Workpad Template

Use this exact structure for the persistent TAPD workpad comment and mirror the same content into `.symphony-tapd-workpad.md` throughout execution:

````md
## CodeBuddy Code Workpad

### Plan

- [ ] 1. Parent task
  - [ ] 1.1 Child task
  - [ ] 1.2 Child task
- [ ] 2. Parent task

### Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2

### Validation

- [ ] targeted tests: `<command>`

### Notes

- <short progress note with timestamp>
- branch_name: pending
- commit_sha: pending
- pr_url: pending
- pr_state: pending

### Confusions

- <only include when something was confusing during execution>
````

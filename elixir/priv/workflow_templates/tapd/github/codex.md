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
      # state_phase_map, and route-key raw statuses below. Symphony still
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
    # Route policy defaults are owned by the selected workflow profile. Add
    # policy_by_route_key here only for deliberate template-specific overrides.
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
agent_provider:
  kind: codex
  options:
    command: codex --config shell_environment_policy.inherit=all --config model_reasoning_effort=medium --config 'project_root_markers=[]' --model gpt-5.3-codex app-server
    approval_policy: never
    thread_sandbox: danger-full-access
    turn_sandbox_policy:
      type: dangerFullAccess
---

You are working on a TAPD story `{{ issue.identifier }}`

<!-- symphony-include: _partials/runtime/retry_continuation_context.md -->

Story context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Workitem type: {% if issue.workitem_type_id %}{{ issue.workitem_type_id }}{% else %}unknown{% endif %}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Current workflow contract for this Story:
- profile: `{{ workflow.profile.kind }}` v{{ workflow.profile.version }}
- current route: {% if workflow.route.key %}`{{ workflow.route.key }}`{% else %}`unresolved`{% endif %}; action `{{ workflow.route.action }}`; gate `{{ workflow.gate.status }}/{{ workflow.gate.gate }}`
- gate reason: {{ workflow.gate.reason }}
- allowed completion routes: {{ workflow.completion_contract.allowed_completion_routes }}
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
2. Follow the resolved route policy and the completion bars in this workflow template for when tracker, repo, PR, and handoff actions are allowed.
3. Use the generated Typed Workflow Tool Inventory plus the bundled TAPD and repo skills for how to perform those actions. Do not invent direct TAPD/GitHub/API fallbacks outside those documented capability boundaries.
4. Maintain exactly one persistent workpad comment per active Story and keep it mirrored to the local untracked workpad file for retry recovery and offline scratch use.
5. Only stop early for a true blocker such as missing TAPD auth, missing repository permissions, missing required repo-provider access, or a required external tool being unavailable.
6. Final message must report completed actions and blockers only. Do not include next-step instructions for a human operator.

## Critical Execution Summary

Follow this main path unless the resolved route policy says otherwise:

1. Read the Story snapshot and resolved route policy.
2. Ensure exactly one canonical TAPD workpad exists, then mirror it to `.symphony-tapd-workpad.md`.
3. Sync the base branch and work only on a story-specific branch under `repo/`.
4. Implement against the workpad plan and the Story scope.
5. Run required validation and record evidence in the workpad and mirror.
6. Create or update the GitHub PR through inventory-listed typed tools.
7. Read PR checks and discussion after the latest push.
8. Refresh the workpad and mirror with final handoff evidence.
9. Move the Story to the resolved handoff route only after the quality bar passes.

Work only in the provided repository copy at `repo/`. The only allowed workspace-root artifacts are local automation support files under `SYMPHONY_WORKSPACE_AUTOMATION_DIR` and `.symphony-tapd-workpad.md`. Do not copy or promote `repo/.codex`, `repo/.agents`, or other repo-local automation config into the workspace root unless the task explicitly requires editing repository automation config.

## Provider Runtime: Codex App Server Dynamic Tools

Codex receives Symphony Dynamic Tools through the runtime MCP bridge configured
by Symphony at session startup. This template runs Codex in app-server mode with
`approval_policy: never` and a `danger-full-access` sandbox, so do not ask for
interactive approvals and strictly preserve the repository/workspace artifact
boundaries described here. For routine TAPD tracker actions, repo-core actions,
and GitHub repo-provider change-proposal actions, use the exact
provider-facing callable names listed in the generated inventory below. The
inventory is the source for provider-specific callable names; the bundled
skills define typed capability semantics and argument shape. If a required
typed tool is missing, stop as blocked, record the blocker in the TAPD workpad
when workpad tooling is available, and follow workflow-defined blocker
handling. Do not ask a human for interactive setup during the session.

## Prerequisites

- This template is intended to stay a peer of `elixir/WORKFLOW.md`. Keep tracker-agnostic execution discipline aligned unless a TAPD platform constraint requires an explicit divergence.
- Set `SOURCE_REPO_URL` when using the default `hooks.after_create`; it fails fast if the variable is missing. If that does not fit your repo, replace `hooks.after_create` with the target repo clone/bootstrap commands that your repository actually needs.
- The generated tool inventory must include the typed tracker and repo-provider capabilities required by the route being executed. If a required capability is missing, stop and record a blocker instead of switching to an undocumented provider access path.
- If required non-TAPD tooling or auth is missing, use the blocked-access escape hatch rather than improvising around missing controls.

## TAPD Access And Tools

<!-- symphony-include: _partials/tracker/tapd_access_and_tools.md -->

## GitHub Provider Notes

<!-- symphony-include: _partials/repo_provider/github_change_proposal_notes.md -->

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

## TAPD Workpad Contract

<!-- symphony-include: _partials/tracker/tapd_workpad_contract.md -->

## TAPD Execution Lifecycle

<!-- symphony-include: _partials/tracker/tapd_execution_lifecycle.md -->

## TAPD Manual Review And Merge Lifecycle

<!-- symphony-include: _partials/tracker/tapd_manual_review_merge_lifecycle.md -->

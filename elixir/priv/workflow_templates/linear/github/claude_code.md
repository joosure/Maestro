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
polling:
  interval_ms: 5000
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
  kind: claude_code
  options:
    command_argv: ["claude"]
    prompt_transport: stream_json
    permission_mode: bypassPermissions
    # Claude Code accepts `sonnet` as a model alias. This template keeps the
    # alias so it follows Claude Code's current Sonnet selection; replace it
    # with a full model id when a run must be pinned for reproducibility.
    model: sonnet
---

You are working on a Linear ticket `{{ issue.identifier }}`

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the ticket is still in an active state.
- Resume from the current workspace state instead of restarting from scratch.
- Do not repeat already-completed investigation or validation unless needed for new code changes.
- Do not end the turn while the issue remains in an active state unless you are blocked by missing required typed tools, permissions, or secrets.
  {% endif %}

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

Work only in the provided repository copy at `repo/`. The only allowed workspace-root artifacts are local automation support files under `SYMPHONY_WORKSPACE_AUTOMATION_DIR`. Do not copy or promote `repo/.codex`, `repo/.agents`, or other repo-local automation config into the workspace root unless the task explicitly requires editing repository automation config.

## Provider Runtime: Claude Code MCP dynamic-tool bridge

Claude Code receives Symphony Dynamic Tools through the MCP dynamic-tool bridge
generated for this workspace. This is a Claude Code provider runtime
prerequisite whenever this session exposes Dynamic Tools; it is not a
Linear/GitHub workflow prerequisite. For routine Linear tracker actions,
repo-core actions, and repo-provider change-proposal actions, call the exact
provider-facing callable tool names listed in the generated inventory below.
The inventory is the only source for Claude Code's provider-specific callable
names; do not derive a callable name from an internal runtime tool name. If a
required typed tool is missing from the generated inventory, stop as blocked,
record the blocker in the workpad when workpad tooling is available, and follow
workflow-defined blocker handling. Do not ask a human for interactive setup
during the session.

{{ tool_inventory }}

For Linear tracker actions, open and follow the bundled workspace skill:
`${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/tracker/linear/SKILL.md`.
This workflow defines when tracker actions are allowed; the skill defines the
Linear typed capability semantics and argument shape. Use inventory-listed
typed tracker tools and treat missing typed capabilities as blockers.
For repo-core or repo-provider operations covered by the inventory, use the
typed tool. Use repo-core or repo-provider helpers only for unsupported
operations, diagnostics, or documented fallback.
For repo-core typed tools, use canonical typed-tool argument values from the
inventory. In particular, `repo.commit` mode is `all` or `staged`, and
`repo.checkout` mode is `create_or_switch`, `create`, or `switch`; do not send
helper command names or aliases as typed-tool arguments.
When creating or updating a change proposal through a typed repo-provider tool,
omit `body` when the configured generated default is sufficient. If you provide
`body`, pass the proposal description as a single string argument; do not split
Markdown sections into extra tool arguments.
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
- The active repo provider for bundled automation is `{{ repo.provider.kind }}`.
- `SYMPHONY_WORKSPACE_AUTOMATION_DIR` points at the workspace-root automation directory for the active agent provider.
- Run build, test, and code-edit commands from `repo/`. For repo-core actions covered by the inventory, use the exact typed tool; use normal git only for low-level inspection that repo-core does not expose.
- Leave any `repo/.codex` or `repo/.agents` content in place; do not merge it into the workspace root during normal ticket execution.
- When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo` exists, treat it as the repo-core helper fallback for provider-neutral repo facts and supported Git side effects that are not covered by the typed tool inventory, or when documented fallback is explicitly required. It delegates to `symphony repo` and does not perform PR, review, check, or provider merge operations.
- When workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo-provider` exists, use it only for provider-backed PR view/create/edit/check/merge/close operations that are not covered by the typed tool inventory or when documented fallback is explicitly required.

## Default posture

- Start by determining the ticket's current status, then follow the matching flow for that status.
- Start every task by opening the tracking workpad comment and bringing it up to date before doing new implementation work.
- Spend extra effort up front on planning and verification design before implementation.
- Reproduce first: always confirm the current behavior/issue signal before changing code so the fix target is explicit.
- Keep ticket metadata current (state, checklist, acceptance criteria, links).
- Treat a single persistent Linear comment as the source of truth for progress.
- Use that single workpad comment for all progress and handoff notes; do not post separate "done"/summary comments.
- Treat any ticket-authored `Validation`, `Test Plan`, or `Testing` section as non-negotiable acceptance input: mirror it in the workpad and execute it before considering the work complete.
- When meaningful out-of-scope improvements are discovered during execution,
  file a separate Linear issue instead of expanding scope. The follow-up issue
  must include a clear title, description, and acceptance criteria, be placed in
  `Backlog`, be assigned to the same project as the current issue, link the
  current issue as `related`, and use `blockedBy` when the follow-up depends on
  the current issue.
- Move status only when the matching quality bar is met.
- Operate autonomously end-to-end unless blocked by missing requirements, secrets, or permissions.
- Use the blocked-access escape hatch only for true external blockers (missing required tools/auth) after exhausting documented backup paths.

## Related skills

Workspace-root automation skills can help. They stay separate from any `repo/.codex` or `repo/.agents` content:

- `linear`: interact with Linear.
- `commit`: produce clean, logical commits during implementation.
- `push`: keep remote branch current and publish updates.
- `pull`: keep branch updated with latest `origin/{{ repo.base_branch }}` before handoff.
- `land`: when ticket reaches `Merging`, open workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists.

## Status map

- `Backlog` -> out of scope for this workflow; do not modify.
- `Todo` -> queued; immediately transition to `In Progress` before active work.
  - Special case: if a PR is already attached, treat as feedback/rework loop (run full PR feedback sweep, address or explicitly push back, revalidate, return to `In Review`).
- `In Progress` -> implementation actively underway.
- `In Review` -> PR is attached and validated; waiting on human approval.
- `Merging` -> approved by human; execute the `land` skill flow (do not call provider merge commands directly).
- `Rework` -> reviewer requested changes; planning + implementation required.
- `Done` -> terminal state; no further action required.

## Step 0: Determine current ticket state and route

1. Fetch the issue by explicit ticket ID through the inventory `tracker.issue_snapshot` typed tool.
2. Read the current state from that snapshot.
3. Route to the matching flow:
   - `Backlog` -> do not modify issue content/state; stop and wait for human to move it to `Todo`.
   - `Todo` -> immediately move to `In Progress`, then ensure bootstrap workpad comment exists (create if missing), then start execution flow.
     - If PR is already attached, start by reviewing all open PR comments and deciding required changes vs explicit pushback responses.
   - `In Progress` -> continue execution flow from the current workpad comment.
   - `In Review` -> wait and poll for decision/review updates.
   - `Merging` -> on entry, open workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists and follow it. Otherwise, use the inventory `repo.merge_change_proposal` typed tool when it is listed; use the repository's normal repo-core/repo-provider fallback flow only when documented fallback is explicitly required.
   - `Rework` -> run rework flow.
   - `Done` -> do nothing and shut down.
4. Check whether a PR already exists for the current branch and whether it is closed.
   - Use the inventory `repo.change_proposal_snapshot` typed tool with the current workflow branch when it is listed; use documented fallback only if snapshot capability is unavailable and fallback is explicitly allowed.
   - If a branch PR exists and is `CLOSED` or `MERGED`, treat prior branch work as non-reusable for this run.
   - Prefer `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" create-working-branch "<unique-issue-attempt-id>" --base "origin/{{ repo.base_branch }}"` and restart execution flow as a new attempt.
5. For `Todo` tickets, do startup sequencing in this exact order:
   - Use the inventory `tracker.move_issue` typed tool to move the issue to `In Progress`.
   - Find or create the `## Claude Code Workpad` bootstrap comment through inventory-listed typed tracker tools.
   - Only then begin analysis/planning/implementation work.
6. Record a short note in the workpad if state and issue content are inconsistent, then proceed with the safest flow.

## Step 1: Start/continue execution (Todo or In Progress)

1.  Find or create a single persistent workpad comment for the issue:
    - Use the inventory `tracker.issue_snapshot` typed tool with comments included to inspect existing issue comments and workpad candidates.
    - Search snapshot comments for a marker header: `## Claude Code Workpad`.
    - Ignore resolved comments while searching; only active/unresolved comments are eligible to be reused as the live workpad.
    - If found, reuse that comment; do not create a new workpad comment.
    - If not found, create one workpad comment through the inventory `tracker.upsert_workpad` typed tool and use it for all updates.
    - Persist the workpad comment ID and only write progress updates to that ID.
2.  If arriving from `Todo`, do not delay on additional status transitions: the issue should already be `In Progress` before this step begins.
3.  Immediately reconcile the workpad before new edits:
    - Check off items that are already done.
    - Expand/fix the plan so it is comprehensive for current scope.
    - Ensure `Acceptance Criteria` and `Validation` are current and still make sense for the task.
4.  Start work by writing/updating a hierarchical plan in the workpad comment.
5.  Ensure the workpad includes a compact environment stamp at the top as a code fence line:
    - Format: `<host>:<abs-workdir>@<short-sha>`
    - Example: `devbox-01:/home/dev-user/code/maestro-workspaces/MT-32/repo@7bdde33bc`
    - Do not include metadata already inferable from issue fields (`issue ID`, `status`, `branch`, `PR link`).
6.  Add explicit acceptance criteria and TODOs in checklist form in the same comment.
    - If changes are user-facing, include a UI walkthrough acceptance criterion that describes the end-to-end user path to validate.
    - If changes touch app files or app behavior, add explicit app-specific flow checks to `Acceptance Criteria` in the workpad (for example: launch path, changed interaction path, and expected result path).
    - If the ticket description/comment context includes `Validation`, `Test Plan`, or `Testing` sections, copy those requirements into the workpad `Acceptance Criteria` and `Validation` sections as required checkboxes (no optional downgrade).
7.  Run a principal-style self-review of the plan and refine it in the comment.
8.  Before implementing, capture a concrete reproduction signal and record it in the workpad `Notes` section (command/output, screenshot, or deterministic UI behavior).
9.  From `repo/`, run the workspace-root `pull` skill if it exists. Otherwise, use `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" sync-base` when available before any code edits, and record the pull/sync result in the workpad `Notes`.
    - Include a `pull skill evidence` note with:
      - merge source(s),
      - result (`clean` or `conflicts resolved`),
      - resulting `HEAD` short SHA.
10. Compact context and proceed to execution.

## PR feedback sweep protocol (required)

When a ticket has an attached PR, run this protocol before moving to `In Review`:

1. Identify the PR number from issue links/attachments.
2. Gather feedback from all channels:
   - Use the inventory `repo.read_change_proposal_discussion` typed tool when it is listed.
     Treat `unresolvedFeedbackSummary.unresolvedItems` and
     `nextResponseActions` as the canonical response queue, use
     `actionableItems` for full item context, and use `reviewThreads` for inline
     thread context. Check `feedbackActionPolicy` before submitting review
     decisions or replies; unsupported actions are not fallback invitations.
     When an actionable item includes `responseAction`, call its `tool`, keep
     its `prefilledArguments`, and supply only its `requiredArguments` instead
     of guessing provider-specific reply parameters.
   - Use the inventory `repo.add_change_proposal_comment` typed tool for required top-level PR comments when it is listed.
   - Use the inventory `repo.submit_change_proposal_review` typed tool only when it is listed and the workflow explicitly needs to submit a review decision.
   - Use the inventory `repo.reply_change_proposal_review_comment` typed tool for required inline review replies when it is listed.
   - If a required feedback capability is missing from the inventory, stop as blocked and record the missing typed repo capability instead of interpreting provider helper output directly.
3. Treat every actionable reviewer comment (human or bot), including inline review comments, as blocking until one of these is true:
   - code/test/docs updated to address it, or
   - explicit, justified pushback reply is posted on that thread through the item's `responseAction.tool` when present, or through the inventory reply/comment typed tool when listed.
4. Update the workpad plan/checklist to include each feedback item and its resolution status.
5. Re-run validation after feedback-driven changes and push updates.
6. Repeat this sweep until `unresolvedFeedbackSummary.hasUnresolvedFeedback` is false, or there are no outstanding actionable comments.

## Blocked-access escape hatch (required behavior)

Use this only when completion is blocked by missing required tools or missing auth/permissions that cannot be resolved in-session.

- Active repo-provider access/auth is **not** a valid blocker by default. Always try documented backup strategies first, then continue publish/review flow.
- Do not move to `In Review` for active repo-provider access/auth until all backup strategies have been attempted and documented in the workpad.
- If a required non-repo-provider tool is missing, or required non-repo-provider auth is unavailable, move the ticket to `In Review` with a short blocker brief in the workpad only when the required tracker workpad and state-transition tools are available. The brief must include:
  - what is missing,
  - why it blocks required acceptance/validation,
  - exact human action needed to unblock.
- If the missing capability is the tracker workpad or state-transition tool required to record or move the blocker, stop and report that missing typed tracker capability instead of using non-inventory tracker access.
- Keep the brief concise and action-oriented; do not add extra top-level comments outside the workpad.

## Step 2: Execution phase (Todo -> In Progress -> In Review)

1.  From `repo/`, use inventory-listed repo-core typed tools for supported branch, diff, commit, and push actions (`repo.checkout`, `repo.diff`, `repo.commit`, `repo.push`). Use `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo"` only for repo-core facts not yet covered by typed tools (`preflight`, `status`, and published head when needed). Verify the kickoff `pull` sync result is already recorded in the workpad before implementation continues.
2.  If current issue state is `Todo`, move it to `In Progress`; otherwise leave the current state unchanged.
3.  Load the existing workpad comment and treat it as the active execution checklist.
    - Edit it liberally whenever reality changes (scope, risks, validation approach, discovered tasks).
4.  Implement against the hierarchical TODOs and keep the comment current:
    - Check off completed items.
    - Add newly discovered items in the appropriate section.
    - Keep parent/child structure intact as scope evolves.
    - Update the workpad immediately after each meaningful milestone (for example: reproduction complete, code change landed, validation run, review feedback addressed).
    - Never leave completed work unchecked in the plan.
    - For tickets that started as `Todo` with an attached PR, run the full PR feedback sweep protocol immediately after kickoff and before new feature work.
5.  Run validation/tests required for the scope.
    - Mandatory gate: execute all ticket-provided `Validation`/`Test Plan`/ `Testing` requirements when present; treat unmet items as incomplete work.
    - Prefer a targeted proof that directly demonstrates the behavior you changed.
    - You may make temporary local proof edits to validate assumptions (for example: tweak a local build input for `make`, or hardcode a UI account / response path) when this increases confidence.
    - Revert every temporary proof edit before commit/push.
    - Document these temporary proof steps and outcomes in the workpad `Validation`/`Notes` sections so reviewers can follow the evidence.
    - If app-touching, run the target repository's documented launch or runtime validation from `repo/`, and record concrete evidence such as commands, logs, screenshots, or screen recordings in the workpad or change proposal.
6.  Re-check all acceptance criteria and close any gaps.
7.  Before every push attempt, run the required validation for your scope and confirm it passes; if it fails, address issues and rerun until green, then commit and push changes.
    - Before the final push, use `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" sync-base` when available to merge latest `origin/{{ repo.base_branch }}` into the branch, resolve conflicts, rerun required validation, and push the merged branch.
    - After the final commit and after any `sync-base`, run a final PR-diff whitespace check against the base branch: `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" diff-check "origin/{{ repo.base_branch }}...HEAD"` when the helper exists, otherwise `git diff --check "origin/{{ repo.base_branch }}...HEAD"`.
    - Do not substitute plain `git diff --check` on a clean working tree for the final PR-diff check; it does not validate already-committed whitespace.
8.  Create or update the PR through the inventory `repo.create_or_update_change_proposal` typed tool when it is listed.
    - For a new PR, pass `mode: "create"`, `title`, `base: "{{ repo.base_branch }}"`, and the pushed head branch.
    - For an existing PR, pass `mode: "update"` with `number`, `url`, or `branch`.
    - Confirm the resulting PR with `repo.change_proposal_snapshot` when it is listed and use the confirmed PR URL for issue attachment.
{% if repo.provider.kind == "github" %}{% if repo.provider.options.required_pr_label %}    - Ensure the PR has label `{{ repo.provider.options.required_pr_label }}`.
    - Apply the label through the inventory `repo.create_or_update_change_proposal` typed tool by passing `labels: ["{{ repo.provider.options.required_pr_label }}"]` during create or update. Do not call `repo-provider`, `gh`, or direct GitHub APIs for label handling when the typed tool is listed.
{% endif %}{% endif %}
9.  Attach PR URL to the issue through the inventory `tracker.attach_change_proposal` typed tool. If it is missing, stop as blocked and record the missing typed tracker capability. Prefer tracker attachment/link fields and use the workpad comment only when the typed attach flow reports that attachment/link storage is unavailable.
10. Update the workpad comment with final checklist status and validation notes.
    - Mark completed plan/acceptance/validation checklist items as checked.
    - Add final handoff notes (commit + validation summary) in the same workpad comment.
    - Do not include PR URL in the workpad comment when an issue attachment/link exists; keep PR linkage on the issue via attachment/link fields. Only record the PR URL in the workpad when attachment/link storage was unavailable, and include the fallback reason.
    - Add a short `### Confusions` section at the bottom when any part of task execution was unclear/confusing, with concise bullets.
    - Do not post any additional completion summary comment.
11. Before moving to `In Review`, poll PR feedback and checks:
    - Read the PR `Manual QA Plan` comment (when present) and use it to sharpen UI/runtime test coverage for the current change.
    - Run the full PR feedback sweep protocol.
    - Confirm PR checks are passing (green) after the latest changes using the inventory `repo.read_change_proposal_checks` typed tool when it is listed.
    - Confirm the final PR-diff whitespace check passed after the latest commit and push.
    - Confirm every required ticket-provided validation/test-plan item is explicitly marked complete in the workpad.
    - Repeat this check-address-verify loop until no outstanding comments remain and checks are fully passing.
    - Re-open and refresh the workpad before state transition so `Plan`, `Acceptance Criteria`, and `Validation` exactly match completed work.
12. Only then move issue to `In Review`.
    - Exception: if blocked by missing required non-repo-provider tools/auth per the blocked-access escape hatch, move to `In Review` with the blocker brief and explicit unblock actions only when tracker state-transition tooling is available.
13. For `Todo` tickets that already had a PR attached at kickoff:
    - Ensure all existing PR feedback was reviewed and resolved, including inline review comments (code changes or explicit, justified pushback response).
    - Ensure branch was pushed with any required updates.
    - Then move to `In Review`.

## Step 3: In Review and merge handling

1. When the issue is in `In Review`, do not code or change ticket content except for the workflow state transition described below.
2. Poll for updates as needed, including active-provider PR review comments from humans and bots.
3. If review feedback requires changes, move the issue to `Rework` and follow the rework flow.
4. If approved, human moves the issue to `Merging`.
5. When the issue is in `Merging`, open workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists and follow its loop. Otherwise, use the inventory `repo.merge_change_proposal` typed tool when it is listed; use the repository's normal repo-core/repo-provider fallback flow only when documented fallback is explicitly required.
6. After merge is complete, move the issue to `Done`.

## Step 4: Rework handling

1. Treat `Rework` as a full approach reset, not incremental patching.
2. Re-read the full issue body and all human comments; explicitly identify what will be done differently this attempt.
3. Close the existing PR tied to the issue using the inventory `repo.close_change_proposal` typed tool when it is listed; use repo-provider fallback only when documented fallback is explicitly required.
4. Reset the existing `## Claude Code Workpad` comment through the inventory `tracker.upsert_workpad` typed tool; do not delete the comment or create a parallel workpad.
5. Prefer `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" create-working-branch "<unique-issue-attempt-id>" --base "origin/{{ repo.base_branch }}"`.
6. Start over from the normal kickoff flow:
   - If current issue state is `Todo`, move it to `In Progress`; otherwise keep the current state.
   - Rewrite the same `## Claude Code Workpad` comment with a fresh plan/checklist.
   - Build a fresh plan/checklist and execute end-to-end.

## Completion bar before In Review

- Step 1/2 checklist is fully complete and accurately reflected in the single workpad comment.
- Acceptance criteria and required ticket-provided validation items are complete.
- Validation/tests are green for the latest commit, including final PR-diff whitespace check against `origin/{{ repo.base_branch }}...HEAD`.
- PR feedback sweep is complete and no actionable comments remain.
- PR checks are green, branch is pushed, and PR is linked on the issue, or fallback PR link storage is recorded in the workpad when issue attachment/link storage is unavailable.
{% if repo.provider.kind == "github" %}{% if repo.provider.options.required_pr_label %}- Required PR metadata is present (`{{ repo.provider.options.required_pr_label }}` label), or the repository-specific GitHub workflow has explicitly validated/enforced it outside the helper.
{% endif %}{% endif %}
- If app-touching, target-repository runtime validation evidence is recorded in the workpad or change proposal.

## Guardrails

- If the branch PR is already closed/merged, do not reuse that branch or prior implementation state for continuation.
- For closed/merged branch PRs, create a new branch with `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" create-working-branch "<unique-issue-attempt-id>" --base "origin/{{ repo.base_branch }}"` and restart from reproduction/planning as if starting fresh.
- If issue state is `Backlog`, do not modify it; wait for human to move to `Todo`.
- Do not edit the issue body/description for planning or progress tracking.
- Use exactly one persistent workpad comment (`## Claude Code Workpad`) per issue, and update it through the inventory `tracker.upsert_workpad` typed tool.
- If `tracker.upsert_workpad` is unavailable, report a missing typed tracker capability; do not use external comment update tooling.
- Do not copy, move, or merge `repo/.codex` or `repo/.agents` into workspace-root automation directories during normal task execution.
- Temporary proof edits are allowed only for local verification and must be reverted before commit.
- If out-of-scope improvements are found, create a separate Backlog issue rather
  than expanding current scope, and include a clear
  title/description/acceptance criteria, same-project assignment, a `related`
  link to the current issue, and `blockedBy` when the follow-up depends on the
  current issue.
- Do not move to `In Review` unless the `Completion bar before In Review` is satisfied.
- In `In Review`, do not make changes; wait and poll.
- If state is terminal (`Done`), do nothing and shut down.
- Keep issue text concise, specific, and reviewer-oriented.
- If blocked and no workpad exists yet, create one through inventory-listed typed tracker tooling and describe blocker, impact, and next unblock action. If the required typed tracker tooling is missing, report that missing capability instead of using non-inventory tracker access.

## Workpad template

Use this exact structure for the persistent workpad comment and keep it updated in place throughout execution:

````md
## Claude Code Workpad

```text
<hostname>:<abs-path>@<short-sha>
```

### Plan

- [ ] 1\. Parent task
  - [ ] 1.1 Child task
  - [ ] 1.2 Child task
- [ ] 2\. Parent task

### Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2

### Validation

- [ ] targeted tests: `<command>`

### Notes

- <short progress note with timestamp>

### Confusions

- <only include when something was confusing during execution>
````

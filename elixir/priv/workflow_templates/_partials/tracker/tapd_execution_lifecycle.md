Use this lifecycle when the current TAPD route is dispatchable for implementation
or for preparing a handoff from implementation to the configured non-dispatch
review route.

Route and workpad bootstrap:

1. Fetch the Story with `tracker.issue_snapshot`; use the issue identity supplied by the current workflow context.
2. Route by the resolved route key, configured raw status, and resolved policy:
   - unmapped raw status -> do not modify the Story; record a blocker
   - `planning` route with raw status `{{ issue.workflow.raw_state_by_route_key.planning }}` and backend transition policy -> record a route-preparation anomaly; do not perform prompt-driven pre-dispatch transitions
   - `developing` route with raw status `{{ issue.workflow.raw_state_by_route_key.developing }}` or `rework` route with raw status `{{ issue.workflow.raw_state_by_route_key.rework }}` and dispatch policy -> continue implementation
   - `review` route with raw status `{{ issue.workflow.raw_state_by_route_key.review }}` and wait policy -> do not code or mutate state; wait/poll
   - `merging` route with raw status `{{ issue.workflow.raw_state_by_route_key.merging }}` and dispatch policy -> run the merge/land flow
   - terminal stop route -> do nothing and shut down
3. Respect the configured TAPD workitem type scope. Do not assume other Story subtypes share this workflow unless they are configured or discovered as matching types.
4. Check whether a branch PR already exists and whether it is closed or merged.
   - If a branch PR exists and is `CLOSED` or `MERGED`, treat prior branch work as non-reusable for this run.
   - Prefer `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" create-working-branch "<unique-story-attempt-id>" --base "origin/{{ repo.base_branch }}"` and restart execution flow as a new attempt.
5. If you must stop before the workpad exists, create one when possible; otherwise post one concise standalone blocker comment.
6. Find or create exactly one persistent workpad through typed tracker tools:
   - read `workpad_id` from `tracker.issue_snapshot`
   - pass `workpad_id` to `tracker.upsert_workpad` when present
   - omit `workpad_id` only when no registered workpad exists; the adapter creates and registers the canonical workpad
   - do not search comments by title or Markdown shape yourself; never use body text as workpad identity
7. Keep `.symphony-tapd-workpad.md` as a full-file mirror of the latest workpad body for retry recovery and offline scratch use.
8. If the session began while the Story was still in `{{ issue.workflow.raw_state_by_route_key.planning }}`, treat that as recovery mode only. Under normal backend route preparation, the Story should already have reached the backend-confirmed dispatchable route before this step begins.

Planning and branch setup:

1. Reconcile the workpad before new edits:
   - check off items that are already done
   - expand or fix the plan so it is comprehensive for current scope
   - ensure `Acceptance Criteria` and `Validation` are current and still make sense for the task
2. Start work by writing or updating a hierarchical plan in the persistent workpad comment, then mirror it.
3. Add explicit acceptance criteria and TODOs in checklist form in the same workpad comment.
   - if changes are user-facing, include a UI walkthrough acceptance criterion that describes the end-to-end user path to validate
   - if changes touch app files or app behavior, add explicit app-specific flow checks to `Acceptance Criteria`
   - if story context includes `Validation`, `Test Plan`, or `Testing` sections, copy those requirements into `Acceptance Criteria` and `Validation` as required checkboxes
4. Review the plan for missing scope, validation gaps, and risky assumptions; refine it in the workpad.
5. Before implementing, capture a concrete reproduction signal and record it in the workpad `Notes` section.
6. From `repo/`, run the workspace-root `pull` skill if it exists; otherwise use `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" sync-base` when available. Record the result in `Notes`.
7. Before code edits or commits, ensure you are on a story-specific working branch rather than `{{ repo.base_branch }}`. Prefer `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" create-working-branch "<unique-story-attempt-id>" --base "origin/{{ repo.base_branch }}"`, then record the branch name in the workpad. Never commit directly on `{{ repo.base_branch }}`.
8. Update the same workpad comment in place after each meaningful milestone and resync the mirror.

Implementation:

1. From `repo/`, determine current repo state through inventory-listed repo-core typed tools when they cover the needed facts. Use `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo"` only as documented fallback for repo-core facts not exposed by the inventory.
2. If the current story state has been moved back to `{{ issue.workflow.raw_state_by_route_key.planning }}` during an active session, treat that as a route divergence. Record it in the workpad and stop instead of performing a prompt-driven corrective pre-dispatch transition.
3. Implement against the workpad TODOs:
   - check off completed items
   - add newly discovered items in the appropriate section
   - keep parent-child structure intact as scope evolves
   - never leave completed work unchecked in the plan
   - if the story started with an attached PR, run the PR feedback sweep immediately after kickoff and before new feature work

Validation:

1. Run validation and tests required for the scope.
   - mandatory gate: execute all ticket-provided `Validation`, `Test Plan`, or `Testing` requirements when present
   - prefer a targeted proof that directly demonstrates the behavior you changed
   - temporary proof edits are allowed for local verification only and must be reverted before commit or push
   - document proof steps and outcomes in the workpad
2. Re-check all acceptance criteria and close any gaps.
3. Before every push attempt, run the required validation for your scope and confirm it passes.

PR creation and feedback:

1. Before moving a Story into its next non-dispatch handoff route, run the PR feedback sweep. In the common TAPD baseline, that route is `{{ issue.workflow.raw_state_by_route_key.review }}`.
   - Identify the PR number from issue links, branch naming, or existing repo state.
   - Read feedback through the inventory `repo.read_change_proposal_discussion` typed tool. Treat `unresolvedFeedbackSummary.unresolvedItems` and `nextResponseActions` as the canonical response queue for top-level comments, change requests, and inline review threads. Use `actionableItems` and `reviewThreads` for context. Check `feedbackActionPolicy`; unsupported actions are not fallback invitations.
   - Do not interpret raw provider payloads directly. Prefer each item `responseAction`: call `responseAction.tool`, keep its `prefilledArguments`, and supply only its `requiredArguments`. Fall back to `responseTool` only when `responseAction` is absent. The normal response tools are `repo_add_change_proposal_comment` for top-level/change-request responses and `repo_reply_change_proposal_review_comment` for inline thread replies. Use `repo_submit_change_proposal_review` only when the inventory lists it and the workflow explicitly needs to submit a review decision.
   - Treat every actionable reviewer comment, human or bot, as blocking until it has both a work change or justified pushback and a typed-tool response on the original PR/thread. Do not rely only on a new PR, commit message, or workpad note to close out human feedback.
   - Track each feedback item and resolution in the workpad, mirror the update, re-run validation after changes, push updates, and confirm the typed response was posted through the listed `responseAction.tool` or `responseTool`.
   - Repeat until `unresolvedFeedbackSummary.hasUnresolvedFeedback` is false, or every `actionableItems` entry has a completed or justified-response workpad entry plus a provider-side typed response.
2. Create or update the PR through the inventory `repo.create_or_update_change_proposal` typed tool when it is listed. Confirm the resulting PR with `repo.change_proposal_snapshot` when it is listed.
   - Use the inventory `tracker.attach_change_proposal` typed tool to attach the PR URL. TAPD currently exposes this to reviewers through the canonical workpad comment, while backend evidence comes from typed-tool results and KnownTarget registration.
   - Record the PR URL in the workpad for reviewer navigation.
3. Use `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" sync-base` when available to merge latest `origin/{{ repo.base_branch }}` into the branch, resolve conflicts, and rerun checks.
4. Update the persistent workpad with final checklist status and validation notes.
   - The final workpad refresh is reviewer-facing and freshness-gated. Backend review readiness is derived from typed-tool evidence, not Markdown checkbox parsing.

Handoff:

1. Before moving into the baseline handoff route `{{ issue.workflow.raw_state_by_route_key.review }}` when that route remains the resolved handoff target:
   - read the PR `Manual QA Plan` comment when present
   - run the full PR feedback sweep
   - confirm PR checks are green after the latest push using the inventory `repo.read_change_proposal_checks` typed tool when it is listed
   - read PR discussion after the latest push using the inventory `repo.read_change_proposal_discussion` typed tool when it is listed
   - confirm the final PR-diff whitespace check passed after the latest commit and push
   - confirm every required validation item is explicitly marked complete in the workpad comment
   - update the persistent workpad with final PR URL, latest commit SHA, validation summary, and intended handoff status
   - repeat until no outstanding comments remain and checks are fully passing
   - Preserve this final backend-evidence order: push branch, run final PR-diff validation, read PR checks, read PR discussion, update workpad and mirror, then move the Story.
2. Only then, when `{{ issue.workflow.raw_state_by_route_key.review }}` remains the resolved handoff route:
   - move the story to `{{ issue.workflow.raw_state_by_route_key.review }}`
   - stop after the state update succeeds; do not rely on another workpad update after `{{ issue.workflow.raw_state_by_route_key.review }}`, because the orchestrator may stop the active agent as soon as the Story leaves `active_states`
3. For stories that already had a PR attached at kickoff, resolve existing feedback, push required updates, refresh the workpad, then move to review only when that route remains the resolved handoff target.

Blocked handling:

1. Use blocked-access handling only for missing required tools, auth, or permissions that cannot be resolved in-session. Active repo-provider access is not a blocker by default: try the documented backup path first and record the result. Do not move to a non-dispatch handoff route such as `{{ issue.workflow.raw_state_by_route_key.review }}` until the blocker is recorded with what is missing, why it blocks acceptance or validation, and the exact human action needed to unblock. Post a standalone TAPD blocker comment only when the workpad cannot be created or updated.

Guardrails:

1. Before moving a Story into its next non-dispatch handoff route, confirm this bar:
   - kickoff, implementation, validation, and handoff checklist work is complete and reflected in the persistent workpad and local mirror
   - acceptance criteria and required ticket-provided validation items are complete
   - validation and tests are green for the latest commit
   - PR feedback sweep is complete and no actionable comments remain
   - PR checks are green, branch is pushed, and the PR URL is recorded in the workpad and mirror
   - the final handoff evidence order has been observed: branch push, final PR-diff validation, PR checks read, PR discussion read, fresh workpad and mirror update, then Story state move
   - if app-touching, runtime validation or media requirements are complete
2. Apply these guardrails:
   - do not reuse a branch or prior implementation state when its PR is already closed or merged
   - do not edit the Story body for planning or progress tracking unless the task explicitly requires it
   - never stage or commit `.symphony-tapd-workpad.md`
   - do not post standalone TAPD progress comments when the workpad can be updated in place
   - temporary proof edits are allowed only for local verification and must be reverted before commit
   - do not move into a non-dispatch handoff route until required validation, PR checks, PR discussion review, and fresh workpad handoff evidence are satisfied
   - when the current route is a non-dispatch wait route, do not make changes; wait and poll
   - if state is terminal, do nothing and shut down
   - keep the workpad concise, specific, reviewer-oriented, and Markdown-friendly for TAPD rendering
   - if blocked and no workpad exists yet, create one before posting a standalone blocker comment when possible
3. When you find meaningful out-of-scope work, do not expand the current Story. Create a same-workspace follow-up with `tracker.create_follow_up_issue`, link it with `tracker.add_issue_relation`, and record the follow-up id plus split reason in the workpad and mirror. If it is a future dependency, call `tracker.save_issue_dependency` after creation/linking; if TAPD rejects that write, record the intended dependency in the workpad instead of inventing hidden blocker state.

Use this lifecycle for TAPD workflows where backend change-proposal
reconciliation owns the transition from review to merge, and where `rework`
remains dispatchable for a fresh implementation attempt.

1. When the story is in `{{ issue.workflow.raw_state_by_route_key.review }}`, do not code or change the story body.
2. Poll for updates as needed, including active-provider PR review comments from humans and bots plus raw TAPD state changes.
3. If review feedback requires changes, move the story to `{{ issue.workflow.raw_state_by_route_key.rework }}` and follow the rework flow.
4. If approved and PR checks/mergeability are ready, backend change-proposal reconciliation moves the story to `{{ issue.workflow.raw_state_by_route_key.merging }}`. A human may also move it there manually when the local process requires a manual tracker transition.
5. When the story is in `{{ issue.workflow.raw_state_by_route_key.merging }}`, open workspace-root `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/skills/repo/land/SKILL.md` if it exists and follow its loop. Otherwise, merge the PR with the repository's normal repo-core/repo-provider flow after required approvals and checks pass.
6. After merge is complete:
   - update the same workpad comment with merge or closure state
   - move the story to `{{ issue.workflow.raw_state_by_route_key.resolved }}` or another configured terminal success state
   - stop after the state update succeeds; do not assume another workpad update will be possible after the Story leaves `active_states`
   - post a short standalone closure comment only when the workpad comment cannot be updated and human traceability still requires a distinct audit event
7. When `rework` is dispatchable, treat `{{ issue.workflow.raw_state_by_route_key.rework }}` as a full approach reset, not incremental patching.
8. Re-read the full story body and all human comments; explicitly identify what will be done differently this attempt.
9. Close the existing PR tied to the story.
10. Keep one active workpad comment. Reset it for the new attempt instead of creating a parallel active workpad comment.
11. Prefer `"${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo" create-working-branch "<unique-story-attempt-id>" --base "origin/{{ repo.base_branch }}"`.
12. Rewrite `.symphony-tapd-workpad.md` from the reset workpad comment.
13. Re-fetch the Story snapshot, upsert the canonical workpad, sync the local mirror, sync the base branch, and continue as a fresh implementation attempt.
14. If your raw rework state is not also the active coding state in that workspace, move the story back to `{{ issue.workflow.raw_state_by_route_key.developing }}` before active implementation resumes.

---
name: land
description:
  Land a PR by monitoring conflicts, resolving them, waiting for checks, and
  squash-merging when green; use when asked to land, merge, or shepherd a PR to
  completion.
---

# Land

## Goals

- Ensure the PR is conflict-free with its target/base branch.
- Keep CI green and fix failures when they occur.
- Squash-merge the PR once checks pass.
- Do not yield to the user until the PR is merged; keep the watcher loop running
  unless blocked.
- Delete the remote branch only when repo policy expects it; some repos
  auto-delete head branches after merge.

## Preconditions

- Prefer the bundled repo helper for provider-neutral repo facts such as
  preflight, current branch, head SHA, base branch, generated working branch
  names, remote URL, and status when it exists.
- When a generated Typed Workflow Tool Inventory is present and lists
  repo-provider feedback tools, use those exact typed tools for routine
  discussion reads, top-level PR comments, and inline review-comment replies.
- Prefer the bundled repo-provider helper when it exists. It currently supports
  both GitHub and CNB, and is the fallback or diagnostics surface for
  provider-backed operations not covered by the typed-tool inventory.
- Do not guess the active repo provider. Use the workflow/runtime provider
  configuration or the repo-provider helper's reported current kind; if neither
  is available for a provider-specific action, stop and surface the missing
  provider context.
- For GitHub mode, `gh` CLI is authenticated.
- For CNB mode, `CNB_TOKEN` is available for provider-backed PR, review, and
  merge operations.
- Do not bypass the helper with raw provider-specific CLIs when the helper is
  available.
- You are on the PR branch with a clean working tree.

## Steps

1. Locate the PR for the current branch. Use the bundled repo helper for
   repo-core covered branch/status facts.
2. Confirm the full gauntlet is green locally before any push.
3. If the working tree has uncommitted changes, commit with the `commit` skill
   and push with the `push` skill before proceeding.
4. Check mergeability and conflicts against the current target/base branch.
5. If conflicts exist, use the `pull` skill to fetch/merge the latest remote
   base branch and resolve conflicts, then use the `push` skill to publish the
   updated branch.
6. Ensure agent review comments (if present) are acknowledged and any required
   fixes are handled before merging.
7. Watch checks until complete.
8. If checks fail, pull logs, fix the issue, commit with the `commit` skill,
   push with the `push` skill, and re-run checks.
9. When all checks are green and review feedback is addressed, squash-merge
   using the PR title/body for the merge subject/body. Delete the branch only
   when repo policy expects it.
10. **Context guard:** Before implementing review feedback, confirm it does not
    conflict with the user’s stated intent or task context. If it conflicts,
    respond inline with a justification and ask the user before changing code.
11. **Pushback template:** When disagreeing, reply inline with: acknowledge +
    rationale + offer alternative.
12. **Ambiguity gate:** When ambiguity blocks progress, use the clarification
    flow supported by the active repo provider (assign or mention a reviewer
    when available, then wait for response). Do not implement until ambiguity is
    resolved.
    - If you are confident you know better than the reviewer, you may proceed
      without asking the user, but reply inline with your rationale.
13. **Per-comment mode:** For each review comment, choose one of: accept,
    clarify, or push back. Reply inline (or in the issue thread for agent
    reviews) stating the mode before changing code.
14. **Reply before change:** Always respond with intended action before pushing
    code changes (inline for review comments, issue thread for agent reviews).

## Commands

```
# Resolve the bundled helpers from the runtime automation directory.
automation_dir="${SYMPHONY_WORKSPACE_AUTOMATION_DIR:?SYMPHONY_WORKSPACE_AUTOMATION_DIR is required}"
repo_cmd="$automation_dir/bin/repo"
provider_cmd="$automation_dir/bin/repo-provider"

# Ensure branch and PR context
branch=$("$repo_cmd" current-branch)
pr_number=$("$provider_cmd" pr-view --json number -q .number)
pr_title=$("$provider_cmd" pr-view --json title -q .title)
pr_body=$("$provider_cmd" pr-view --json body -q .body)

# Check mergeability and conflicts
mergeable=$("$provider_cmd" pr-view --json mergeable -q .mergeable)

if [ "$mergeable" = "CONFLICTING" ]; then
  # Run the `pull` skill to handle fetch + merge + conflict resolution.
  # Then run the `push` skill to publish the updated branch.
fi

# Use the provider-neutral land-watch command to monitor checks, review
# comments, agent review signals, merge conflicts, and PR head updates.

# Watch checks, review comments, and PR head updates
if ! "$provider_cmd" pr-land-watch "$pr_number"; then
  # Identify failing run and inspect logs
  "$provider_cmd" pr-checks
  # "$provider_cmd" run-list --branch "$branch"
  # "$provider_cmd" run-view <run-id> --log
  exit 1
fi

# Squash-merge. Delete the branch separately only if repo policy expects it.
"$provider_cmd" pr-merge --squash --subject "$pr_title" --body "$pr_body"
# Optional policy-dependent cleanup:
# "$repo_cmd" delete-remote-branch "$branch"
```

## Land Watch Helper

Use the repo-provider land watcher to monitor review comments, CI, merge
conflicts, and PR head updates. It exits cleanly after checks pass when no
repo-specific agent review signal is present:

```
"$provider_cmd" pr-land-watch "$pr_number"
```

Exit codes:

- 2: Review comments detected (address feedback)
- 3: CI checks failed
- 4: PR head updated (autofix commit detected)
- 5: PR has merge conflicts

## Failure Handling

- If checks fail, pull details with `"$provider_cmd" pr-checks` and `"$provider_cmd" run-view --log`, then
  fix locally, commit with the `commit` skill, push with the `push` skill, and
  re-run the watch.
- In CNB mode, `run-list` returns CNB build ids (`sn`), and
  `run-view <sn> --log` streams per-stage logs via CNB build APIs.
- Use judgment to identify flaky failures. If a failure is a flake (e.g., a
  timeout on only one platform), you may proceed without fixing it.
- If CI pushes an auto-fix commit (for example, authored by GitHub Actions), it
  may not trigger a fresh CI run. Detect the updated PR head, pull locally,
  merge the latest remote base branch if needed, add a real author commit, and
  force-push to retrigger CI, then restart the checks loop.
- If all jobs fail with corrupted pnpm lockfile errors on the merge commit, the
  remediation is to fetch the latest remote base branch, merge, force-push, and
  rerun CI.
- If mergeability is `UNKNOWN`, wait and re-check.
- Do not merge while review comments (human or agent review) are outstanding.
- In repos that surface agent reviews as issue comments, use the presence of
  a stable provider review heading (not job status alone) as the signal
  that feedback is available.
- Do not enable auto-merge unless the repo's required-check policy makes it
  safe; in repos without required checks, auto-merge can skip validation.
- If the remote PR branch advanced due to your own prior force-push or merge,
  avoid redundant merges; re-run the formatter locally if needed and
  `"$repo_cmd" push "$branch" --force-with-lease`.

## Review Handling

- Some repos surface agent reviews as issue comments posted by automation. When
  that convention is in use, those comments
  include a stable provider review heading and the reviewer's
  methodology and guardrails. Treat them as feedback that must be acknowledged
  before merge.
- Human review comments are blocking and must be addressed (responded to and
  resolved) before requesting a new review or merging.
- If multiple reviewers comment in the same thread, respond to each comment
  (batching is fine) before closing the thread.
- Prefer `repo.read_change_proposal_discussion` from the generated typed-tool
  inventory for routine discussion reads when it is listed.
- Prefer `repo.add_change_proposal_comment` for routine top-level PR comments
  and `repo.reply_change_proposal_review_comment` for inline review replies
  when those typed tools are listed.
- Fetch top-level PR issue comments via `"$provider_cmd" pr-issue-comments` and post follow-up issue-thread replies with `"$provider_cmd" pr-add-issue-comment` only as fallback or diagnostics.
- Fetch review summaries/states via `"$provider_cmd" pr-reviews`.
- Fetch inline review comments via `"$provider_cmd" pr-review-comments` and reply with `"$provider_cmd" pr-reply-review-comment` only as fallback or diagnostics.
- Use review comment endpoints (not issue comments) to find inline feedback:
  - List PR reviews:
    ```
    "$provider_cmd" pr-reviews <pr_number>
    ```
  - List PR review comments:
    ```
    "$provider_cmd" pr-review-comments <pr_number>
    ```
  - PR issue comments (top-level discussion):
    ```
    "$provider_cmd" pr-issue-comments <pr_number>
    ```
  - Reply to a specific review comment:
    ```
    "$provider_cmd" pr-reply-review-comment <comment_id> <pr_number> --body '[agent] <response>'
    ```
- `<comment_id>` must be the numeric review comment id (e.g., `2710521800`), not
  the GraphQL node id (e.g., `PRRC_...`).
- All provider-backed PR comments generated by this agent must be prefixed with
  `[agent]`.
- For repos that use agent review issue comments, reply in the issue thread
  (not a review thread) with `[agent]` and state whether you will address the
  feedback now or defer it (include rationale).
  - Post that acknowledgement with:
    ```
    "$provider_cmd" pr-add-issue-comment <pr_number> --body '[agent] <response>'
    ```
- If feedback requires changes:
  - For inline review comments (human), reply with intended fixes
    (`[agent] ...`) **as an inline reply to the original review comment** using
    `pr-reply-review-comment` (do not use issue comments for this).
  - Implement fixes, commit, push.
  - Reply with the fix details and commit sha (`[agent] ...`) in the same place
    you acknowledged the feedback (issue comment for agent reviews, inline reply
    for review comments).
- In repos that use agent review issue comments, the land watcher treats those
  comments as unresolved until a newer `[agent]` issue comment is posted
  acknowledging the findings.
- Only request a new agent review when you need a rerun (e.g., after new
  commits). Do not request one without changes since the last review.
  - Before requesting a new agent review, re-run the land watcher and ensure
    there are zero outstanding review comments (all have `[agent]` inline
    replies).
  - After pushing new commits, the configured agent review workflow will rerun on PR
    synchronization (or you can re-run the workflow manually). Post a concise
    root-level summary comment so reviewers have the latest delta:
    ```
    "$provider_cmd" pr-add-issue-comment <pr_number> --body "$(cat <<'EOF'
    [agent] Changes since last review:
    - <short bullets of deltas>
    Commits: <sha>, <sha>
    Tests: <commands run>
    EOF
    )"
    ```
  - Only request a new review if there is at least one new commit since the
    previous request.
  - Wait for the next agent review comment before merging.

## Scope + PR Metadata

- The PR title and description should reflect the full scope of the change, not
  just the most recent fix.
- If review feedback expands scope, decide whether to include it now or defer
  it. You can accept, defer, or decline feedback. If deferring or declining,
  call it out in the root-level `[agent]` update with a brief reason (e.g.,
  out-of-scope, conflicts with intent, unnecessary).
- Correctness issues raised in review comments should be addressed. If you plan
  to defer or decline a correctness concern, validate first and explain why the
  concern does not apply.
- Classify each review comment as one of: correctness, design, style,
  clarification, scope.
- For correctness feedback, provide concrete validation (test, log, or
  reasoning) before closing it.
- When accepting feedback, include a one-line rationale in the root-level
  update.
- When declining feedback, offer a brief alternative or follow-up trigger.
- Prefer a single consolidated "review addressed" root-level comment after a
  batch of fixes instead of many small updates.
- For doc feedback, confirm the doc change matches behavior (no doc-only edits
  to appease review).

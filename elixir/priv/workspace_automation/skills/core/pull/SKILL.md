---
name: pull
description:
  Pull the latest remote base branch into the current local branch and resolve
  merge conflicts (aka update-branch). Use when the agent needs to sync a feature
  branch with origin, perform a merge-based update (not rebase), and guide
  conflict resolution best practices.
---

# Pull

## Workflow

1. Resolve the bundled repo helper from the runtime automation directory and
   verify repo status is clean before merging:
   - `automation_dir="${SYMPHONY_WORKSPACE_AUTOMATION_DIR:?SYMPHONY_WORKSPACE_AUTOMATION_DIR is required}"; repo_cmd="$automation_dir/bin/repo"`
   - `"$repo_cmd" status`
2. Ensure rerere is enabled locally:
   - `"$repo_cmd" enable-rerere`
3. Confirm remotes and branches:
   - Ensure the `origin` remote exists.
   - Ensure the current branch is the one to receive the merge through the
     bundled repo helper.
   - Determine the repo's base branch before merging. Prefer the workflow or PR
     target when it is explicit; otherwise use the remote default
     branch (for example `origin/HEAD`).
4. Fetch latest refs:
   - `"$repo_cmd" fetch`
5. Sync the remote feature branch first:
   - `branch=$("$repo_cmd" current-branch)`
   - `"$repo_cmd" merge "origin/$branch" --ff-only`
   - This pulls branch updates made remotely (for example, a repo-provider auto-commit)
     before merging the latest remote base branch.
6. Merge in order:
   - Prefer `"$repo_cmd" sync-base --base "<base-branch>"` so repo-core owns
     the fetch and base-merge side effects together.
7. If conflicts appear, resolve them (see conflict guidance below), then:
   - stage the resolved files
   - continue or commit the merge according to the repository's normal merge
     workflow
8. Verify with the target repository's documented checks when present.
9. Summarize the merge:
   - Call out the most challenging conflicts/files and how they were resolved.
   - Note any assumptions or follow-ups.

## Conflict Resolution Guidance (Best Practices)

- Inspect context before editing:
  - Use `"$repo_cmd" status` to list conflicted files.
  - Use `"$repo_cmd" diff` or `"$repo_cmd" diff --merge` to see conflict
    hunks.
  - Use `"$repo_cmd" diff :1:path/to/file :2:path/to/file` and
    `"$repo_cmd" diff :1:path/to/file :3:path/to/file` to compare base vs
    ours/theirs for a file-level view of intent.
  - With `merge.conflictstyle=zdiff3`, conflict markers include:
    - `<<<<<<<` ours, `|||||||` base, `=======` split, `>>>>>>>` theirs.
    - Matching lines near the start/end are trimmed out of the conflict region,
      so focus on the differing core.
  - Summarize the intent of both changes, decide the semantically correct
    outcome, then edit:
    - State what each side is trying to achieve (bug fix, refactor, rename,
      behavior change).
    - Identify the shared goal, if any, and whether one side supersedes the
      other.
    - Decide the final behavior first; only then craft the code to match that
      decision.
    - Prefer preserving invariants, API contracts, and user-visible behavior
      unless the conflict clearly indicates a deliberate change.
  - Open files and understand intent on both sides before choosing a resolution.
- Prefer minimal, intention-preserving edits:
  - Keep behavior consistent with the branch’s purpose.
  - Avoid accidental deletions or silent behavior changes.
- Resolve one file at a time and rerun tests after each logical batch.
- Use `ours/theirs` only when you are certain one side should win entirely.
- For complex conflicts, search for related files or definitions to align with
  the rest of the codebase.
- For generated files, resolve non-generated conflicts first, then regenerate:
  - Prefer resolving source files and handwritten logic before touching
    generated artifacts.
  - Run the CLI/tooling command that produced the generated file to recreate it
    cleanly, then stage the regenerated output.
- For import conflicts where intent is unclear, accept both sides first:
  - Keep all candidate imports temporarily, finish the merge, then run lint/type
    checks to remove unused or incorrect imports safely.
- After resolving, ensure no conflict markers remain:
  - `"$repo_cmd" diff-check`
- When unsure, note assumptions and ask for confirmation before finalizing the
  merge.

## When To Ask The User (Keep To A Minimum)

Do not ask for input unless there is no safe, reversible alternative. Prefer
making a best-effort decision, documenting the rationale, and proceeding.

Ask the user only when:

- The correct resolution depends on product intent or behavior not inferable
  from code, tests, or nearby documentation.
- The conflict crosses a user-visible contract, API surface, or migration where
  choosing incorrectly could break external consumers.
- A conflict requires selecting between two mutually exclusive designs with
  equivalent technical merit and no clear local signal.
- The merge introduces data loss, schema changes, or irreversible side effects
  without an obvious safe default.
- The branch is not the intended target, or the remote/branch names do not exist
  and cannot be determined locally.

Otherwise, proceed with the merge, explain the decision briefly in notes, and
leave a clear, reviewable commit history.

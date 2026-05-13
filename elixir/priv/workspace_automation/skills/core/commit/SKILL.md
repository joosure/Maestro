---
name: commit
description:
  Create a well-formed repository commit from current changes using session
  history for rationale and summary; use when asked to commit, prepare a commit
  message, or finalize staged work.
---

# Commit

## Goals

- Produce a commit that reflects the actual code changes and the session
  context.
- Follow common git conventions (type prefix, short subject, wrapped body).
- Include both summary and rationale in the body.

## Inputs

- Agent session history for intent and rationale.
- Bundled repo helper outputs for status and diffs when available.
- Repo-specific commit conventions if documented.

## Steps

1. Read session history to identify scope, intent, and rationale.
2. Resolve the bundled repo helper from the runtime automation directory:
   - `automation_dir="${SYMPHONY_WORKSPACE_AUTOMATION_DIR:?SYMPHONY_WORKSPACE_AUTOMATION_DIR is required}"; repo_cmd="$automation_dir/bin/repo"`
3. Inspect the working tree and staged changes with repo-core:
   - `"$repo_cmd" status`
   - `"$repo_cmd" diff`
   - `"$repo_cmd" diff --staged`
4. Stage intended changes, including new files, with `"$repo_cmd" stage-all`
   after confirming scope.
5. Sanity-check newly added files; if anything looks random or likely ignored
   (build artifacts, logs, temp files), flag it to the user before committing.
6. If staging is incomplete or includes unrelated files, fix the index or ask
   for confirmation.
7. Choose a conventional type and optional scope that match the change (e.g.,
   `feat(scope): ...`, `fix(scope): ...`, `refactor(scope): ...`).
8. Write a subject line in imperative mood, <= 72 characters, no trailing
   period.
9. Write a body that includes:
   - Summary of key changes (what changed).
   - Rationale and trade-offs (why it changed).
   - Tests or validation run (or explicit note if not run).
10. Append a provider-specific `Co-authored-by` trailer only when the active
    agent/provider policy requires one or the user requests it.
11. Wrap body lines at 72 characters.
12. Create the commit with `"$repo_cmd" commit-staged --message "$message"`
    when the repo helper is available; otherwise use the local VCS path
    required by the environment.
13. Commit only when the message matches the staged changes: if the staged diff
    includes unrelated files or the message describes work that isn't staged,
    fix the index or revise the message before committing.

## Output

- A single repository commit whose message reflects the session.

## Template

Type and scope are examples only; adjust to fit the repo and changes.

```
<type>(<scope>): <short summary>

Summary:
- <what changed>
- <what changed>

Rationale:
- <why>
- <why>

Tests:
- <command or "not run (reason)">

Co-authored-by: <agent name> <<agent email>>
```

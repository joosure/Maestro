- Each active issue has at most one persistent workpad.
- The workpad stable identity is the typed-tool returned `workpad.id` / `workpad_id`.
- Agents must read workpad identity through `tracker.issue_snapshot`.
- Agents must update workpad only through `tracker.upsert_workpad`.
- Agents must not identify workpads by title, Markdown shape, comment body, or provider UI text.
- The workpad is the human-readable execution log; backend readiness is based on structured typed-tool evidence, not Markdown parsing.
- TAPD stores the workpad as a TAPD Story comment.
- Symphony renders TAPD comment writes as HTML rich text and normalizes TAPD comment reads back to Markdown so the TAPD UI stays readable.
- Keep workspace-root `.symphony-tapd-workpad.md` as a local mirror/cache for retry recovery; when your shell is inside `repo/`, address it as `../.symphony-tapd-workpad.md`.
- Never create, stage, or commit `repo/.symphony-tapd-workpad.md`. If a repo-local copy appears, move any needed content into the workspace-root mirror, delete the repo-local copy, and continue.
- The TAPD adapter creates and registers the canonical workpad when `workpad_id` is unavailable.

Use this recommended human-readable structure for the persistent workpad comment
and mirror the same content into `.symphony-tapd-workpad.md` throughout execution.
Backend readiness does not depend on these headings or checkbox text:

````md
## Workpad

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

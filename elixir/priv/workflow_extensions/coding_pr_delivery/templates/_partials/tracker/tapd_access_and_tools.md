Use exact runtime tool names from the generated inventory. If a required typed
tool is missing, stop as blocked and record the blocker in the workpad when
workpad tooling is available.

{{ runtime.tool_inventory }}

For TAPD tracker actions, follow the bundled workspace skill:
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

- Work only in `repo/` for source changes, builds, tests, and normal repo operations.
- Workspace-root automation belongs to Symphony. The only normal workspace-root artifact you update is `.symphony-tapd-workpad.md`.
- Do not copy, move, or merge `repo/.codex`, `repo/.agents`, or repo-local automation config into the workspace root.
- Prefer `${SYMPHONY_WORKSPACE_AUTOMATION_DIR}/bin/repo` only as explicitly documented helper path for repo-core facts and Git side effects not covered by the generated inventory.
- Use inventory-listed repo-provider typed tools for routine PR view/create/update/discussion/check/merge/close actions. Use `bin/repo-provider` only as explicitly documented helper path for operations not covered by the inventory.

Only use inventory-listed typed TAPD tools for Story reads and writes, state
transitions, workpad/comment updates, external reference links, relations,
dependencies, and provider health checks. Use `tracker.provider_diagnostics`
for fixed provider health checks when it is listed. If a required TAPD
capability is missing, stop as blocked and record the missing typed capability
in the workpad; do not improvise with direct TAPD REST calls or shell scripts.

- Determine the raw TAPD status first, then follow the resolved route policy.
- Open or create the workpad through typed tracker tools before new implementation work, then keep the local mirror synchronized.
- Reproduce or otherwise confirm the issue signal before changing code.
- Treat ticket-authored `Validation`, `Test Plan`, or `Testing` content as required acceptance input.
- Create and link a follow-up TAPD Story for meaningful out-of-scope work instead of expanding the current Story.
- Move status only when the matching quality bar is met.
- Operate autonomously unless blocked by missing requirements, secrets, permissions, or required tools.

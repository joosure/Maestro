---
name: tapd
description: |
  Use Symphony's generated typed TAPD tools for tracker workflow actions.
  Provides TAPD capability semantics and workpad rules.
---

# TAPD Tracker Tools

Use this skill with the generated Typed Workflow Tool Inventory in the prompt.
The inventory is authoritative for exact runtime tool names available in the
current session.

This skill owns TAPD tracker semantics: which typed capability to use, the
stable TAPD workpad identity, and the argument shape for routine Story actions.
Workflow templates own when those actions are allowed, route-policy handling,
repo-provider behavior, and completion bars.

## Typed Tool Rule

Do not infer TAPD REST paths, raw parameter shapes, workspace IDs, comment HTML
encoding, or raw status mutation syntax from memory. TAPD provider details are
owned by Symphony typed tools.

For each TAPD tracker action, call the exact runtime tool name from the
generated inventory for the matching semantic capability:

- `tracker.issue_snapshot`: read the Story, raw status, workflow route states,
  labels, comments, and the adapter-resolved active workpad reference.
- `tracker.move_issue`: move a Story to a workflow route, lifecycle phase, or
  raw status from the typed snapshot. The tool owns TAPD status update syntax.
- `tracker.upsert_workpad`: create or update the single active workflow workpad.
  Use the `workpad_id` returned by `tracker.issue_snapshot` when it is present.
  If no `workpad_id` exists yet, omit it and let the typed tool create and
  register the canonical workpad. The tool owns the provider comment mapping,
  canonical Markdown rendering, and Markdown-to-TAPD rich text conversion.
- `tracker.attach_change_proposal`: attach a PR/MR/change proposal URL to the
  Story. TAPD currently stores this through the canonical workpad comment.
- `tracker.upsert_comment`: create a general Story comment or update a specific
  existing comment by `comment_id`.
- `tracker.create_follow_up_issue`: create a constrained follow-up Story in the
  same TAPD workspace.
- `tracker.read_issue_relations`: read direct Story relations.
- `tracker.add_issue_relation`: link two Stories through TAPD direct relations.
- `tracker.read_issue_dependencies`: read time-relative dependencies and
  normalized incoming blockers.
- `tracker.save_issue_dependency`: save one dependency relation using semantic
  Story ids.
- `tracker.provider_diagnostics`: run fixed read-only TAPD provider diagnostics
  when explicitly exposed for operator or troubleshooting workflows.

If the inventory does not list the required typed capability, treat that as a
workflow blocker unless the prompt explicitly supplies a different typed tool.
Do not construct TAPD REST requests or token-bearing shell helpers for workflow
actions.

## Common Calls

Use `workpad_id` as the workpad identity. The stored workpad body is human
readable content only; do not use headings, sections, checkbox text, or comment
body shape to find or update a workpad.

Read current Story context:

```json
{
  "issue_id": "{{ issue.id }}",
  "include_comments": true,
  "include_attachments": true,
  "comment_limit": 50
}
```

Move a Story to the workflow review route:

```json
{
  "issue_id": "{{ issue.id }}",
  "state_name": "review",
  "expected_current_state": "in_progress",
  "reason": "implementation is ready for review"
}
```

Upsert the workflow workpad:

```json
{
  "issue_id": "{{ issue.id }}",
  "workpad_id": "tapd:issue:{{ issue.id }}:workpad",
  "body": "### Plan\n\n- [x] ...\n\n### Validation\n\n- ..."
}
```

When `workpad_id` is omitted, the upsert tool creates and registers the
canonical workpad for the Story.

Create a general comment:

```json
{
  "issue_id": "{{ issue.id }}",
  "body": "Validation completed."
}
```

Update a specific comment:

```json
{
  "comment_id": "comment-id",
  "body": "Updated comment body."
}
```

Attach a change proposal:

```json
{
  "issue_id": "{{ issue.id }}",
  "url": "https://provider.example/org/repo/change-proposals/123",
  "title": "TAPD implementation"
}
```

Create and link a follow-up Story:

```json
{
  "source_issue_id": "{{ issue.id }}",
  "title": "Follow-up: scoped improvement",
  "description": "Problem statement...\n\nAcceptance Criteria\n- ..."
}
```

```json
{
  "source_issue_id": "{{ issue.id }}",
  "target_issue_id": "TAPD-1153000000000000010"
}
```

Read and save dependency facts:

```json
{
  "issue_id": "{{ issue.id }}"
}
```

```json
{
  "blocking_issue_id": "TAPD-1153000000000000002",
  "blocked_issue_id": "{{ issue.id }}",
  "current_user": "symphony"
}
```

## Usage Rules

- Use typed tools for all routine TAPD Story reads and writes.
- Use `tracker.issue_snapshot` before state transitions so route keys, raw TAPD
  states, and lifecycle phases come from the current Story workflow.
- Prefer route keys such as `review`, `developing`, or `rework` for
  `tracker.move_issue` when available in the typed snapshot.
- Use `tracker.upsert_workpad` only for the canonical workflow workpad.
- Follow the active workflow template for when state transitions, follow-up
  Stories, dependency writes, and provider handoffs are allowed.
- Use `tracker.upsert_comment` for non-workpad comments.
- Use `tracker.create_follow_up_issue` and `tracker.add_issue_relation` when
  splitting out related work instead of constructing TAPD Story REST calls.
- Use `tracker.read_issue_dependencies` and `tracker.save_issue_dependency`
  when the workflow explicitly needs dependency/blocker relation facts.
- Use `tracker.attach_change_proposal` for PR/MR/change proposal links; TAPD
  stores the link in the canonical workpad comment until a structured TAPD
  attachment API is available.
- Do not introduce token-bearing shell helpers or direct TAPD REST calls.

## TAPD Access Boundary

Only use inventory-listed typed TAPD tools for Story reads and writes, state
transitions, workpad/comment updates, change proposal links, relations,
dependencies, and provider health checks.

Use `tracker.provider_diagnostics` for fixed provider health checks when the
inventory exposes that capability. For migration or metadata needs not covered
by typed tools, stop as blocked and request a new typed capability instead of
calling TAPD REST directly.

Do not ask for or invent a raw TAPD fallback. Routine TAPD gaps require a new
typed capability; troubleshooting gaps require a fixed diagnostics typed tool
that does not accept arbitrary REST paths or payloads.

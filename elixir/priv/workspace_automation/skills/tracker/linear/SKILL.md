---
name: linear
description: |
  Use Symphony's generated typed Linear tools for tracker workflow actions.
  Provides Linear capability semantics and workpad rules.
---

# Linear Tracker Tools

Use this skill with the generated Typed Workflow Tool Inventory in the prompt.
The inventory is authoritative for exact runtime tool names available in the
current session.

This skill owns Linear tracker semantics: which typed capability to use, the
stable Linear workpad identity, upload preparation rules, and the argument shape
for routine issue actions. Workflow templates own when those actions are
allowed, route-policy handling, repo-provider behavior, and completion bars.

## Typed Tool Rule

Do not infer Linear provider fields, mutation names, or comment field names from
memory. Linear provider schema details are owned by Symphony typed tools.

For each Linear action, call the exact runtime tool name from the generated
inventory for the matching semantic capability:

- `tracker.issue_snapshot`: read issue state, comments, attachments, labels,
  branch name, team states, and the adapter-resolved active workpad reference.
- `tracker.move_issue`: move an issue to a named state. Pass the destination
  state name from a typed issue snapshot; the tool resolves `stateId`.
- `tracker.upsert_workpad`: create or update the single active workflow workpad.
  Use the `workpad_id` returned by `tracker.issue_snapshot` when it is present.
  If no `workpad_id` exists yet, omit it and let the typed tool create and
  register the canonical workpad. The tool owns the provider comment mapping and
  canonical Markdown rendering.
- `tracker.attach_change_proposal`: attach a PR, MR, or other change proposal
  URL to the issue.
- `tracker.upsert_comment`: create a general issue comment or update a specific
  existing comment by `comment_id`.
- `tracker.prepare_file_upload`: prepare a signed Linear file upload and return
  `uploadUrl`, `assetUrl`, and required upload headers.
- `tracker.provider_diagnostics`: run the fixed read-only Linear provider
  diagnostics query.

If the inventory does not list the required typed capability, treat that as a
workflow blocker unless the prompt explicitly supplies a different typed tool.
Do not use any non-inventory Linear access path for workflow actions.

## Common Calls

Use `workpad_id` as the workpad identity. The stored workpad body is human
readable content only; do not use headings, sections, checkbox text, or comment
body shape to find or update a workpad.

Read current issue context:

```json
{
  "issue_id": "{{ issue.id }}",
  "include_comments": true,
  "include_attachments": true,
  "comment_limit": 50
}
```

Move an issue:

```json
{
  "issue_id": "{{ issue.id }}",
  "state_name": "In Review",
  "expected_current_state": "In Progress",
  "reason": "implementation is ready for review"
}
```

Upsert the workflow workpad:

```json
{
  "issue_id": "{{ issue.id }}",
  "workpad_id": "linear:issue:{{ issue.id }}:workpad",
  "body": "### Plan\n\n- [x] ...\n\n### Validation\n\n- ..."
}
```

When `workpad_id` is omitted, the upsert tool creates and registers the
canonical workpad for the issue.

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

Attach uploaded asset URLs to a comment body:

```json
{
  "issue_id": "{{ issue.id }}",
  "body": "Uploaded validation artifact.",
  "asset_urls": ["https://uploads.linear.app/asset/example.mp4"]
}
```

Prepare a file upload:

```json
{
  "filename": "validation.mp4",
  "content_type": "video/mp4",
  "size": 123456,
  "make_public": true
}
```

After `tracker.prepare_file_upload` returns `uploadUrl`, upload the file bytes
to that signed URL with the exact returned headers. Then call
`tracker.upsert_comment` with the returned `assetUrl` in `asset_urls`.

Attach a change proposal:

```json
{
  "issue_id": "{{ issue.id }}",
  "url": "https://provider.example/org/repo/change-proposals/123",
  "title": "DEMO-123 implementation"
}
```

## Usage Rules

- Use typed tools for all Linear reads and writes.
- Use `tracker.issue_snapshot` before state transitions so you can choose an
  existing team state name.
- Use `tracker.upsert_workpad` only for the canonical workflow workpad.
- Follow the active workflow template for when state transitions, follow-up
  issues, provider handoffs, and completion state changes are allowed.
- Use `tracker.upsert_comment` for non-workpad comments.
- Use `tracker.prepare_file_upload` only to prepare signed upload URLs; those
  upload URLs already carry the required authorization.
- Do not use any non-inventory Linear access path.

## Linear Access Boundary

Only use inventory-listed typed Linear tools for issue reads and writes, state
transitions, workpad/comment updates, change proposal links, file upload
preparation, and provider health checks.

Use `tracker.provider_diagnostics` for fixed provider health checks when the
inventory exposes that capability. For migration or metadata needs not covered
by typed tools, stop as blocked and request a new typed capability instead of
using a non-inventory Linear access path.

Do not ask for or invent a raw Linear fallback. Routine Linear gaps require a
new typed capability; troubleshooting gaps require a fixed diagnostics typed
tool that does not accept arbitrary GraphQL.

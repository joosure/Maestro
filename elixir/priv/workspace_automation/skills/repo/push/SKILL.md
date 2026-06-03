---
name: push
description:
  Push current branch changes to origin and create or update the corresponding
  pull request; use when asked to push, publish updates, or create pull request.
---

# Push

## Prerequisites

- Prefer the bundled repo helper for provider-neutral repo facts such as
  preflight, current branch, head SHA, published head SHA, base branch,
  generated working branch names, remote URL, and status when it exists.
- When a generated Typed Workflow Tool Inventory is present and lists
  repo-provider change-proposal tools, use those exact typed tools for routine
  PR create/update operations.
- Prefer the bundled repo-provider helper when it exists. It currently supports
  both GitHub and CNB, and is the fallback or diagnostics surface for
  provider-backed operations not covered by the typed-tool inventory.
- Do not guess the active repo provider. Use the workflow/runtime provider
  configuration or the repo-provider helper's reported current kind; if neither
  is available for a provider-specific action, stop and surface the missing
  provider context.
- For GitHub mode, `gh` CLI is installed and available in `PATH`.
- For GitHub mode, `gh auth status` succeeds for GitHub operations in the
  target repo.
- For CNB mode, `CNB_TOKEN` is available for provider-backed PR operations.
- For CNB mode, the configured `origin` remote must already use CNB HTTPS
  transport. Push auth is still Git-level auth and should use username
  `cnb` plus the token through the existing credential flow or remote config.
- Do not bypass the helper with raw provider-specific CLIs when the helper is
  available, except for the GitHub-only workflow-level label convention when
  `repo.provider.options.required_pr_label` is explicitly configured.

## Goals

- Push current branch changes to `origin` safely.
- Create a PR if none exists for the branch, otherwise update the existing PR.
- Keep branch history clean when remote has moved.

## Related Skills

- `pull`: use this when push is rejected or sync is not clean (non-fast-forward,
  merge conflict risk, or stale branch).

## Steps

1. Identify current branch and confirm remote state through the bundled repo
   helper for repo-core covered facts.
2. Run the repo-defined validation gate from the current repo root before
   pushing.
3. Push branch to `origin` with upstream tracking if needed, using whatever
   remote URL is already configured, then verify the published head matches the
   local head.
4. If push is not clean/rejected:
   - If the failure is a non-fast-forward or sync problem, run the `pull`
     skill to merge the repo's current base branch, resolve conflicts, and
     rerun validation.
   - Push again; use `--force-with-lease` only when history was rewritten.
   - If the failure is due to auth, permissions, or workflow restrictions on
     the configured remote, stop and surface the exact error instead of
     rewriting remotes or switching protocols as a workaround.

5. Ensure a PR exists for the branch:
   - If no PR exists, create one.
   - If a PR exists and is open, update it.
   - If branch is tied to a closed/merged PR, create a new branch with the repo
     helper when available, then create a replacement PR.
   - Write a proper PR title that clearly describes the change outcome
   - For branch updates, explicitly reconsider whether current PR title still
     matches the latest scope; update it if it no longer does.
6. If `repo.provider.options.required_pr_label` is configured:
   - Treat it as a GitHub-only workflow convention surfaced through the
     repo-provider helper.
   - Verify the PR has that label. Prefer
     `"$provider_cmd" pr-add-label "<label>"` after the PR exists.
   - Pass an explicit PR selector only when you are not on the PR branch.
7. When the target repo provides `.github/pull_request_template.md`, write/update
   the PR body explicitly from that template:
   - Fill every section with concrete content for this change.
   - Replace all placeholder comments (`<!-- ... -->`).
   - Keep bullets/checkboxes where template expects them.
   - If PR already exists, refresh body content so it reflects the total PR
     scope (all intended work on the branch), not just the newest commits,
     including newly added work, removed work, or changed approach.
   - Do not reuse stale description text from earlier iterations.
8. If the target repo ships a local PR-body validator, run it and fix all
   reported issues before handing off.
9. Reply with the PR URL from the bundled repo-provider helper.

## Commands

```sh
# Resolve the bundled helpers from the runtime automation directory.
automation_dir="${SYMPHONY_WORKSPACE_AUTOMATION_DIR:?SYMPHONY_WORKSPACE_AUTOMATION_DIR is required}"
repo_cmd="$automation_dir/bin/repo"
provider_cmd="$automation_dir/bin/repo-provider"

# Identify branch through repo-core when available.
branch=$("$repo_cmd" current-branch)

# Minimal validation gate: run the current repo's documented checks from this
# repo root before pushing. Examples:
#   make all
#   npm test
#   cargo test

# Initial push: respect the current origin remote. In CNB mode that remote
# should already be HTTPS-based and authenticated through the existing Git
# credential flow; do not rewrite it here as a workaround.
"$repo_cmd" push "$branch" --set-upstream

# If that failed because the remote moved, use the pull skill. After
# pull-skill resolution and re-validation, retry the normal push:
"$repo_cmd" push "$branch" --set-upstream

# If the configured remote rejects the push for auth, permissions, or workflow
# restrictions, stop and surface the exact error.

# Only if history was rewritten locally:
"$repo_cmd" push "$branch" --force-with-lease

# After whichever push succeeds, confirm the configured remote sees the same
# branch head that was validated locally.
local_sha=$("$repo_cmd" head-sha)
published_sha=$("$repo_cmd" published-head-sha "$branch")
if [ "$published_sha" != "$local_sha" ]; then
  echo "Published head $published_sha does not match local HEAD $local_sha" >&2
  exit 1
fi

# Ensure a PR or equivalent change proposal exists. The provider helper owns
# provider-native behavior for the configured repo provider.
pr_state=$("$provider_cmd" pr-view --json state -q .state 2>/dev/null || true)
if [ "$pr_state" = "MERGED" ] || [ "$pr_state" = "CLOSED" ]; then
  echo "Current branch is tied to a closed PR; create a new branch with the repo helper, then create a replacement PR." >&2
  exit 1
fi

# Write a clear, human-friendly title that summarizes the shipped change.
pr_title="<clear PR title written for this change>"
if [ -z "$pr_state" ]; then
  "$provider_cmd" pr-create --title "$pr_title"
else
  # Reconsider title on every branch update; edit if scope shifted.
  "$provider_cmd" pr-edit --title "$pr_title"
fi

# Optional workflow-level label enforcement when configured:
# required_pr_label="<configured repo.provider.options.required_pr_label or empty>"
# if [ -n "$required_pr_label" ] && [ "$("$provider_cmd" current-kind | tr -d '\n')" = "github" ]; then
#   "$provider_cmd" pr-add-label "$required_pr_label"
# fi

# Write/edit PR body to match .github/pull_request_template.md before validation.
# Example workflow:
# 1) open the template and draft body content for this PR
# 2) "$provider_cmd" pr-edit --body-file /tmp/pr_body.md
# 3) for branch updates, re-check that title/body still match current diff

tmp_pr_body=$(mktemp)
"$provider_cmd" pr-view --json body -q .body > "$tmp_pr_body"
# If the target repo ships a local PR-body validator, run it here.
rm -f "$tmp_pr_body"

# Show PR URL for the reply
"$provider_cmd" pr-view --json url -q .url
```

## Notes

- Do not use `--force`; only use `--force-with-lease` as the last resort.
- Distinguish sync problems from remote auth/permission problems:
  - Use the `pull` skill for non-fast-forward or stale-branch issues.
  - Surface auth, permissions, or workflow restrictions directly instead of
    changing remotes or protocols.

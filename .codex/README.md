# Codex Local Skills

This directory is for developing this repository with Codex.

It is not the runtime workspace automation source. Runtime automation is
bundled from `elixir/priv/workspace_automation` and copied into each issue
workspace by Symphony.

Repo-local skills should use the ambient checkout and local developer tools
such as `git`, `gh`, and project commands. They may encode assumptions for this
repository, such as GitHub PRs and `origin/main`.

They should not depend on `SYMPHONY_WORKSPACE_AUTOMATION_DIR`, `repo/.codex`, or
workspace-root automation helpers unless a task is explicitly testing the
runtime automation pack.

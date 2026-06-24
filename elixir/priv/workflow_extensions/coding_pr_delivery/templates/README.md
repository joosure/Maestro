# Coding PR Delivery Template Assets

This directory contains template and partial assets owned by the built-in
Coding PR Delivery workflow extension.

It lives under `priv/` because these files are runtime assets, not compiled
Elixir modules. OTP releases can locate them through the owning application's
private directory, while the extension code remains under
`lib/symphony_elixir/workflow/extensions/coding_pr_delivery/`.

The platform does not scan this directory as a global template source. The
owning extension registers selectable aliases through
`Workflow.Extension.template_entries/0`, and each entry points to this asset
root. Prompt partials under `_partials/` are resolved relative to this same
asset root.

This directory is the in-application form for a built-in extension. If Coding PR
Delivery is split into an external plugin application later, these assets should
move to that plugin application's own `priv/templates/` directory and be
declared through the plugin manifest or registry source. Platform code should
continue to consume only registered template entries, not this path directly.

Current aliases:

```text
linear/github/codex
linear/github/claude_code
linear/github/codebuddy_code
linear/github/opencode
tapd/cnb/opencode
tapd/cnb/claude_code
tapd/cnb/codebuddy_code
tapd/github/codex
```

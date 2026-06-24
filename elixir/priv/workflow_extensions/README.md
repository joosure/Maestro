# Built-In Workflow Extension Assets

This directory contains runtime assets owned by built-in workflow extensions.
It is not a plugin registry, not a platform mechanism directory, and not a place
for Elixir source code.

Allowed content:

- Markdown workflow templates.
- Prompt partials under the owning template asset root's `_partials/`.
- Static files required by those templates.

Keep out:

- Extension execution logic.
- Registry or catalog source modules.
- Readiness policies.
- Operator commands.
- Tool-result recorders.
- Provider adapters.
- Storage adapters or migrations.

Built-in extensions register these assets through their Elixir extension
contributions. Extension template catalogs should contribute public
`Workflow.Template.Entry` records through `Workflow.Template.entry!/1`; they
must not construct platform registry internals directly. The platform consumes
only registered template entries containing an asset root and asset path; it
must not scan this directory as a global template source or interpret extension
business semantics from the path.

Current built-in extension asset roots:

```text
coding_pr_delivery/templates/
```

If a built-in extension is split into an external plugin application later, its
assets should move to that plugin application's own `priv/` directory, for
example:

```text
apps/symphony_workflow_plugin_coding_pr_delivery/
  lib/...
  priv/templates/...
  plugin_manifest.json
```

The host application should then consume template refs from the plugin manifest
or trusted registry source, not from this host-app asset directory.

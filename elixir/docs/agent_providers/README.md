# Agent Provider Guides

This directory contains provider-specific runtime and protocol documentation.

Keep provider-neutral architecture rules in [`../architecture.md`](../architecture.md)
and provider-neutral observability rules in [`../logging.md`](../logging.md).
Use this directory for concrete agent-provider behavior such as CLI/app-server
protocol details, bundled automation packs, provider-specific event semantics,
and provider-specific token accounting.

## Current Providers

- [`codex.md`](./codex.md): Codex provider runtime, command configuration,
  sandbox/approval configuration, automation pack, event-summary, error, and
  logging notes.
- [`codex_token_accounting.md`](./codex_token_accounting.md): Codex app-server
  token-usage semantics and Maestro accounting rules.
- [`credential_ops.md`](./credential_ops.md): operator login, workflow, and
  troubleshooting notes for managed agent credentials.
- [`claude_code.md`](./claude_code.md): Claude Code provider runtime,
  stream-json transport, Dynamic Tool MCP tooling, managed credential, quota,
  and runtime-boundary notes.
- [`opencode.md`](./opencode.md): OpenCode provider runtime configuration,
  managed env-token account login, credential refs, and unsupported capability
  boundaries.

## Placement Rule

New provider documentation should live under `docs/agent_providers/<kind>.md`
or a clearly named sibling when one provider needs a deeper document. Shared
agent-provider concepts should stay in the root docs and link here only for
provider-specific details.

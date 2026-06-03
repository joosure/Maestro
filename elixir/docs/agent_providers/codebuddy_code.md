# CodeBuddy Code Provider

The `codebuddy_code` agent provider runs CodeBuddy Code behind the shared
`AgentProvider` facade. It is implemented under
[`lib/symphony_elixir/agent_provider/code_buddy_code/`](../../lib/symphony_elixir/agent_provider/code_buddy_code/).

Use this guide for concrete operator setup and current provider behavior.

## Configuration

Typical local configuration for ACP stdio:

```yaml
agent:
  credentials:
    enabled: true
    store_root: ~/.symphony/agent_credentials
    max_concurrent_leases_per_account: 1
  quota:
    preflight: off

agent_provider:
  kind: codebuddy_code
  options:
    transport: acp_stdio
    command_argv: ["codebuddy"]
    credential_ref: "credential://codebuddy_code/default"
    model: glm-5.1
    permission_mode: bypass_permissions
    mcp:
      enabled: true
      discovery: explicit_config
      approve_generated_server: true
    plugin:
      enabled: false
    http:
      enabled: false
```

`command_argv` is the preferred production shape. If omitted, Maestro uses
`["codebuddy"]` by default. Maestro appends the ACP transport, generated MCP
configuration, permission mode, model, agent, and tool allow/deny flags at
launch time.

Supported transports are:

- `acp_stdio`: starts CodeBuddy Code as a local ACP stdio process. This is the
  normal bundled-template path for Dynamic Tool sessions.
- `acp_http`: starts or connects to a loopback ACP HTTP service. This mode is
  intended for controlled local service integrations and requires explicit HTTP
  options.

`permission_mode` supports `restricted`, `planned_tools`, `provider_default`,
and `bypass_permissions`. Use the least permissive mode that still matches the
workflow. The bundled TAPD/CNB and Linear/GitHub CodeBuddy templates use
`bypass_permissions` for trusted unattended runs.

## Managed Account Login

CodeBuddy managed credentials use the `codebuddy_env_token` account shape. The
operator logs in once with an API key, and Maestro stores that key in the Agent
Credentials store. Later workflow runs reference it through
`agent_provider.options.credential_ref`.

```bash
export CODEBUDDY_API_KEY="..."

mise exec -- ./bin/symphony accounts login codebuddy_code default \
  --internet-environment public \
  --token-env CODEBUDDY_API_KEY \
  path/to/WORKFLOW.md

mise exec -- ./bin/symphony accounts verify codebuddy_code default \
  path/to/WORKFLOW.md
```

`--internet-environment` may be `public`, `internal`, or `ioa`. Keep `public`
unless the account requires an intranet or IOA environment.

Managed CodeBuddy credentials materialize only the provider-owned environment
contract into the provider process:

- `CODEBUDDY_API_KEY`
- `CODEBUDDY_AUTH_TOKEN`
- `CODEBUDDY_API_KEY_DISABLED`
- `CODEBUDDY_BASE_URL`
- `CODEBUDDY_INTERNET_ENVIRONMENT`

Do not also set these variables in `agent_provider.options.env` when using a
managed `credential_ref`; explicit provider env values override the leased
credential material.

## Dynamic Tools

For ACP stdio sessions with `mcp.enabled: true`, Maestro generates a
session-scoped MCP configuration under `.symphony/codebuddy/sessions/` in the
issue workspace and passes it directly to CodeBuddy Code. The generated MCP
server exposes only the workflow-planned Dynamic Tools for that session.

Repository-authored CodeBuddy plugins or project MCP files are not part of the
bundled CodeBuddy Dynamic Tool path. Keep provider-specific runtime guidance in
the concrete workflow template and keep typed-tool semantics in the bundled
workspace skills and runtime schemas.

## Auxiliary HTTP Metadata

The optional CodeBuddy auxiliary HTTP integration records bounded, allowlisted
metadata after an ACP HTTP turn. Supported identifiers are owned by the provider
settings and include health/version, summary metrics, session stats, and plugin
inventory. Auxiliary HTTP collection must not expose prompts, raw credentials,
workspace paths, or provider-private payloads.

## Runtime Boundary

CodeBuddy Code provider-neutral execution stays behind `AgentProvider`;
CodeBuddy ACP, command rendering, generated MCP config, and auxiliary HTTP
details stay inside the CodeBuddy provider implementation.

- [`adapter.ex`](../../lib/symphony_elixir/agent_provider/code_buddy_code/adapter.ex)
  owns provider registration, option validation, managed credential checks, and
  session wrapping.
- [`app_server.ex`](../../lib/symphony_elixir/agent_provider/code_buddy_code/app_server.ex)
  owns session start, turn orchestration, transport selection, and cleanup.
- [`app_server/protocol.ex`](../../lib/symphony_elixir/agent_provider/code_buddy_code/app_server/protocol.ex)
  owns ACP stdio protocol behavior.
- [`app_server/http_protocol.ex`](../../lib/symphony_elixir/agent_provider/code_buddy_code/app_server/http_protocol.ex)
  owns ACP HTTP behavior.
- [`command_renderer.ex`](../../lib/symphony_elixir/agent_provider/code_buddy_code/command_renderer.ex)
  owns provider command argument assembly and conflict checks.
- [`tooling.ex`](../../lib/symphony_elixir/agent_provider/code_buddy_code/tooling.ex)
  owns generated MCP Dynamic Tool configuration.

Resolved credentials must not appear in prompts, generated workspace helper
files, logs, dashboard payloads, or status payloads.

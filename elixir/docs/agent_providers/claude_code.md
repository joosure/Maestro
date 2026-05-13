# Claude Code Provider

The `claude_code` agent provider runs Claude Code through its headless
`stream-json` stdin/stdout protocol behind the shared `AgentProvider` facade.
It is implemented under
[`lib/symphony_elixir/agent_provider/claude_code/`](../../lib/symphony_elixir/agent_provider/claude_code/).

## Configuration

Typical local configuration:

```yaml
agent_provider:
  kind: claude_code
  options:
    command_argv: ["claude"]
    prompt_transport: stream_json
    permission_mode: bypassPermissions
    model: sonnet
```

`command_argv` is the preferred production shape. Maestro appends the
provider-native stream-json, strict MCP config, session-id, permission-mode,
model, and effort arguments at launch time.

`model` is passed through to Claude Code as `--model <value>`. Claude Code
accepts aliases such as `sonnet`; aliases are concise and track the provider's
current mapping, but they are not a pinned model contract. Use a full
Claude Code-supported model id in production workflows that require strict
reproducibility.

`command` is reserved for deployment-authored static commands:

```yaml
agent_provider:
  kind: claude_code
  options:
    command: claude
```

Do not build `command` from issue, branch, repository, workflow, prompt, or
provider-generated values. Local string commands run through a shell. Remote
string commands are high-trust deployment-authored command strings.

Supported Claude Code options:

- `command`
- `command_argv`
- `env`
- `prompt_transport`
- `model`
- `effort`
- `permission_mode`
- `telemetry`
- `credential_ref`
- `quota_probe`
- `turn_timeout_ms`
- `read_timeout_ms`
- `stall_timeout_ms`

`prompt_transport` supports only `stream_json`.

## Workspace Tooling

The Claude Code adapter prepares provider-owned tooling under
`.symphony/claude/` in the issue workspace.

- `tooling.ex` coordinates local and remote workspace preparation and writes
  provider config plus runtime MCP helper files.
- `tooling/mcp_config.ex` owns the generated MCP config path and JSON payload.
- `tooling/remote_bootstrap.ex` owns the remote shell bootstrap script for
  writing MCP files and `.git/info/exclude` entries.
- `tooling/tool_specs.ex` extracts provider-visible Dynamic Tool specs from
  the explicit Agent Dynamic Tool context supplied by the provider facade.
- Generated MCP helper source is provider-neutral and lives under
  `agent_provider/planned_tool_mcp_server*`:
  `planned_tool_mcp_server.ex` renders the helper, while
  `planned_tool_mcp_server/tool_registry.ex`, `protocol.ex`, `handlers.ex`,
  `bridge_client.ex`, and `template.ex` own the generated Node helper internals.
- Dynamic Tool bridge path, token, transport, and environment names come from
  `SymphonyElixir.Agent.DynamicTool.BridgeContract`.
- Provider startup merges captured Dynamic Tool source environment, bridge
  runtime environment, and explicit provider `env`; explicit provider values
  win.

Workspace preparation is not a tool-selection authority. It may write MCP
directories, an empty MCP config, or MCP files derived from an explicitly
supplied workflow-planned `tool_context`, but it must not inspect issue state,
workflow route, or source-advertised tools to decide exposure. Local session
startup rewrites the runtime MCP config and helper source from the
session-restricted context; if preparation and startup differ, startup is the
execution authority.

The generated MCP helper must not contain resolved credentials. Runtime
credential values belong in the provider process environment.

## Runtime Boundary

Claude Code provider-neutral execution stays behind `AgentProvider`; Claude
Code's stream-json protocol details stay inside the Claude Code provider
implementation.

- [`app_server.ex`](../../lib/symphony_elixir/agent_provider/claude_code/app_server.ex)
  owns session start, turn orchestration, and terminal session cleanup calls.
- [`app_server/launcher.ex`](../../lib/symphony_elixir/agent_provider/claude_code/app_server/launcher.ex)
  owns runtime target selection, workspace cwd validation, command argument
  assembly, remote shell command assembly, and provider process environment
  assembly.
- [`app_server/stream_protocol.ex`](../../lib/symphony_elixir/agent_provider/claude_code/app_server/stream_protocol.ex)
  owns stream-json stdin writes, stdout event parsing, assistant-part callback
  emission, session-id checks, and turn/read/stall timeout handling.
- [`app_server/usage.ex`](../../lib/symphony_elixir/agent_provider/claude_code/app_server/usage.ex)
  owns provider token usage normalization and turn-id extraction.
- [`app_server/event_fields.ex`](../../lib/symphony_elixir/agent_provider/claude_code/app_server/event_fields.ex)
  owns the Claude Code structured observability base context.
- [`app_server/process_lifecycle.ex`](../../lib/symphony_elixir/agent_provider/claude_code/app_server/process_lifecycle.ex)
  owns provider process termination.
- Shared callback message emission and provider process metadata live under
  [`agent_provider/app_server/`](../../lib/symphony_elixir/agent_provider/app_server/).

## Managed Credentials And Quota

Claude Code managed credentials use the common Agent Credentials store and
lease lifecycle through `agent_provider.options.credential_ref`. OAuth-token
accounts materialize `CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CONFIG_DIR`, and a
blank `ANTHROPIC_API_KEY` into the provider process environment.

Quota probes use the common Agent Quota layer. The Claude Code provider owns
only the Anthropic rate-limit parser callback; polling cadence, snapshot
storage, and run admission stay provider-neutral.

The resolved token must not appear in prompts, workspace helper files, logs, or
status payloads. Redaction covers common provider token shapes and
`*_API_KEY=value` environment assignments.

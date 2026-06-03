# OpenCode Provider

The `opencode` agent provider runs OpenCode in server mode behind the shared
`AgentProvider` facade. Turn results come from OpenCode's synchronous
`/session/:id/message` endpoint; SSE is used for runtime events such as
permission prompts, progress and errors. It is implemented under
[`lib/symphony_elixir/agent_provider/open_code/`](../../lib/symphony_elixir/agent_provider/open_code/).

Use this guide for concrete operator setup and current provider behavior.

## Configuration

Typical local configuration:

```yaml
agent:
  credentials:
    enabled: true
    store_root: ~/.symphony/agent_credentials
    max_concurrent_leases_per_account: 1
  quota:
    preflight: off

agent_provider:
  kind: opencode
  options:
    command_argv: ["opencode", "serve", "--hostname", "127.0.0.1", "--port", "0"]
    agent: build
    credential_ref: "credential://opencode/openrouter"
```

`command_argv` is the preferred production shape. If omitted, Maestro uses the
same `opencode serve --hostname 127.0.0.1 --port 0` shape by default.

`agent` defaults to `build`. `variant` may be `low`, `medium`, `high`, or
`max`. `model` may be set when the OpenCode deployment expects an explicit
provider-native model value.

OpenCode does not expose a workflow `prompt_transport` option. Maestro always
posts turns through `/session/:id/message` and uses the returned message as the
authoritative turn result.

Keep model-provider secrets out of `agent_provider.options.env` when using a
managed `credential_ref`. Explicit `env` values win over generated credential
environment, so setting the same variable in both places overrides the leased
credential.

## Managed Account Login

OpenCode managed credentials use the `opencode_env_token` account shape. The
environment variable name is non-secret metadata; the token value is copied into
the Agent Credentials secret store.

The configured environment variable must be one that OpenCode itself reads for
the selected model provider. OpenCode's
[provider documentation](https://opencode.ai/docs/providers/) describes
provider-native API key settings such as `apiKey: "{env:...}"`, and some
built-in providers are enabled by their expected environment variable names.
For example, the Google provider expects `GOOGLE_GENERATIVE_AI_API_KEY`. If an
operator stores the same secret under a local alias such as `GEMINI_API_KEY`,
export the OpenCode-native name before logging the account into Maestro.

Verified Google/Gemini example:

```bash
export GOOGLE_GENERATIVE_AI_API_KEY="$GEMINI_API_KEY"
symphony accounts login opencode google \
  --env-name GOOGLE_GENERATIVE_AI_API_KEY \
  --token-env GOOGLE_GENERATIVE_AI_API_KEY \
  path/to/WORKFLOW.md
```

Workflow excerpt:

```yaml
agent:
  credentials:
    enabled: true
    store_root: ~/.symphony/agent_credentials
    max_concurrent_leases_per_account: 1
  quota:
    preflight: off

agent_provider:
  kind: opencode
  options:
    command_argv: ["opencode", "serve", "--hostname", "127.0.0.1", "--port", "0"]
    agent: build
    model: google/gemini-2.5-flash-lite
    credential_ref: "credential://opencode/google"
```

Example for an OpenRouter-backed OpenCode profile:

```bash
export OPENROUTER_API_KEY="..."
symphony accounts login opencode openrouter \
  --env-name OPENROUTER_API_KEY \
  --token-env OPENROUTER_API_KEY \
  path/to/WORKFLOW.md
```

Equivalent stdin form:

```bash
printf '%s' "$OPENROUTER_API_KEY" | symphony accounts login opencode openrouter \
  --env-name OPENROUTER_API_KEY \
  --token-stdin \
  path/to/WORKFLOW.md
```

After login, reference the account from workflow config as:

```yaml
agent_provider:
  kind: opencode
  options:
    credential_ref: "credential://opencode/openrouter"
```

The account id in the command (`openrouter` above) becomes the trailing segment
of the credential ref. Use a different id for each model-provider credential
profile, for example `anthropic`, `openrouter`, or `local-gateway`.

Concrete OpenRouter workflow example:

```yaml
agent:
  credentials:
    enabled: true
    store_root: ~/.symphony/agent_credentials
    max_concurrent_leases_per_account: 1
  quota:
    preflight: off

agent_provider:
  kind: opencode
  options:
    command_argv: ["opencode", "serve", "--hostname", "127.0.0.1", "--port", "0"]
    agent: build
    model: openrouter/anthropic/claude-sonnet-4
    credential_ref: "credential://opencode/openrouter"
```

For an Anthropic-backed profile, keep the same account shape and change only
the account id, environment variable name, and provider-native model:

```bash
export ANTHROPIC_API_KEY="..."
symphony accounts login opencode anthropic \
  --env-name ANTHROPIC_API_KEY \
  --token-env ANTHROPIC_API_KEY \
  path/to/WORKFLOW.md
```

```yaml
agent_provider:
  kind: opencode
  options:
    model: anthropic/claude-sonnet-4
    credential_ref: "credential://opencode/anthropic"
```

Useful account commands:

```bash
symphony accounts list opencode path/to/WORKFLOW.md
symphony accounts verify opencode openrouter path/to/WORKFLOW.md
symphony accounts disable opencode openrouter path/to/WORKFLOW.md
symphony accounts enable opencode openrouter path/to/WORKFLOW.md
symphony accounts remove opencode openrouter path/to/WORKFLOW.md
```

`accounts verify opencode <id>` starts `opencode --version` with the env-token
credential materialized in the provider process environment. This verifies the
stored profile shape, secret materialization, and CLI availability. It does not
prove that the upstream model provider accepts the token; use a non-interactive
OpenCode session smoke run with the same workflow file for that.

## Real Smoke Evidence

On 2026-05-04, OpenCode CLI `1.14.33` was installed in a temporary path and
validated with a real Google/Gemini provider token copied into the
`opencode_env_token` account shape.

Sanitized operator command results:

```text
symphony accounts login opencode google-smoke-20260504 \
  --env-name GOOGLE_GENERATIVE_AI_API_KEY \
  --token-env GOOGLE_GENERATIVE_AI_API_KEY \
  --config elixir/WORKFLOW.md

Stored opencode account google-smoke-20260504

symphony accounts verify opencode google-smoke-20260504 \
  --config elixir/WORKFLOW.md

Verified opencode account google-smoke-20260504
1.14.33
```

The provider-token acceptance control used a clean XDG config/data/cache/state
root and only `GOOGLE_GENERATIVE_AI_API_KEY` in the provider process
environment:

```text
opencode run --model google/gemini-2.5-flash-lite --agent build --format json
status=0
provider_reply=seen
secret_leak=not_seen
```

The Maestro managed-session smoke then launched `opencode serve` through
`AgentProvider.start_session/3`, acquired the same credential ref, completed one
turn, and stopped the provider process:

```text
start_session=ok
run_turn=completed
reply_seen=true
session_id_present=true
usage_keys=input,output,reasoning,total
xdg_secret_leak=not_seen
active_leases={}
```

The disposable smoke account was removed after evidence capture.

## Runtime Behavior

At session start, Maestro:

1. acquires the account lease from `agent.credentials.store_root`
2. reads the token from the account secret file
3. materializes `%{env_name => token}` for the OpenCode server process
4. starts `opencode serve` in the prepared issue workspace
5. creates an OpenCode HTTP session and posts rendered prompts through
   `/session/:id/message`

The resolved token must not appear in prompts, workspace helper files, logs, or
status payloads. Redaction covers common provider token shapes and
`*_API_KEY=value` environment assignments.

## Workspace Tooling

OpenCode provider tooling prepares provider-owned files under `.opencode/` in
the issue workspace.

- `tooling.ex` coordinates local workspace preparation and explicit remote
  rejection.
- `tooling/tool_specs.ex` extracts provider-visible Dynamic Tool specs from the
  explicit Agent Dynamic Tool context supplied by the provider facade.
- `tooling/tool_entries.ex` owns generated OpenCode tool filenames and
  duplicate-name disambiguation.
- `tooling/tool_files.ex` owns generated TypeScript tool file writes and stale
  file removal.
- `tooling/manifest.ex` owns the provider manifest used to identify generated
  files from earlier preparations.
- `tooling/planned_tool_plugin.ex` coordinates provider-specific TypeScript
  source rendering.
- `tooling/planned_tool_plugin/schema_renderer.ex` owns JSON-schema-to-Zod
  argument rendering for provider tool registration.
- `tooling/planned_tool_plugin/template.ex` owns the generated
  TypeScript template that calls the shared Dynamic Tool bridge.
- `tooling/planned_tool_plugin/tool_spec.ex` owns normalized tool fields used
  by generated OpenCode source.

Generated tool files must read only provider-neutral bridge environment such as
`SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL` and
`SYMPHONY_DYNAMIC_TOOL_BRIDGE_TOKEN`.

Workspace preparation is not a tool-selection authority. It may remove stale
generated tool files, write an empty tool manifest state, or write tool files
derived from an explicitly supplied workflow-planned `tool_context`, but it
must not inspect issue state, workflow route, or source-advertised tools to
decide exposure. Local session startup rewrites `.opencode/tools` from the
session-restricted context before launching OpenCode.

## Runtime Boundary

OpenCode provider-neutral execution stays behind `AgentProvider`; OpenCode's
HTTP message API and SSE runtime events stay inside the OpenCode provider
implementation.

- [`app_server.ex`](../../lib/symphony_elixir/agent_provider/open_code/app_server.ex)
  owns session start, turn orchestration, task coordination, and terminal
  session cleanup calls.
- [`app_server/launcher.ex`](../../lib/symphony_elixir/agent_provider/open_code/app_server/launcher.ex)
  owns local runtime placement checks, workspace cwd validation, command launch,
  listening URL discovery, and provider process environment assembly.
- [`app_server/http_requests.ex`](../../lib/symphony_elixir/agent_provider/open_code/app_server/http_requests.ex)
  owns health checks, session creation, abort calls, and HTTP/transport error
  shaping for those short server operations.
- [`app_server/transport/sync_message.ex`](../../lib/symphony_elixir/agent_provider/open_code/app_server/transport/sync_message.ex)
  owns synchronous `/session/:id/message` prompt posts and turn-response error
  shaping.
- [`app_server/event_stream.ex`](../../lib/symphony_elixir/agent_provider/open_code/app_server/event_stream.ex)
  owns SSE parsing, session filtering, permission replies, input rejection, and
  terminal stream failure detection.
- [`app_server/usage.ex`](../../lib/symphony_elixir/agent_provider/open_code/app_server/usage.ex)
  owns provider token usage extraction and turn-id extraction.
- [`app_server/event_fields.ex`](../../lib/symphony_elixir/agent_provider/open_code/app_server/event_fields.ex)
  owns the OpenCode structured observability base context.
- [`app_server/process_lifecycle.ex`](../../lib/symphony_elixir/agent_provider/open_code/app_server/process_lifecycle.ex)
  owns provider process termination.
- [`app_server/diagnostics.ex`](../../lib/symphony_elixir/agent_provider/open_code/app_server/diagnostics.ex)
  owns bounded diagnostic output.
- Shared callback message emission and provider process metadata live under
  [`agent_provider/app_server/`](../../lib/symphony_elixir/agent_provider/app_server/).

## Unsupported Capabilities

The bundled OpenCode provider does not claim:

- `agent.runtime.remote_worker`
- `agent.quota.probe`

Keep `agent.quota.preflight` set to `off` or `advisory` unless OpenCode later
ships a deterministic provider-native quota probe and the provider profile
declares `agent.quota.probe`.

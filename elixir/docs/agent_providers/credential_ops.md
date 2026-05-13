# Agent Credential Operations Note

Date: 2026-05-04

Use managed credentials only through `agent_provider.options.credential_ref`.
Do not put provider secrets directly in workflow YAML.

## Login

OpenCode env-token account:

```bash
export GOOGLE_GENERATIVE_AI_API_KEY="$GEMINI_API_KEY"
symphony accounts login opencode google \
  --env-name GOOGLE_GENERATIVE_AI_API_KEY \
  --token-env GOOGLE_GENERATIVE_AI_API_KEY \
  path/to/WORKFLOW.md
symphony accounts verify opencode google path/to/WORKFLOW.md
```

Codex API-key account:

```bash
printf '%s' "$OPENAI_API_KEY" \
  | symphony accounts login codex openai --token-stdin path/to/WORKFLOW.md
symphony accounts verify codex openai path/to/WORKFLOW.md
```

Claude Code accounts use the `claude_code` provider kind. OAuth-token accounts
materialize `CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CONFIG_DIR`, and a blank
`ANTHROPIC_API_KEY` into the provider process environment when referenced from
`agent_provider.options.credential_ref`.

## Workflow

OpenCode:

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
    model: google/gemini-2.5-flash-lite
    credential_ref: "credential://opencode/google"
```

Codex:

```yaml
agent:
  credentials:
    enabled: true
    store_root: ~/.symphony/agent_credentials
    max_concurrent_leases_per_account: 1
  quota:
    preflight: off

agent_provider:
  kind: codex
  options:
    command_argv: ["codex", "app-server"]
    credential_ref: "credential://codex/openai"
```

## Troubleshooting

- `accounts verify` proves account shape, secret materialization, and provider
  CLI availability. It is not quota or balance evidence.
- For OpenCode, confirm the account `--env-name` matches the environment
  variable OpenCode expects for that provider. Example: Google expects
  `GOOGLE_GENERATIVE_AI_API_KEY`, not a local alias such as `GEMINI_API_KEY`.
- For Codex, inspect the generated materialization contract, not the parent
  shell. The provider process should receive `CODEX_HOME`, not a raw
  `OPENAI_API_KEY`.
- If a run fails before provider start, check the account state:

```bash
symphony accounts list path/to/WORKFLOW.md
symphony accounts enable <provider> <id> path/to/WORKFLOW.md
symphony accounts resume <provider> <id> path/to/WORKFLOW.md
```

- If a run fails during provider auth, run a minimal non-interactive provider
  session smoke with the same model and environment variable name.
- Keep Codex/OpenCode quota disabled until the provider profile declares
  `agent.quota.probe` with real provider-native probe evidence.

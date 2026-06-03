# Compose Profiles

- `compose.quickstart.yml`: first-run experience using `memory/no_repo/mock`; no external credentials required.
- `compose.integration.yml`: real workflow integration using explicit provider profiles. Use `--profile opencode` for `runtime-agent-opencode`, `--profile codex` for `runtime-agent-codex`, `--profile claude-code` for `runtime-agent-claude-code`, or `--profile codebuddy` for `runtime-agent-codebuddy`.

See `docs/deployment/container.md` for the full container deployment guide.

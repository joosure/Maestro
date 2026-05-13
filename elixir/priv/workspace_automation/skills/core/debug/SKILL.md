---
name: debug
description:
  Investigate stuck runs and execution failures by tracing Symphony agent-provider
  logs with issue/session identifiers; use when runs stall, retry repeatedly, or
  fail unexpectedly.
---

# Debug

## Goals

- Find why a run is stuck, retrying, or failing.
- Correlate tracker issue identity to an agent-provider session quickly.
- Read the right logs in the right order to isolate root cause.

## Log Sources

- Primary runtime log: `log/symphony.log`
  - This is the default runtime log path unless the deployment configures a
    different one.
  - Includes orchestrator, agent runner, and agent-provider lifecycle logs.
- Rotated runtime logs: `log/symphony.log*`
  - Check these when the relevant run is older.

## Correlation Keys

- `issue_identifier`: human ticket key (example: `MT-625`)
- `issue_id`: tracker-native internal ID
- `session_id`: provider-neutral agent session identifier; exact format is
  provider-owned
- `thread_id`: optional provider-native thread/conversation identifier
- `turn_id`: optional provider-native turn/message identifier

The structured logging contract uses these fields for issue/session lifecycle
logs. Use `session_id` as the primary cross-provider join key during
debugging. Use `thread_id` and `turn_id` only as narrowing keys when a provider
emits them; do not assume any provider-specific composite shape is portable.

## Quick Triage (Stuck Run)

1. Confirm scheduler/worker symptoms for the ticket.
2. Find recent lines for the ticket (`issue_identifier` first).
3. Extract `session_id` from matching lines.
4. Trace that `session_id` across start, stream, completion/failure, and stall
   handling logs.
5. Decide class of failure: timeout/stall, app-server startup failure, turn
   failure, or orchestrator retry loop.

## Commands

```bash
# 1) Narrow by ticket key (fastest entry point)
rg -n "issue_identifier=MT-625" log/symphony.log*

# 2) If needed, narrow by tracker-native internal id
rg -n "issue_id=<tracker-id>" log/symphony.log*

# 3) Pull session IDs seen for that ticket
rg -n "issue_identifier=MT-625" log/symphony.log* | rg -o "session_id=[^ ;]+" | sort -u

# 4) Trace one session end-to-end
rg -n "session_id=<session-id>" log/symphony.log*

# 5) Focus on stuck/retry signals
rg -n "Issue stalled|scheduling retry|turn_timeout|turn_failed|session failed|session ended with error" log/symphony.log*
```

## Investigation Flow

1. Locate the ticket slice:
    - Search by `issue_identifier=<KEY>`.
    - If noise is high, add `issue_id=<UUID>`.
2. Establish timeline:
    - Identify the first provider lifecycle line with `session_id=...`.
    - If startup fails before `session_id` is emitted, pivot on `run_id` and
      provider-native fields such as `thread_id` when present.
    - Follow with provider completion, `ended with error`, or worker exit
      lines.
3. Classify the problem:
    - Stall loop: `Issue stalled ... restarting with backoff`.
    - Provider startup: `session failed ...`.
    - Turn execution failure: `turn_failed`, `turn_cancelled`, `turn_timeout`, or
      `ended with error`.
    - Worker crash: `Agent task exited ... reason=...`.
4. Validate scope:
    - Check whether failures are isolated to one issue/session or repeating across
      multiple tickets.
5. Capture evidence:
    - Save key log lines with timestamps, `issue_identifier`, `issue_id`, and
      `session_id`.
    - Record probable root cause and the exact failing stage.

## Reading Agent-Provider Session Logs

In Symphony, agent-provider session diagnostics are emitted into
`log/symphony.log`. Once known, `session_id` is the provider-neutral key for the
session trace. Read the lifecycle as:

1. Provider session or turn start line with `session_id=...`
2. Session stream/lifecycle events for the same `session_id`
3. Terminal event:
    - provider session completed, or
    - provider session ended with error, or
    - `Issue stalled ... restarting with backoff`

For one specific session investigation, keep the trace narrow:

1. Capture one `session_id` for the ticket.
2. Build a timestamped slice for only that session:
    - `rg -n "session_id=<session-id>" log/symphony.log*`
3. Mark the exact failing stage:
    - Startup failure before stream events (`session failed ...`).
    - Turn/runtime failure after stream events (`turn_*` / `ended with error`).
    - Stall recovery (`Issue stalled ... restarting with backoff`).
4. Pair findings with `issue_identifier` and `issue_id` from nearby lines to
   confirm you are not mixing concurrent retries.

Always pair session findings with `issue_identifier`/`issue_id` to avoid mixing
concurrent runs.

## Notes

- Prefer `rg` over `grep` for speed on large logs.
- Check rotated logs (`log/symphony.log*`) before concluding data is missing.
- If required context fields are missing in new log statements, include
  `issue_identifier`, `issue_id`, and `session_id` consistently.

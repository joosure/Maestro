---
workflow:
  profile:
    kind: triage
    version: 1
tracker:
  kind: memory
  provider:
    persist_state_updates: true
    issues:
      - id: local-memory-1
        identifier: MEM-1
        title: Explore Symphony locally without external credentials
        description: |
          This in-memory issue is bundled with the local Quick Start template.
          It lets the service, dashboard, tracker polling, workspace creation,
          and mock agent turn run without Linear, GitHub, Codex, or other
          external credentials.
        state: classifying
        labels:
          - local
          - quick-start
        url: http://localhost:4000
  lifecycle:
    active_states:
      - intake
      - classifying
    terminal_states:
      - routed
      - duplicate
      - rejected
    state_phase_map:
      intake: todo
      classifying: in_progress
      needs_info: human_review
      routed: done
      duplicate: canceled
      rejected: canceled
polling:
  interval_ms: 5000
workspace:
  root: $SYMPHONY_WORKSPACE_ROOT
repo:
  path: .
  base_branch: main
  provider:
    kind: memory
agent:
  execution:
    max_concurrent_agents: 1
    max_turns: 1
agent_provider:
  kind: mock
  options:
    message: Local memory/mock workflow completed one no-credential turn.
    complete_issue_state: routed
---

You are running the local `memory/no_repo/mock` workflow for `{{ issue.identifier }}`.

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This template is for local smoke testing only. No external tracker,
   repository, or agent credentials are required.
2. Do not clone repositories, push branches, open change proposals, or call
   external APIs from this workflow.
3. Complete the single local turn by reporting that the service, dashboard/API,
   memory tracker, memory repo provider, and mock agent provider were loaded.
   The mock provider will then move the in-memory issue to `routed` so the
   local service does not keep scheduling continuation turns.

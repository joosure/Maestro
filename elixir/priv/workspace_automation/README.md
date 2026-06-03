# Workspace Automation

This directory contains the bundled automation pack copied into each runtime
workspace. It is runtime guidance for agents, not workflow selection logic.

## Responsibility Boundary

Symphony keeps workflow prompts, bundled skills, and runtime schemas in three
separate layers:

- Workflow templates answer when the current issue should do work: route-policy
  handling, handoff/rework/merge behavior, completion bars, tracker/repo-provider
  pairing, and agent-provider runtime prerequisites.
- Bundled skills answer how a class of action is performed: typed capability
  semantics, argument shape, access boundaries, helper fallback rules, and safe
  operational recipes.
- Runtime code and typed-tool schemas enforce non-negotiable invariants such as
  workpad identity, typed tool validation, gate failure policy, candidate
  lifecycle, and provider adapter behavior.

Skills should not redefine workflow routes, completion bars, or tracker state
transitions. Workflow templates should not restate detailed skill how-to content
or typed-tool schemas. If a rule must be enforced for correctness, implement it
in runtime code or a typed-tool schema, then keep prompt and skill prose as
human-readable guidance.

## Skill Layout

- `skills/tracker/` owns tracker action semantics and access boundaries.
- `skills/repo/` owns repository and change-proposal operational recipes.
- `skills/core/` owns generic local development helpers such as commit, pull,
  and debug.

Prefer provider-neutral language in shared skills. If a provider-specific rule is
needed, name the provider explicitly and keep it scoped to that provider's
section or helper behavior.

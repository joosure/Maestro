# Maestro Roadmap

Languages: [English](./ROADMAP.md) · [简体中文](./ROADMAP.zh-CN.md) · [More](./LANGUAGES.md)

## Goal

Maestro has a simple goal:

> **Make AI agents easier, safer, and more reliable for real engineering teams.**

Many coding agents can already write code. Teams need more than code generation:

- work should come from real project systems such as TAPD, Linear, and future platforms;
- code should come from an explicitly configured Git repository and branch;
- each run should have an isolated workspace so tasks do not interfere with each other;
- people should understand what the agent did, what it changed, and why it failed;
- high-risk steps should remain reviewable;
- teams should be able to expand usage gradually instead of opening all permissions on day one.

This roadmap is organized around user value, not internal module names.

---

## Near term: make Maestro easier to try

A first-time user should understand and run Maestro without learning the full architecture first.

Planned work:

- a simpler local demo;
- clearer Quick Start instructions;
- screenshots, GIFs, or short demo videos;
- complete example tasks that show the full flow;
- a clearer explanation of why isolated workspaces matter: parallelism, isolation, cleanup, and reviewability;
- a clear explanation for remaining `symphony` compatibility names;
- a clear path from local demo to real project configuration.

Scenarios we want to make easier to demonstrate:

- TAPD task to GitHub pull request;
- Linear task to GitHub pull request;
- requirement analysis before coding;
- incoming work triage;
- reviewer suggestions;
- comparison of Codex, Claude Code, and OpenCode on similar tasks.

Success means a new reader can answer within minutes:

> “What does Maestro do, and why might my team need it?”

---

## Next: connect agents to real project workflows

Maestro should help agents work from the project systems teams already use, not force teams to invent a new task queue.

Planned work:

- improve the current TAPD and Linear flows;
- make task states, comments, links, and results easier to understand;
- make workflow templates easier to find, copy, and adapt;
- support more common engineering tasks: bug fixes, small features, requirement analysis, task refinement, triage, and review suggestions;
- clearly distinguish current integration support from future extension targets;
- prepare for more integrations such as Jira, GitHub Issues, GitLab, Gitea, Bitbucket, and Feishu Project.

Success means teams can start from their existing project workflow instead of changing how they manage work just to use agents.

---

## Mid term: make agent work more trustworthy

Teams should not trust a run just because an agent says “done.”

Planned work:

- clearer run history;
- easier-to-read run summaries;
- better links between tasks, Git changes, logs, and review material;
- clearer failure reasons;
- better log redaction;
- a more useful dashboard;
- visible checkpoints before writing to real project systems, pushing branches, or creating PRs;
- clearer separation between local demo, trusted evaluation, team pilot, and production operation.

Success means a reviewer can answer:

- What did the agent do?
- Which task and Git repository did it work from?
- What changed?
- Why did it stop?
- What still needs human confirmation?
- Is it safe to continue?

---

## Long term: help teams use agents at scale

A single-agent demo is useful. Team-level use requires stronger operations.

Planned work:

- safely run multiple tasks at the same time;
- keep separate workspaces and records for different projects and tasks;
- choose different agents for different task types;
- manage accounts, credentials, quota, and cost more clearly;
- improve team-level runtime environments;
- provide better retry and recovery;
- support clearer human approval points;
- help teams compare the real effectiveness of different agents and workflows.

Success means teams can expand agent usage gradually while keeping safety, cost, and quality under control.

---

## Documentation and community

Maestro should be understandable before it feels powerful.

Planned work:

- keep the main README short and example-driven;
- move deeper technical details into separate docs;
- actively maintain English and Simplified Chinese;
- keep other translations available and welcome community improvements;
- add contribution guides for project systems, agents, code platforms, and workflow templates;
- publish more real engineering scenario examples.

Success means contributors can find a useful entry point without reading the whole codebase first.

---

## Non-goals for now

Maestro is not trying to help teams bypass review, testing, or release judgment.

We care more about:

- connecting agents to real tasks;
- making code source and task source visible;
- keeping the execution process traceable;
- keeping people in control at high-risk steps;
- preserving useful run records;
- expanding automation only as trust grows.

Automation should scale with evidence, not with wishful thinking.

---

## Current focus

The current focus is to make Maestro easier to understand, easier to try, and safer to evaluate:

1. simplify the public README;
2. add a plain-language roadmap;
3. improve local demo guidance;
4. describe current integration support without calling external systems “built in”;
5. explain why isolated workspaces matter;
6. add examples for TAPD, Linear, GitHub, CNB, and real agent combinations;
7. keep technical details available without making every new reader start there.

---

## How to contribute

Useful contributions include:

- better examples;
- clearer documentation;
- safer workflow templates;
- new project-system integrations;
- new coding-agent integrations;
- new code-platform integrations;
- dashboard improvements;
- real workflow test coverage;
- native-speaker translation review.

Start with the local memory/mock flow, then move gradually toward real systems.

.PHONY: help all setup deps build fmt fmt-check lint test coverage ci dialyzer secret-scan tracker-smoke repo-provider-smoke agent-provider-smoke worker-daemon-check worker-daemon-simulated-provider-turn worker-daemon-provider-smoke worker-daemon-provider-turn worker-daemon-dynamic-tool-turn e2e e2e-linear e2e-linear-local-ssh e2e-tapd e2e-tapd-pr e2e-tapd-land e2e-tapd-rework

MIX ?= mise exec -- mix
COVERAGE_THRESHOLD ?= 70

help:
	@echo "Targets: setup, deps, fmt, fmt-check, lint, test, coverage, dialyzer, secret-scan, tracker-smoke, repo-provider-smoke, agent-provider-smoke, worker-daemon-check, worker-daemon-simulated-provider-turn, worker-daemon-provider-smoke, worker-daemon-provider-turn, worker-daemon-dynamic-tool-turn, e2e, e2e-linear, e2e-linear-local-ssh, e2e-tapd, e2e-tapd-pr, e2e-tapd-land, e2e-tapd-rework, ci"
	@echo "Variables: COVERAGE_THRESHOLD=$(COVERAGE_THRESHOLD)"

setup:
	$(MIX) setup

deps:
	$(MIX) deps.get

build:
	$(MIX) build

fmt:
	$(MIX) format

fmt-check:
	$(MIX) format --check-formatted

lint:
	$(MIX) lint

coverage:
	SYMPHONY_TEST_COVERAGE_THRESHOLD=$(COVERAGE_THRESHOLD) $(MIX) test --cover

test:
	$(MIX) test

dialyzer:
	$(MIX) deps.get
	$(MIX) dialyzer --format short

secret-scan:
	../scripts/secret-scan.sh

repo-provider-smoke: build
	./bin/symphony repo-provider smoke $(REPO_PROVIDER_SMOKE_ARGS)

agent-provider-smoke:
	$(MIX) agent_provider.smoke $(AGENT_PROVIDER_SMOKE_ARGS)

tracker-smoke:
	$(MIX) tracker.smoke $(TRACKER_SMOKE_ARGS)

worker-daemon-check:
	$(MIX) worker_daemon.check

worker-daemon-simulated-provider-turn:
	$(MIX) test test/symphony_worker_daemon/simulated_provider_turn_test.exs

worker-daemon-provider-smoke:
	SYMPHONY_RUN_WORKER_DAEMON_PROVIDER_SMOKE=1 $(MIX) test test/symphony_worker_daemon/real_provider_smoke_test.exs

worker-daemon-provider-turn:
	SYMPHONY_RUN_WORKER_DAEMON_PROVIDER_TURN=1 $(MIX) test test/symphony_worker_daemon/real_provider_turn_test.exs

worker-daemon-dynamic-tool-turn:
	SYMPHONY_RUN_WORKER_DAEMON_DYNAMIC_TOOL_TURN=1 $(MIX) test test/symphony_worker_daemon/real_provider_turn_test.exs

e2e: e2e-linear

e2e-linear:
	SYMPHONY_RUN_LIVE_E2E=1 $(MIX) test test/symphony_elixir/live_e2e_test.exs

e2e-linear-local-ssh:
	test/support/live_e2e_local_ssh/localhost_ssh_worker.sh run -- env SYMPHONY_RUN_LIVE_E2E=1 $(MIX) test test/symphony_elixir/live_e2e_test.exs:129

e2e-tapd:
	SYMPHONY_RUN_TAPD_LIVE_E2E=1 $(MIX) test test/symphony_elixir/tapd_live_e2e_test.exs

e2e-tapd-pr:
	SYMPHONY_RUN_TAPD_LIVE_E2E=1 SYMPHONY_RUN_TAPD_LIVE_PR_E2E=1 $(MIX) test test/symphony_elixir/tapd_live_e2e_test.exs

e2e-tapd-land:
	SYMPHONY_RUN_TAPD_LIVE_E2E=1 SYMPHONY_RUN_TAPD_LIVE_LAND_E2E=1 $(MIX) test test/symphony_elixir/tapd_live_e2e_test.exs

e2e-tapd-rework:
	SYMPHONY_RUN_TAPD_LIVE_E2E=1 SYMPHONY_RUN_TAPD_LIVE_REWORK_E2E=1 $(MIX) test test/symphony_elixir/tapd_live_e2e_test.exs

ci:
	$(MAKE) setup
	$(MAKE) build
	$(MAKE) fmt-check
	$(MAKE) lint
	$(MAKE) coverage
	$(MAKE) dialyzer

all: ci

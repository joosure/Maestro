# Quickstart workflows

This directory is the output location for quickstart-generated local workflow
files.

Do not treat files in this directory as canonical reusable templates. Canonical
templates live under `priv/workflow_templates/`.

Normal quickstart flow:

1. Follow the quickstart guide for your language under `docs/quickstart/`.
2. Run `../scripts/tapd-workflow-init` or `../scripts/linear-workflow-init`.
3. The script writes an expanded `WORKFLOW.*.local.md` file into this directory.
4. Start `./bin/symphony` with that generated local workflow file.

For example, the TAPD quickstart writes a local workflow here:

```bash
../scripts/tapd-workflow-init \
  --env-file ./.env.tapd.local \
  --template tapd/cnb/codebuddy_code \
  --output ./quickstart/WORKFLOW.tapd-cnb-codebuddy.local.md
```

The generated file is then passed to the main service:

```bash
mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  ./quickstart/WORKFLOW.tapd-cnb-codebuddy.local.md \
  --port 4000
```

The relationship is:

```text
priv/workflow_templates/*
        -> init script + local .env + external tracker metadata
        -> quickstart/WORKFLOW.*.local.md
        -> ./bin/symphony runtime
```

`WORKFLOW.*.local.md` files are generated runtime configuration. They are written
with bundled template partials already expanded, so newcomers do not need to
understand or edit `_partials/` includes in the generated file. They may contain
workspace-specific tracker status mappings, repository choices, provider options,
other local settings, and quickstart-only overrides.

For example, TAPD quickstart generation disables the change-proposal PR approval
gate by default so a smoke Story can demonstrate the full automation loop. Pass
`--require-pr-approval` to `tapd-workflow-init` when you want the generated local
workflow to keep that gate enabled.

Generated workflow files are safe to regenerate and overwrite, and should not be
committed.

If this directory ever contains `WORKFLOW.*.example.md` files, they are examples
only. Use them for reading and comparison, not as the source of truth for your
workspace.

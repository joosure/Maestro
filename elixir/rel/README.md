# Release Templates

This directory contains Mix release templates. It is source configuration, not a
build artifact.

`vm.args.eex` is consumed by `mix release` to generate the BEAM VM arguments for
release builds, including Docker images. Keep the `+B i` setting here so release
entrypoints do not expose the Erlang BREAK menu and bypass OTP shutdown through
interactive abort.

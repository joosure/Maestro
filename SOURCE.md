# Source Availability

Maestro is licensed under the GNU Affero General Public License version 3
(AGPL-3.0-only).

When running Maestro as a network service, operators should make the
Corresponding Source for the running version available to remote users through a
standard source repository or equivalent download location.

The built-in dashboard exposes a source notice at `/source`. The worker-daemon
API exposes the same metadata at `/api/v1/worker-daemon/source`. These paths are
owned by the Web and Worker Daemon route helpers respectively, and each surface
passes its own notice path into the shared source metadata payload.

Configure the public source location for a deployment with:

```sh
MAESTRO_SOURCE_URL=https://github.com/joosure/Maestro
MAESTRO_SOURCE_REVISION=<commit-or-release>
```

`MAESTRO_SOURCE_URL` should point to the exact source repository, archive, or
download location for the deployed version. `MAESTRO_SOURCE_REVISION` is
optional, but should be set when the deployed version corresponds to a specific
commit, tag, or release.

For compatibility with early Symphony-derived deployments, the source metadata
runtime also accepts `SYMPHONY_SOURCE_URL` and `SYMPHONY_SOURCE_REVISION` as
fallback environment variables after the `MAESTRO_*` names.

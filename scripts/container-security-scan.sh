#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${CONTAINER_SECURITY_IMAGE:-symphony:agent-security-scan}"
TARGET="${CONTAINER_SECURITY_TARGET:-runtime-agent-opencode}"
REPORT_DIR="${CONTAINER_SECURITY_REPORT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/symphony-container-scan.XXXXXX")}"
TRIVY_SEVERITY="${TRIVY_SEVERITY:-HIGH,CRITICAL}"
TRIVY_IGNORE_UNFIXED="${TRIVY_IGNORE_UNFIXED:-true}"
OPENCODE_VERSION="${OPENCODE_VERSION:-1.14.33}"
CODEX_VERSION="${CODEX_VERSION:-0.135.0}"
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.158}"
CODEBUDDY_VERSION="${CODEBUDDY_VERSION:-2.99.1}"
SYMPHONY_UID="${SYMPHONY_UID:-10001}"
SYMPHONY_GID="${SYMPHONY_GID:-10001}"

require_command() {
  local name="$1"

  if ! command -v "$name" >/dev/null 2>&1; then
    cat >&2 <<EOF
Missing required command: ${name}

Install locally with:
  brew install ${name}
EOF
    exit 127
  fi
}

require_command docker
require_command trivy
require_command syft

mkdir -p "$REPORT_DIR"

echo "Container security reports: ${REPORT_DIR}"
echo "==> Build ${IMAGE} from target ${TARGET}"

build_args=(
  --build-arg "OPENCODE_VERSION=${OPENCODE_VERSION}"
  --build-arg "CODEX_VERSION=${CODEX_VERSION}"
  --build-arg "CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION}"
  --build-arg "CODEBUDDY_VERSION=${CODEBUDDY_VERSION}"
  --build-arg "SYMPHONY_UID=${SYMPHONY_UID}"
  --build-arg "SYMPHONY_GID=${SYMPHONY_GID}"
)

if [ -n "${ELIXIR_IMAGE:-}" ]; then
  build_args+=(--build-arg "ELIXIR_IMAGE=${ELIXIR_IMAGE}")
fi

if [ -n "${RUNTIME_IMAGE:-}" ]; then
  build_args+=(--build-arg "RUNTIME_IMAGE=${RUNTIME_IMAGE}")
fi

trivy_args=(
  --severity "$TRIVY_SEVERITY"
)

if [ "$TRIVY_IGNORE_UNFIXED" = "true" ]; then
  trivy_args+=(--ignore-unfixed)
fi

DOCKER_BUILDKIT=1 docker build \
  -f "${ROOT}/docker/app/Dockerfile" \
  --target "$TARGET" \
  "${build_args[@]}" \
  -t "$IMAGE" \
  "$ROOT"

echo "==> Trivy vulnerability scan (${TRIVY_SEVERITY}; ignore_unfixed=${TRIVY_IGNORE_UNFIXED})"
trivy image \
  "${trivy_args[@]}" \
  --exit-code 1 \
  --format table \
  "$IMAGE"

echo "==> Trivy JSON report"
trivy image \
  "${trivy_args[@]}" \
  --format json \
  --output "${REPORT_DIR}/trivy-image.json" \
  "$IMAGE"

echo "==> Syft SBOM"
syft "$IMAGE" -o spdx-json="${REPORT_DIR}/sbom.spdx.json"
syft "$IMAGE" -o cyclonedx-json="${REPORT_DIR}/sbom.cyclonedx.json"

echo "Container security scan completed successfully."

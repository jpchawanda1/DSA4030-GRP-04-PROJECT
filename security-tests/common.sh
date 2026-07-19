#!/usr/bin/env bash
# Shared helpers sourced by every security-tests/test_*.sh script.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="$ROOT_DIR/evidence"
mkdir -p "$EVIDENCE_DIR"

cd "$ROOT_DIR"
# shellcheck disable=SC1091
[ -f .env ] && set -a && source .env && set +a

TS="$(date -u +%Y%m%dT%H%M%SZ)"

# Run an mc command inside the one-shot `mc` container against the storage-net.
run_mc() {
  docker compose run --rm -T mc "$@"
}

# Run init/upload/etc. shell scripts baked into the mc image's mounted volumes.
run_mc_script() {
  docker compose run --rm -T --entrypoint /bin/sh mc "$@"
}

log_section() {
  echo
  echo "================================================================"
  echo "  $*"
  echo "================================================================"
}

# Tees all following stdout/stderr in the current shell to an evidence file too.
start_evidence() {
  local test_name="$1"
  EVIDENCE_FILE="$EVIDENCE_DIR/${test_name}_${TS}.log"
  exec > >(tee -a "$EVIDENCE_FILE") 2>&1
  echo "Evidence log: $EVIDENCE_FILE"
  echo "Generated (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

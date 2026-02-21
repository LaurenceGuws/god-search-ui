#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TIMEOUT_SECS="${RELEASE_VALIDATE_TIMEOUT_SECS:-300}"

if timeout "${TIMEOUT_SECS}"s scripts/release_validate.sh --ci >/dev/null; then
  echo "release validate ci guard passed"
  exit 0
fi

code=$?
if [[ $code -eq 124 ]]; then
  echo "release validate ci guard failed: timed out after ${TIMEOUT_SECS}s"
  exit 1
fi

echo "release validate ci guard failed: release_validate exited with status $code"
exit $code

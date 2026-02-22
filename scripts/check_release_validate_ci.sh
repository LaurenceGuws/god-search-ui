#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TIMEOUT_SECS="${RELEASE_VALIDATE_TIMEOUT_SECS:-300}"
ALLOW_DIRTY_FLAG=""
if [[ "${RELEASE_VALIDATE_ALLOW_DIRTY:-0}" == "1" ]]; then
  ALLOW_DIRTY_FLAG="--allow-dirty"
fi

OUTPUT_LOG="$(mktemp)"
trap 'rm -f "$OUTPUT_LOG"' EXIT

if timeout "${TIMEOUT_SECS}"s scripts/release_validate.sh --ci --require-clean ${ALLOW_DIRTY_FLAG} >"$OUTPUT_LOG" 2>&1; then
  echo "release validate ci guard passed"
  exit 0
fi

code=$?
if [[ -s "$OUTPUT_LOG" ]]; then
  echo "release_validate output:"
  cat "$OUTPUT_LOG"
fi

if [[ $code -eq 124 ]]; then
  echo "release validate ci guard failed: timed out after ${TIMEOUT_SECS}s"
  exit 1
fi

echo "release validate ci guard failed: release_validate exited with status $code"
exit $code

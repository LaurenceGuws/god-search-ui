#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REQUIRE_CLEAN=0
ALLOW_DIRTY=0
SMOKE_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --require-clean)
      REQUIRE_CLEAN=1
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      ;;
    *)
      SMOKE_ARGS+=("$arg")
      ;;
  esac
done

if [[ "${RELEASE_VALIDATE_ALLOW_DIRTY:-0}" == "1" ]]; then
  ALLOW_DIRTY=1
fi

if [[ $REQUIRE_CLEAN -eq 1 && $ALLOW_DIRTY -eq 0 ]]; then
  scripts/check_clean_worktree.sh
fi

scripts/release_smoke.sh "${SMOKE_ARGS[@]}"
scripts/check_release_docs_contracts.sh

echo "release validation passed"

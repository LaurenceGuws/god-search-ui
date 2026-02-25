#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: scripts/check_release_contracts.sh [options]

Options:
  --docs-only   Run docs/help/matrix contract checks only
  --help        Show this help
EOF
}

DOCS_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --docs-only) DOCS_ONLY=1 ;;
    --help) usage; exit 0 ;;
    *)
      echo "unknown argument: $arg"
      usage
      exit 1
      ;;
  esac
done

scripts/check_release_docs_contracts.sh
if [[ $DOCS_ONLY -eq 0 ]]; then
  scripts/check_release_validate_ci.sh
  scripts/check_shell_health_contract.sh
fi

echo "release contract checks passed"

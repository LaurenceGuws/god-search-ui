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

Notes:
  Full mode runs GUI-dependent runtime checks:
    - scripts/check_shell_health_contract.sh
    - scripts/control_plane_smoke.sh
    - scripts/wm_event_refresh_smoke.sh
  These checks may self-skip when no usable display session is available.
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
  echo "runtime-check note: GUI-dependent checks may self-skip when WAYLAND_DISPLAY/DISPLAY are unavailable"
  scripts/check_release_validate_ci.sh
  scripts/check_shell_health_contract.sh
  scripts/control_plane_smoke.sh
  scripts/wm_event_refresh_smoke.sh
fi

echo "release contract checks passed"

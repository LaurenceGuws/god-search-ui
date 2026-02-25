#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

HELP="$(scripts/check_release_contracts.sh --help)"
README="README.md"
MATRIX="docs/RELEASE_SCRIPT_MATRIX.md"

test -f "$README"
test -f "$MATRIX"

printf '%s\n' "$HELP" | rg -q -- '--docs-only'
printf '%s\n' "$HELP" | rg -q -- '--help'
printf '%s\n' "$HELP" | rg -q -- 'Full mode runs GUI-dependent runtime checks:'
printf '%s\n' "$HELP" | rg -q -- 'scripts/check_shell_health_contract.sh'
printf '%s\n' "$HELP" | rg -q -- 'scripts/control_plane_smoke.sh'
printf '%s\n' "$HELP" | rg -q -- 'may self-skip when no usable display session is available'

rg -q --fixed-strings 'scripts/check_release_contracts.sh --docs-only' "$README"
rg -q --fixed-strings 'scripts/release_validate.sh --ci --require-clean' "$README"
rg -q --fixed-strings 'scripts/check_release_validate_ci.sh' "$README"
rg -q --fixed-strings 'For release operations, start with `scripts/check_release_contracts.sh --docs-only` then `scripts/release_validate.sh --ci --require-clean`.' "$README"
if [[ "$(rg -c --fixed-strings 'Release contracts reference:' "$README")" -lt 2 ]]; then
  echo "release contracts alias contract failed: expected release contracts reference in both README sections"
  exit 1
fi
rg -q --fixed-strings '`scripts/check_release_contracts.sh --docs-only`' "$MATRIX"
rg -q --fixed-strings '`scripts/check_release_contracts.sh`' "$MATRIX"

echo "release contracts alias contract checks passed"

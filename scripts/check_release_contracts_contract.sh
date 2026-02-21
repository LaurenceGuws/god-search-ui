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

rg -q --fixed-strings 'scripts/check_release_contracts.sh --docs-only' "$README"
rg -q --fixed-strings 'scripts/release_validate.sh --ci --require-clean' "$README"
rg -q --fixed-strings 'scripts/check_release_validate_ci.sh' "$README"
rg -q --fixed-strings '`scripts/check_release_contracts.sh --docs-only`' "$MATRIX"
rg -q --fixed-strings '`scripts/check_release_contracts.sh`' "$MATRIX"

echo "release contracts alias contract checks passed"

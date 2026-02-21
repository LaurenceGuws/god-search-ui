#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

HELP="$(scripts/release_validate.sh --help)"
MATRIX="docs/RELEASE_SCRIPT_MATRIX.md"
SMOKE_MODES="docs/RELEASE_SMOKE_MODES.md"

test -f "$MATRIX"
test -f "$SMOKE_MODES"

printf '%s\n' "$HELP" | rg -q -- '--require-clean'
printf '%s\n' "$HELP" | rg -q -- '--allow-dirty'
printf '%s\n' "$HELP" | rg -q -- '--help'
printf '%s\n' "$HELP" | rg -q -- 'forwarded to scripts/release_smoke.sh'

rg -q --fixed-strings '`scripts/release_validate.sh`' "$MATRIX"
rg -q --fixed-strings '`scripts/release_validate.sh --ci`' "$MATRIX"
rg -q --fixed-strings 'scripts/release_validate.sh --ci' "$SMOKE_MODES"

echo "release validate contract checks passed"

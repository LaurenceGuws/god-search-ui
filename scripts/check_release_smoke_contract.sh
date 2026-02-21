#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

HELP="$(scripts/release_smoke.sh --help)"
DOC="docs/RELEASE_SMOKE_MODES.md"

test -f "$DOC"

# CLI help contract
printf '%s\n' "$HELP" | rg -q -- '--ci'
printf '%s\n' "$HELP" | rg -q -- '--with-gtk-runtime'
printf '%s\n' "$HELP" | rg -q -- '--strict-icon-threshold'
printf '%s\n' "$HELP" | rg -q -- '--icon-threshold=N'
printf '%s\n' "$HELP" | rg -q -- '--skip-gtk-build'
printf '%s\n' "$HELP" | rg -q -- '--help'

# Docs contract for mode table
rg -q --fixed-strings '`scripts/release_smoke.sh`' "$DOC"
rg -q --fixed-strings '`scripts/release_smoke.sh --ci`' "$DOC"
rg -q --fixed-strings '`scripts/release_smoke.sh --strict-icon-threshold --icon-threshold=5`' "$DOC"
rg -q --fixed-strings '`scripts/release_smoke.sh --with-gtk-runtime`' "$DOC"

# Docs must describe CI implications and threshold override
rg -q --fixed-strings '`--ci` implies:' "$DOC"
rg -q --fixed-strings '`--skip-gtk-build`' "$DOC"
rg -q --fixed-strings '`--icon-threshold=<N>` overrides the threshold' "$DOC"

echo "release smoke contract checks passed"

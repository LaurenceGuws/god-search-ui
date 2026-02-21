#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CUT_HELP="$(scripts/cut_release_tag.sh --help)"
PUB_HELP="$(scripts/publish_release_tag.sh --help)"

echo "$CUT_HELP" | rg -q -- '--version vX.Y.Z'
echo "$CUT_HELP" | rg -q -- '--apply'
echo "$CUT_HELP" | rg -q -- '--push'
echo "$CUT_HELP" | rg -q -- '--commit-notes'
echo "$CUT_HELP" | rg -q -- '--reuse-notes'

echo "$PUB_HELP" | rg -q -- '--version vX.Y.Z'
echo "$PUB_HELP" | rg -q -- '--remote name'
echo "$PUB_HELP" | rg -q -- '--apply'
echo "$PUB_HELP" | rg -q -- 'selected remote'

echo "release helper CLI checks passed"

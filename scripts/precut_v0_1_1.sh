#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/6] release smoke"
scripts/release_smoke.sh

echo "[2/6] helper CLI contract"
scripts/check_release_helpers.sh

echo "[3/6] matrix contract"
scripts/check_release_matrix.sh

echo "[4/6] gtk build"
zig build -Denable_gtk=true

echo "[5/6] notes presence"
test -f docs/release-notes-v0.1.1.md
rg -q --fixed-strings -- "- Version: v0.1.1" docs/release-notes-v0.1.1.md

echo "[6/6] triage artifacts presence"
test -f docs/POST_RELEASE_TRIAGE_TEMPLATE.md
test -f docs/TRIAGE_LOG.md

echo "v0.1.1 pre-cut gate passed"

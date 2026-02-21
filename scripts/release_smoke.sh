#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/4] full check"
scripts/dev.sh check

echo "[2/4] headless smoke"
printf ':refresh\nkitty\n:q\n' | zig build run -- --ui

echo "[3/4] gtk build smoke"
zig build -Denable_gtk=true

echo "[4/4] release notes draft smoke"
TMP_NOTES="$(mktemp)"
scripts/gen_release_notes.sh "SMOKE" "$TMP_NOTES" >/dev/null
rm -f "$TMP_NOTES"

echo "release smoke checks passed"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUN_GTK_RUNTIME=0
if [[ "${1:-}" == "--with-gtk-runtime" ]]; then
  RUN_GTK_RUNTIME=1
fi

echo "[1/4] full check"
scripts/dev.sh check

echo "[2/4] headless smoke"
printf ':refresh\nkitty\n:q\n' | zig build run -- --ui

echo "[3/4] gtk build smoke"
zig build -Denable_gtk=true

echo "[4/5] release notes draft smoke"
TMP_NOTES="$(mktemp)"
scripts/gen_release_notes.sh "SMOKE" "$TMP_NOTES" >/dev/null
rm -f "$TMP_NOTES"

echo "[5/6] release helper CLI contract smoke"
scripts/check_release_helpers.sh

echo "[6/7] release matrix reference smoke"
scripts/check_release_matrix.sh

echo "[7/7] cut dry-run default-safe smoke"
scripts/check_cut_dryrun_default_safe.sh

if [[ $RUN_GTK_RUNTIME -eq 1 ]]; then
  echo "[optional] gtk runtime launch smoke"
  timeout 3s zig build run -Denable_gtk=true -- --ui >/dev/null 2>&1 || true
fi

echo "release smoke checks passed"

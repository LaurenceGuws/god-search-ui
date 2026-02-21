#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUN_GTK_RUNTIME=0
if [[ "${1:-}" == "--with-gtk-runtime" ]]; then
  RUN_GTK_RUNTIME=1
fi

echo "[1/8] full check"
scripts/dev.sh check

echo "[2/8] headless smoke"
printf ':refresh\nkitty\n:q\n' | zig build run -- --ui

echo "[3/8] gtk build smoke"
zig build -Denable_gtk=true

echo "[4/8] release notes draft smoke"
TMP_NOTES="$(mktemp)"
scripts/gen_release_notes.sh "SMOKE" "$TMP_NOTES" >/dev/null
rm -f "$TMP_NOTES"

echo "[5/8] release helper CLI contract smoke"
scripts/check_release_helpers.sh

echo "[6/8] release matrix reference smoke"
scripts/check_release_matrix.sh

echo "[7/8] cut dry-run default-safe smoke"
scripts/check_cut_dryrun_default_safe.sh

echo "[8/8] apps cache format smoke"
scripts/check_apps_cache_format.sh

if [[ $RUN_GTK_RUNTIME -eq 1 ]]; then
  echo "[optional] gtk runtime launch smoke"
  timeout 3s zig build run -Denable_gtk=true -- --ui >/dev/null 2>&1 || true
fi

echo "release smoke checks passed"

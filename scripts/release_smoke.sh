#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUN_GTK_RUNTIME=0
if [[ "${1:-}" == "--with-gtk-runtime" ]]; then
  RUN_GTK_RUNTIME=1
fi

echo "[1/11] full check"
scripts/dev.sh check

echo "[2/11] headless smoke"
printf ':refresh\n:icondiag\n:icondiag --json\nkitty\n:q\n' | zig build run -- --ui

echo "[3/11] gtk build smoke"
zig build -Denable_gtk=true

echo "[4/11] release notes draft smoke"
TMP_NOTES="$(mktemp)"
scripts/gen_release_notes.sh "SMOKE" "$TMP_NOTES" >/dev/null
rm -f "$TMP_NOTES"

echo "[5/11] release helper CLI contract smoke"
scripts/check_release_helpers.sh

echo "[6/11] release matrix reference smoke"
scripts/check_release_matrix.sh

echo "[7/11] cut dry-run default-safe smoke"
scripts/check_cut_dryrun_default_safe.sh

echo "[8/11] apps cache format smoke"
scripts/check_apps_cache_format.sh

echo "[9/11] icon theme env preflight"
scripts/check_icon_theme_env.sh

echo "[10/11] icondiag json schema smoke"
scripts/check_icondiag_json.sh

echo "[11/11] icondiag fallback-threshold smoke"
MAX_GLYPH_FALLBACK_PCT=100 scripts/check_icondiag_threshold.sh

if [[ $RUN_GTK_RUNTIME -eq 1 ]]; then
  echo "[optional] gtk runtime launch smoke (with icon-cache fixture)"
  TMP_HOME="$(mktemp -d)"
  trap 'rm -rf "$TMP_HOME"' EXIT
  mkdir -p "$TMP_HOME/.cache/waybar" "$TMP_HOME/.local/state/god-search-ui"
  cat > "$TMP_HOME/.cache/waybar/wofi-app-launcher.tsv" <<'EOF'
Utilities	Kitty	kitty	kitty
Internet	Firefox	firefox	firefox
EOF
  HOME="$TMP_HOME" timeout 3s zig build run -Denable_gtk=true -- --ui >/dev/null 2>&1 || true
  rm -rf "$TMP_HOME"
  trap - EXIT
fi

echo "release smoke checks passed"

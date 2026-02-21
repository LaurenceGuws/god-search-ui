#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUN_GTK_RUNTIME=0
STRICT_ICON_THRESHOLD=0
ICON_THRESHOLD="${MAX_GLYPH_FALLBACK_PCT:-100}"
SKIP_GTK_BUILD=0
CI_PRESET=0

for arg in "$@"; do
  case "$arg" in
    --with-gtk-runtime)
      RUN_GTK_RUNTIME=1
      ;;
    --ci)
      CI_PRESET=1
      STRICT_ICON_THRESHOLD=1
      SKIP_GTK_BUILD=1
      ICON_THRESHOLD="${MAX_GLYPH_FALLBACK_PCT:-5}"
      ;;
    --strict-icon-threshold)
      STRICT_ICON_THRESHOLD=1
      ICON_THRESHOLD="${MAX_GLYPH_FALLBACK_PCT:-5}"
      ;;
    --icon-threshold=*)
      ICON_THRESHOLD="${arg#--icon-threshold=}"
      ;;
    --skip-gtk-build)
      SKIP_GTK_BUILD=1
      ;;
    *)
      echo "unknown argument: $arg"
      echo "usage: scripts/release_smoke.sh [--ci] [--with-gtk-runtime] [--strict-icon-threshold] [--icon-threshold=N] [--skip-gtk-build]"
      exit 1
      ;;
  esac
done

echo "[1/11] full check"
scripts/dev.sh check

echo "[2/11] headless smoke"
printf ':refresh\n:icondiag\n:icondiag --json\nkitty\n:q\n' | zig build run -- --ui

if [[ $SKIP_GTK_BUILD -eq 0 ]]; then
  echo "[3/11] gtk build smoke"
  zig build -Denable_gtk=true
else
  echo "[3/11] gtk build smoke (skipped)"
fi

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
MAX_GLYPH_FALLBACK_PCT="$ICON_THRESHOLD" scripts/check_icondiag_threshold.sh

if [[ $STRICT_ICON_THRESHOLD -eq 1 ]]; then
  echo "[strict] icon threshold mode enabled (limit=${ICON_THRESHOLD}%)"
fi

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

if [[ $CI_PRESET -eq 1 ]]; then
  echo "[preset] ci mode enabled (--skip-gtk-build + strict icon threshold)"
fi

echo "release smoke checks passed"

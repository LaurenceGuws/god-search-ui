#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUN_GTK_RUNTIME=0
STRICT_ICON_THRESHOLD=0
ICON_THRESHOLD="${MAX_GLYPH_FALLBACK_PCT:-100}"
SKIP_GTK_BUILD=0
CI_PRESET=0

usage() {
  cat <<'EOF'
Usage: scripts/release_smoke.sh [options]

Options:
  --ci                     CI preset: skip GTK build + strict icon threshold (default 5%)
  --with-gtk-runtime       Run optional short GTK runtime launch smoke
  --strict-icon-threshold  Enable strict icon threshold mode (default threshold 5%)
  --icon-threshold=N       Override icon fallback threshold percentage
  --skip-gtk-build         Skip GTK compile smoke step
  --help                   Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --help)
      usage
      exit 0
      ;;
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

echo "[1/13] full check"
scripts/dev.sh check

echo "[2/13] headless smoke"
printf ':refresh\n:icondiag\n:icondiag --json\nkitty\n:q\n' | zig build run -- --ui

if [[ $SKIP_GTK_BUILD -eq 0 ]]; then
  echo "[3/13] gtk build smoke"
  zig build -Denable_gtk=true
else
  echo "[3/13] gtk build smoke (skipped)"
fi

echo "[4/13] release notes draft smoke"
TMP_NOTES="$(mktemp)"
scripts/gen_release_notes.sh "SMOKE" "$TMP_NOTES" >/dev/null
rm -f "$TMP_NOTES"

echo "[5/13] release helper CLI contract smoke"
scripts/check_release_helpers.sh

echo "[6/13] release matrix reference smoke"
scripts/check_release_matrix.sh

echo "[7/13] cut dry-run default-safe smoke"
scripts/check_cut_dryrun_default_safe.sh

echo "[8/13] apps cache format smoke"
scripts/check_apps_cache_format.sh

echo "[9/13] icon theme env preflight"
scripts/check_icon_theme_env.sh

echo "[10/13] icondiag json schema smoke"
scripts/check_icondiag_json.sh

echo "[11/13] icondiag fallback-threshold smoke"
MAX_GLYPH_FALLBACK_PCT="$ICON_THRESHOLD" scripts/check_icondiag_threshold.sh

echo "[12/13] release smoke contract guard"
scripts/check_release_smoke_contract.sh

echo "[13/13] release docs meta-contract guard"
scripts/check_release_docs_contracts.sh

if [[ $STRICT_ICON_THRESHOLD -eq 1 ]]; then
  echo "[strict] icon threshold mode enabled (limit=${ICON_THRESHOLD}%)"
fi

if [[ $RUN_GTK_RUNTIME -eq 1 ]]; then
  if ! command -v timeout >/dev/null 2>&1; then
    echo "error: timeout command not found; required for --with-gtk-runtime" >&2
    exit 1
  fi

  echo "[optional] gtk runtime launch smoke (with icon-cache fixture)"
  TMP_HOME="$(mktemp -d)"
  trap 'rm -rf "$TMP_HOME"' EXIT
  mkdir -p "$TMP_HOME/.cache/waybar" "$TMP_HOME/.local/state/god-search-ui"
  cat > "$TMP_HOME/.cache/waybar/wofi-app-launcher.tsv" <<'EOF'
Utilities	Kitty	kitty	kitty
Internet	Firefox	firefox	firefox
EOF
  if ! HOME="$TMP_HOME" timeout 3s zig build run -Denable_gtk=true -- --ui >/dev/null 2>&1; then
    echo "error: gtk runtime launch smoke failed" >&2
    exit 1
  fi
  rm -rf "$TMP_HOME"
  trap - EXIT
fi

if [[ $CI_PRESET -eq 1 ]]; then
  echo "[preset] ci mode enabled (--skip-gtk-build + strict icon threshold)"
fi

echo "release smoke checks passed"

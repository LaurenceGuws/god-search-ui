#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT_DIR/packaging/arch"
DO_INSTALL=0
DO_UNINSTALL=0

usage() {
  cat <<'EOF'
Usage: scripts/arch_package_smoke.sh [--install] [--uninstall]

Default behavior:
  - build package with makepkg
  - verify package archive contains launcher artifacts

Optional flags:
  --install    install package via pacman and run installed-artifact checks
  --uninstall  remove package after install checks
EOF
}

for arg in "$@"; do
  case "$arg" in
    --install) DO_INSTALL=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown arg: $arg" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ $DO_UNINSTALL -eq 1 && $DO_INSTALL -eq 0 ]]; then
  echo "error: --uninstall requires --install in the same invocation" >&2
  exit 1
fi

if ! command -v makepkg >/dev/null 2>&1; then
  echo "error: makepkg not found; run on an Arch-based host" >&2
  exit 1
fi

echo "[1/4] build package"
cd "$PKG_DIR"
makepkg -f

PKG_FILE="$(ls -1t god-search-ui-git-*.pkg.tar.* 2>/dev/null | grep -v -- '-debug-' | head -n 1 || true)"
if [[ -z "$PKG_FILE" ]]; then
  echo "error: package archive not produced" >&2
  exit 1
fi
PKG_PATH="$PKG_DIR/$PKG_FILE"
echo "built package: $PKG_PATH"

if ! command -v bsdtar >/dev/null 2>&1; then
  echo "error: bsdtar not found; required to inspect package contents" >&2
  exit 1
fi

if [[ $DO_INSTALL -eq 1 ]] && ! command -v desktop-file-validate >/dev/null 2>&1; then
  echo "error: desktop-file-validate not found; install desktop-file-utils for --install checks" >&2
  exit 1
fi

echo "[2/4] verify package archive contents"
bsdtar -tf "$PKG_PATH" | grep -q '^usr/bin/god-search-ui$'
bsdtar -tf "$PKG_PATH" | grep -q '^usr/share/applications/god-search-ui.desktop$'
bsdtar -tf "$PKG_PATH" | grep -q '^usr/share/icons/hicolor/scalable/apps/god-search-ui.svg$'
bsdtar -tf "$PKG_PATH" | grep -q '^usr/lib/systemd/user/god-search-ui.service$'

if [[ $DO_INSTALL -eq 1 ]]; then
  if ! command -v sudo >/dev/null 2>&1 || ! command -v pacman >/dev/null 2>&1; then
    echo "error: sudo/pacman required for --install path" >&2
    exit 1
  fi

  echo "[3/4] install package and validate installed artifacts"
  sudo pacman -U --noconfirm "$PKG_PATH"
  command -v god-search-ui >/dev/null 2>&1
  test -f /usr/share/applications/god-search-ui.desktop
  test -f /usr/share/icons/hicolor/scalable/apps/god-search-ui.svg
  test -f /usr/lib/systemd/user/god-search-ui.service
  desktop-file-validate /usr/share/applications/god-search-ui.desktop
  grep -q '^Exec=god-search-ui --ui$' /usr/share/applications/god-search-ui.desktop
  grep -q '^Icon=god-search-ui$' /usr/share/applications/god-search-ui.desktop
else
  echo "[3/4] install path skipped (use --install to enable)"
fi

if [[ $DO_UNINSTALL -eq 1 ]]; then
  echo "[4/4] uninstall package"
  sudo pacman -R --noconfirm god-search-ui-git
  ! command -v god-search-ui >/dev/null 2>&1
  test ! -f /usr/share/applications/god-search-ui.desktop
  test ! -f /usr/share/icons/hicolor/scalable/apps/god-search-ui.svg
  test ! -f /usr/lib/systemd/user/god-search-ui.service
else
  echo "[4/4] uninstall path skipped (use --uninstall with --install)"
fi

echo "arch package smoke checks passed"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APPLY=0
VERSION=""

usage() {
  cat <<'EOF'
Usage: scripts/publish_release_tag.sh --version vX.Y.Z [--apply]

Default mode is dry-run and prints planned push commands.

Options:
  --version   existing local tag to publish (required)
  --apply     push main and tag to origin
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "error: --version is required" >&2
  usage
  exit 1
fi

if [[ -n "$(git status --short)" ]]; then
  echo "error: working tree is not clean" >&2
  exit 1
fi

if ! git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "error: local tag does not exist: $VERSION" >&2
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "error: git remote 'origin' is not configured" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/$VERSION" >/dev/null 2>&1; then
  echo "error: remote tag already exists on origin: $VERSION" >&2
  exit 1
fi

echo "tag commit:"
git show "$VERSION" --no-patch --oneline

if [[ $APPLY -eq 0 ]]; then
  echo "[dry-run] would run: git push origin main"
  echo "[dry-run] would run: git push origin $VERSION"
  exit 0
fi

echo "[apply] pushing main and tag to origin"
git push origin main
git push origin "$VERSION"

echo "publish complete"

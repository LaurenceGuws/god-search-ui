#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APPLY=0
VERSION=""
REMOTE="origin"

usage() {
  cat <<'EOF'
Usage: scripts/publish_release_tag.sh --version vX.Y.Z [--remote name] [--apply]

Default mode is dry-run and prints planned push commands.

Options:
  --version   existing local tag to publish (required)
  --remote    git remote to publish to (default: origin)
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
    --remote)
      REMOTE="${2:-}"
      shift 2
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

if [[ -z "$REMOTE" ]]; then
  echo "error: --remote must not be empty" >&2
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

HAS_ORIGIN=1
if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  HAS_ORIGIN=0
fi

echo "tag commit:"
git show "$VERSION" --no-patch --oneline

if [[ $APPLY -eq 0 ]]; then
  if [[ $HAS_ORIGIN -eq 0 ]]; then
    echo "[dry-run] note: remote '$REMOTE' is not configured; push commands may fail until configured"
  else
    if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$VERSION" >/dev/null 2>&1; then
      echo "[dry-run] note: remote tag already exists on $REMOTE: $VERSION"
    fi
  fi
  echo "[dry-run] would run: git push $REMOTE main"
  echo "[dry-run] would run: git push $REMOTE $VERSION"
  exit 0
fi

if [[ $HAS_ORIGIN -eq 0 ]]; then
  echo "error: git remote '$REMOTE' is not configured" >&2
  exit 1
fi

if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$VERSION" >/dev/null 2>&1; then
  echo "error: remote tag already exists on $REMOTE: $VERSION" >&2
  exit 1
fi

echo "[apply] pushing main and tag to $REMOTE"
git push "$REMOTE" main
git push "$REMOTE" "$VERSION"

echo "publish complete"

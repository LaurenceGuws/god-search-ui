#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DRY_RUN=1
PUSH=0
VERSION=""

usage() {
  cat <<'EOF'
Usage: scripts/cut_release_tag.sh --version vX.Y.Z [--apply] [--push]

Default mode is dry-run and prints planned actions.

Options:
  --version   tag/version to cut (required)
  --apply     execute tag creation (otherwise dry-run)
  --push      push main + tag after creation (requires --apply)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --apply)
      DRY_RUN=0
      shift
      ;;
    --push)
      PUSH=1
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

if [[ $PUSH -eq 1 && $DRY_RUN -eq 1 ]]; then
  echo "error: --push requires --apply" >&2
  exit 1
fi

if [[ -n "$(git status --short)" ]]; then
  echo "error: working tree is not clean" >&2
  exit 1
fi

if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "error: tag already exists: $VERSION" >&2
  exit 1
fi

echo "[preflight] running release smoke"
scripts/release_smoke.sh

echo "[preflight] generating release notes draft"
scripts/gen_release_notes.sh "$VERSION" "docs/release-notes-${VERSION}.md"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[dry-run] would run: git tag -a $VERSION -m \"god-search-ui $VERSION\""
  if [[ $PUSH -eq 1 ]]; then
    echo "[dry-run] would run: git push origin main"
    echo "[dry-run] would run: git push origin $VERSION"
  fi
  exit 0
fi

echo "[apply] creating annotated tag"
git tag -a "$VERSION" -m "god-search-ui $VERSION"
git show "$VERSION" --no-patch

if [[ $PUSH -eq 1 ]]; then
  echo "[apply] pushing main and tag"
  git push origin main
  git push origin "$VERSION"
fi

echo "release tag flow complete"

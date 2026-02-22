#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DRY_RUN=1
PUSH=0
COMMIT_NOTES=0
REUSE_NOTES=0
REGEN_NOTES=0
VERSION=""
SEMVER_TAG_RE='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$'

usage() {
  cat <<'EOF'
Usage: scripts/cut_release_tag.sh --version vX.Y.Z [--apply] [--push] [--commit-notes] [--reuse-notes] [--regen-notes]

Default mode is dry-run and prints planned actions.

Options:
  --version   tag/version to cut (required, vMAJOR.MINOR.PATCH[-PRERELEASE][+BUILD])
  --apply     execute tag creation (otherwise dry-run)
  --push      push main + tag after creation (requires --apply)
  --commit-notes  commit generated release notes before tag creation (requires --apply)
  --reuse-notes   reuse existing docs/release-notes-<version>.md (requires --apply)
  --regen-notes   force regenerate notes even if file already exists (requires --apply)
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
    --commit-notes)
      COMMIT_NOTES=1
      shift
      ;;
    --reuse-notes)
      REUSE_NOTES=1
      shift
      ;;
    --regen-notes)
      REGEN_NOTES=1
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

if [[ ! "$VERSION" =~ $SEMVER_TAG_RE ]]; then
  echo "error: --version must match semver-like tag format (vMAJOR.MINOR.PATCH[-PRERELEASE][+BUILD])" >&2
  exit 1
fi

if [[ $PUSH -eq 1 && $DRY_RUN -eq 1 ]]; then
  echo "error: --push requires --apply" >&2
  exit 1
fi

if [[ $COMMIT_NOTES -eq 1 && $DRY_RUN -eq 1 ]]; then
  echo "error: --commit-notes requires --apply" >&2
  exit 1
fi

if [[ $REUSE_NOTES -eq 1 && $DRY_RUN -eq 1 ]]; then
  echo "error: --reuse-notes requires --apply" >&2
  exit 1
fi

if [[ $REGEN_NOTES -eq 1 && $DRY_RUN -eq 1 ]]; then
  echo "error: --regen-notes requires --apply" >&2
  exit 1
fi

if [[ $REUSE_NOTES -eq 1 && $REGEN_NOTES -eq 1 ]]; then
  echo "error: --reuse-notes and --regen-notes are mutually exclusive" >&2
  exit 1
fi

if [[ -n "$(git status --short)" ]]; then
  echo "error: working tree is not clean" >&2
  exit 1
fi

if git rev-parse -- "$VERSION" >/dev/null 2>&1; then
  echo "error: tag already exists: $VERSION" >&2
  exit 1
fi

if [[ "${CUT_RELEASE_SKIP_PREFLIGHT:-0}" == "1" ]]; then
  echo "[preflight] skipped (CUT_RELEASE_SKIP_PREFLIGHT=1)"
else
  echo "[preflight] running release smoke"
  scripts/release_smoke.sh
fi

NOTES_PATH="docs/release-notes-${VERSION}.md"
if [[ "$NOTES_PATH" != docs/release-notes-*.md ]]; then
  echo "error: computed notes path must remain under docs/: $NOTES_PATH" >&2
  exit 1
fi
NOTES_BASENAME="${NOTES_PATH#docs/}"
if [[ "$NOTES_BASENAME" == "$NOTES_PATH" || "$NOTES_BASENAME" == */* ]]; then
  echo "error: computed notes path must be a direct file under docs/: $NOTES_PATH" >&2
  exit 1
fi
NOTES_MODE="regen"
if [[ -f "$NOTES_PATH" && $REGEN_NOTES -eq 0 ]]; then
  NOTES_MODE="reuse"
fi
if [[ $REUSE_NOTES -eq 1 ]]; then
  NOTES_MODE="reuse"
fi
if [[ $REGEN_NOTES -eq 1 ]]; then
  NOTES_MODE="regen"
fi

if [[ $DRY_RUN -eq 1 ]]; then
  if [[ "$NOTES_MODE" == "reuse" ]]; then
    if [[ -f "$NOTES_PATH" ]]; then
      echo "[dry-run] would reuse: $NOTES_PATH"
    else
      echo "[dry-run] would fail: notes reuse requested but file missing: $NOTES_PATH"
    fi
  else
    echo "[dry-run] would run: scripts/gen_release_notes.sh $VERSION $NOTES_PATH"
  fi
  if [[ $COMMIT_NOTES -eq 1 ]]; then
    echo "[dry-run] would run: git add docs/release-notes-${VERSION}.md"
    echo "[dry-run] would run: git commit -m \"Add release notes draft for $VERSION\""
  fi
  echo "[dry-run] would run: git tag -a -m \"god-search-ui $VERSION\" -- $VERSION"
  if [[ $PUSH -eq 1 ]]; then
    echo "[dry-run] would run: git push origin main"
    echo "[dry-run] would run: git push origin -- $VERSION"
  fi
  exit 0
fi

EXPECTED_BRANCH="${CUT_RELEASE_EXPECTED_BRANCH:-main}"
if [[ ! "$EXPECTED_BRANCH" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ || "$EXPECTED_BRANCH" == */ || "$EXPECTED_BRANCH" == /* || "$EXPECTED_BRANCH" == *"//"* || "$EXPECTED_BRANCH" == *".."* ]]; then
  echo "error: invalid CUT_RELEASE_EXPECTED_BRANCH value: $EXPECTED_BRANCH" >&2
  exit 1
fi

CURRENT_BRANCH="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "error: apply mode requires a checked out branch (detached HEAD is not allowed)" >&2
  exit 1
fi
if [[ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]]; then
  echo "error: apply mode must run on branch '$EXPECTED_BRANCH' (current: '$CURRENT_BRANCH')" >&2
  exit 1
fi

if [[ "$NOTES_MODE" == "reuse" ]]; then
  if [[ ! -f "$NOTES_PATH" ]]; then
    echo "error: notes reuse requested but file missing: $NOTES_PATH" >&2
    exit 1
  fi
  echo "[apply] reusing existing release notes: $NOTES_PATH"
else
  echo "[apply] generating release notes draft"
  scripts/gen_release_notes.sh "$VERSION" "$NOTES_PATH"
fi

if [[ $COMMIT_NOTES -eq 1 ]]; then
  git add "$NOTES_PATH"
  if git diff --cached --quiet; then
    echo "[apply] notes unchanged; skipping release-notes commit"
  else
    echo "[apply] committing release notes draft"
    git commit -m "Add release notes draft for ${VERSION}"
  fi
fi

echo "[apply] creating annotated tag"
git tag -a -m "god-search-ui $VERSION" -- "$VERSION"
git show "$VERSION" --no-patch --

if [[ $PUSH -eq 1 ]]; then
  echo "[apply] pushing $EXPECTED_BRANCH and tag"
  git push origin "$EXPECTED_BRANCH"
  git push origin -- "$VERSION"
fi

echo "release tag flow complete"

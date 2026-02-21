#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Dry-run assertions rely on cut helper behavior that requires a clean tree.
if [[ -n "$(git status --short)" ]]; then
  echo "cut dry-run default-safe checks skipped (dirty worktree)"
  exit 0
fi

# Case A: notes file exists -> dry-run should choose reuse path.
VERSION_REUSE="v0.1.2"
NOTES_REUSE="docs/release-notes-${VERSION_REUSE}.md"
if [[ ! -f "$NOTES_REUSE" ]]; then
  echo "error: expected notes file for reuse case: $NOTES_REUSE" >&2
  exit 1
fi
OUT_REUSE="$(scripts/cut_release_tag.sh --version "$VERSION_REUSE" 2>&1)"
echo "$OUT_REUSE" | rg -q --fixed-strings "[dry-run] would reuse: $NOTES_REUSE"

# Case B: notes file missing -> dry-run should choose generation path.
VERSION_REGEN="v0.1.2-dryrun-missing"
NOTES_REGEN="docs/release-notes-${VERSION_REGEN}.md"
if [[ -f "$NOTES_REGEN" ]]; then
  echo "error: expected missing notes file for regenerate case: $NOTES_REGEN" >&2
  exit 1
fi
OUT_REGEN="$(scripts/cut_release_tag.sh --version "$VERSION_REGEN" 2>&1)"
echo "$OUT_REGEN" | rg -q --fixed-strings "[dry-run] would run: scripts/gen_release_notes.sh $VERSION_REGEN $NOTES_REGEN"

echo "cut dry-run default-safe checks passed"

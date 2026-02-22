#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-UNRELEASED}"
OUT="${2:-docs/release-notes-${VERSION}.md}"
SEMVER_TAG_RE='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$'

if [[ ! "$VERSION" =~ $SEMVER_TAG_RE && "$VERSION" != "SMOKE" && "$VERSION" != "UNRELEASED" ]]; then
  echo "error: version must be semver-like tag (vMAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]) or SMOKE/UNRELEASED" >&2
  exit 1
fi

if [[ "$OUT" == docs/* ]]; then
  if [[ "$OUT" != docs/release-notes-*.md ]]; then
    echo "error: docs output path must match docs/release-notes-*.md" >&2
    exit 1
  fi
  OUT_BASENAME="${OUT#docs/}"
  if [[ "$OUT_BASENAME" == "$OUT" || "$OUT_BASENAME" == */* ]]; then
    echo "error: docs output path must be a direct file under docs/" >&2
    exit 1
  fi
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: run inside git repository" >&2
  exit 1
fi

if [[ ! -f docs/RELEASE_NOTES_TEMPLATE.md ]]; then
  echo "error: docs/RELEASE_NOTES_TEMPLATE.md not found" >&2
  exit 1
fi

DATE_UTC="$(date -u +%F)"
COMMITS="$(git log --oneline -20)"

cp docs/RELEASE_NOTES_TEMPLATE.md "$OUT"

# Fill top metadata fields in-place.
sed -i "s/^\- Version:.*/- Version: ${VERSION}/" "$OUT"
sed -i "s/^\- Date:.*/- Date: ${DATE_UTC}/" "$OUT"

{
  echo
  echo "## Draft Commit Digest"
  echo
  echo '```text'
  echo "$COMMITS"
  echo '```'
} >> "$OUT"

echo "generated: $OUT"

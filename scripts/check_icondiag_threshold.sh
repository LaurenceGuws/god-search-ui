#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MAX_GLYPH_FALLBACK_PCT="${MAX_GLYPH_FALLBACK_PCT:-5}"

OUT="$(printf ':icondiag --json\n:q\n' | zig build run -- --ui)"
JSON_LINE="$(printf '%s\n' "$OUT" | grep -E '"glyph_fallback_pct":' | tail -n 1 || true)"
if [[ -z "$JSON_LINE" ]]; then
  echo "icondiag threshold check failed: no JSON diagnostics line found"
  exit 1
fi
JSON_LINE="${JSON_LINE#*\{}"
JSON_LINE="{${JSON_LINE}"

GLYPH_PCT="$(printf '%s\n' "$JSON_LINE" | sed -n 's/.*"glyph_fallback_pct":\([0-9.]*\).*/\1/p')"
if [[ -z "$GLYPH_PCT" ]]; then
  echo "icondiag threshold check failed: glyph_fallback_pct missing"
  exit 1
fi

if awk "BEGIN {exit !($GLYPH_PCT <= $MAX_GLYPH_FALLBACK_PCT)}"; then
  echo "icondiag threshold check passed: glyph_fallback_pct=${GLYPH_PCT}% (limit=${MAX_GLYPH_FALLBACK_PCT}%)"
  exit 0
fi

echo "icondiag threshold check failed: glyph_fallback_pct=${GLYPH_PCT}% exceeds limit=${MAX_GLYPH_FALLBACK_PCT}%"
exit 1

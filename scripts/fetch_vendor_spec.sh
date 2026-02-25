#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <url> <output_path> [sources_manifest]" >&2
  echo "example: $0 https://specifications.freedesktop.org/notification-spec/latest/ docs/vendor/notifications/notification-spec-latest.html docs/vendor/notifications/SOURCES.txt" >&2
  exit 2
fi

url="$1"
out_path="$2"
manifest="${3:-}"

mkdir -p "$(dirname "$out_path")"
curl -fL --retry 2 --connect-timeout 10 --max-time 60 "$url" -o "$out_path"

fetched_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "fetched: $out_path ($fetched_utc)"

if [[ "$out_path" == *.html || "$out_path" == *.htm ]]; then
  if ! command -v pandoc >/dev/null 2>&1; then
    echo "error: pandoc is required for HTML -> MD/TXT conversion" >&2
    exit 3
  fi

  base_no_ext="${out_path%.*}"
  md_path="${base_no_ext}.md"
  txt_path="${base_no_ext}.txt"

  pandoc "$out_path" -f html -t gfm -o "$md_path"
  pandoc "$out_path" -f html -t plain -o "$txt_path"
  echo "converted: $md_path"
  echo "converted: $txt_path"
fi

if [[ -n "$manifest" ]]; then
  mkdir -p "$(dirname "$manifest")"
  touch "$manifest"
  filename="$(basename "$out_path")"
  new_line="${filename} | ${url} | ${fetched_utc} | fetched via scripts/fetch_vendor_spec.sh"
  pending_prefix="${filename} | ${url} | pending |"
  if grep -Fq "$new_line" "$manifest"; then
    :
  elif grep -Fq "$pending_prefix" "$manifest"; then
    tmp_manifest="${manifest}.tmp"
    awk -v pending_prefix="$pending_prefix" -v new_line="$new_line" '
      BEGIN { replaced = 0 }
      {
        if (!replaced && index($0, pending_prefix) == 1) {
          print new_line
          replaced = 1
          next
        }
        print
      }
    ' "$manifest" > "$tmp_manifest"
    mv "$tmp_manifest" "$manifest"
  else
    printf "%s\n" "$new_line" >> "$manifest"
  fi
  echo "updated manifest: $manifest"
fi

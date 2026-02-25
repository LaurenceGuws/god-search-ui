#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

README="README.md"
DOC="docs/operations/CONTROL_PLANE.md"
RUNBOOK="docs/operations/TROUBLESHOOTING_RUNBOOK.md"
test -f "$README"
test -f "$DOC"
test -f "$RUNBOOK"

require() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! rg -n --fixed-strings -- "$pattern" "$file" >/dev/null; then
    echo "missing ${label}: ${pattern}" >&2
    echo "  file: ${file}" >&2
    exit 1
  fi
}

for cmd in \
  'god-search-ui --ctl --help' \
  'god-search-ui --ctl ping' \
  'god-search-ui --ctl summon' \
  'god-search-ui --ctl hide' \
  'god-search-ui --ctl toggle' \
  'god-search-ui --ctl version' \
  'god-search-ui --ctl shell_health'
do
  require "$README" "$cmd" "README ctl command"
  require "$DOC" "$cmd" "CONTROL_PLANE ctl command"
done

require "$README" 'docs/operations/CONTROL_PLANE.md' 'README control-plane reference'
require "$README" 'docs/operations/CONTROL_PLANE_SMOKE.md' 'README control-plane smoke reference'
require "$DOC" '## Exit Codes' 'CONTROL_PLANE exit codes section'
require "$DOC" '--print-shell-health' 'CONTROL_PLANE health flow reference'
require "$DOC" 'docs/operations/CONTROL_PLANE_SMOKE.md' 'CONTROL_PLANE smoke reference'
require "$RUNBOOK" 'scripts/control_plane_smoke.sh' 'RUNBOOK control-plane smoke reference'
require "$RUNBOOK" 'god-search-ui --ctl ping' 'RUNBOOK ctl ping reference'

echo "control-plane docs contract checks passed"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BIN="${BIN:-./zig-out/bin/god_search_ui}"
DAEMON_LOG="$HOME/.local/state/god-search-ui/daemon.log"
OUT_CSV="${OUT_CSV:-/tmp/god-search-ui-ram-baseline.csv}"
OUT_LOG="${OUT_LOG:-/tmp/god-search-ui-ram-daemon-log.txt}"
QUERY_DELAY_SEC="${QUERY_DELAY_SEC:-10}"
CLEAR_DELAY_SEC="${CLEAR_DELAY_SEC:-10}"

if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  echo "run ./re-run.sh first" >&2
  exit 1
fi

echo "phase,pid,vmrss_kb,vmhwm_kb,vmsize_kb,pss_kb,query,ui_visible,timestamp" >"$OUT_CSV"
echo "[info] ram audit log: $OUT_LOG"

collect() {
  local phase="$1"
  local query="$2"
  local visible="$3"
  local pid="$4"

  local vmrss
  local vmhwm
  local vmsize
  local pss
  local query_escaped
  vmrss="$(awk '/VmRSS:/ {print $2}' "/proc/$pid/status")"
  vmhwm="$(awk '/VmHWM:/ {print $2}' "/proc/$pid/status")"
  vmsize="$(awk '/VmSize:/ {print $2}' "/proc/$pid/status")"
  pss="$(awk '/^Pss:/ {print $2}' "/proc/$pid/smaps_rollup" || true)"
  [[ -n "$pss" ]] || pss=0
  query_escaped="${query//\"/\"\"}"

  printf '%s,%s,%s,%s,%s,%s,"%s",%d,"%s"\n' \
    "$phase" \
    "$pid" \
    "${vmrss:-0}" \
    "${vmhwm:-0}" \
    "${vmsize:-0}" \
    "$pss" \
    "$query_escaped" \
    "$visible" \
    "$(date --iso-8601=seconds)" \
    >>"$OUT_CSV"
}

emit_phase_log() {
  local phase="$1"
  echo "===== ${phase} $(date --iso-8601=seconds) =====" >>"$OUT_LOG"
  local tail_lines="$2"
  local current_lines
  current_lines="$(wc -l < "$DAEMON_LOG")"
  if [[ "$tail_lines" -lt "$current_lines" ]]; then
    sed -n "$((tail_lines + 1)),${current_lines}p" "$DAEMON_LOG" >>"$OUT_LOG"
  fi
  sed -n '$p' "$DAEMON_LOG" >>"$OUT_LOG"
  echo >>"$OUT_LOG"
  echo "$current_lines"
}

cleanup() {
  if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
    if [[ -n "${KEEP_DAEMON:-}" ]]; then
      :
    else
      pkill -f "$BIN --ui-daemon" 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT

rm -f "$DAEMON_LOG"

cat >"$OUT_LOG" <<EOF
$(date --iso-8601=seconds) ram audit started
EOF

./re-run.sh >/tmp/ram-audit-re-run.log 2>&1
sleep 1

PID="$(pgrep -f "$BIN --ui-daemon" | head -n 1 || true)"
if [[ -z "$PID" ]]; then
  echo "failed to find running daemon process" >&2
  echo "check /tmp/ram-audit-re-run.log" >&2
  cat /tmp/ram-audit-re-run.log >&2
  exit 1
fi

tail_line="0"

tail_line="$(emit_phase_log "startup" "$tail_line")"
collect "startup" "" 1 "$PID"

echo "GUI started. Enter '& import' in the launcher."
echo "First query snapshot starts in ${QUERY_DELAY_SEC}s."
sleep "$QUERY_DELAY_SEC"
tail_line="$(emit_phase_log "after_query" "$tail_line")"
collect "after_query" "& import" 1 "$PID"

echo "Clear query now (backspace to empty)."
echo "Clear-state snapshot starts in ${CLEAR_DELAY_SEC}s."
sleep "$CLEAR_DELAY_SEC"
tail_line="$(emit_phase_log "after_clear" "$tail_line")"
collect "after_clear" "" 1 "$PID"

"$BIN" --ctl hide >/dev/null 2>&1 || true
sleep 0.4
tail_line="$(emit_phase_log "after_hide" "$tail_line")"
collect "after_hide" "" 0 "$PID"

"$BIN" --ctl summon >/dev/null 2>&1 || true
sleep 0.4
tail_line="$(emit_phase_log "after_reopen" "$tail_line")"
collect "after_reopen" "" 1 "$PID"

cat "$DAEMON_LOG" >>"$OUT_LOG"

echo "ram audit complete"
echo "csv: $OUT_CSV"
echo "daemon log: $OUT_LOG"

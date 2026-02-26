#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BIN="${BIN:-./zig-out/bin/god_search_ui}"
if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  echo "build with: zig build -Doptimize=ReleaseFast -Denable_gtk=true -Denable_lua_config=true -Denable_layer_shell=true" >&2
  exit 1
fi

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "wm event smoke skipped (WAYLAND_DISPLAY not set)"
  exit 0
fi
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  echo "wm event smoke skipped (HYPRLAND_INSTANCE_SIGNATURE not set)"
  exit 0
fi
if ! command -v hyprctl >/dev/null 2>&1; then
  echo "wm event smoke skipped (hyprctl not found)"
  exit 0
fi
display_probe="$("$BIN" --print-outputs 2>/dev/null || true)"
if [[ "$display_probe" == "no display"* ]]; then
  echo "wm event smoke skipped (display unavailable)"
  exit 0
fi

tmp_dir="$(mktemp -d)"
log_file="$tmp_dir/wm-event-smoke.log"
cleanup() {
  pkill -x god_search_ui 2>/dev/null || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

pkill -x god_search_ui 2>/dev/null || true

GOD_SEARCH_WM_EVENT_LOG_EVERY=1 "$BIN" --ui-daemon >"$log_file" 2>&1 &
i=0
quick_ping() {
  ( timeout 0.35s "$BIN" --ctl ping >/dev/null 2>&1 ) 2>/dev/null
}
until quick_ping; do
  i=$((i + 1))
  if (( i >= 40 )); then
    break
  fi
  sleep 0.1
done
if ! quick_ping; then
  echo "wm event smoke skipped (daemon unavailable in current session)"
  tail -n 20 "$log_file" >&2 || true
  exit 0
fi

timeout 2s hyprctl dispatch workspace +1 >/dev/null 2>&1 || true
sleep 0.25
timeout 2s hyprctl dispatch workspace -1 >/dev/null 2>&1 || true
sleep 0.5

stats="$("$BIN" --ctl wm_event_stats 2>/dev/null || true)"
if [[ -z "$stats" ]]; then
  echo "wm event smoke failed: wm_event_stats query returned empty output" >&2
  tail -n 80 "$log_file" >&2 || true
  exit 3
fi
if [[ "$stats" != *"events="* || "$stats" != *"scheduled="* ]]; then
  echo "wm event smoke failed: unexpected wm_event_stats output: $stats" >&2
  tail -n 80 "$log_file" >&2 || true
  exit 4
fi
if [[ "$stats" == *"events=0"* ]]; then
  echo "wm event smoke failed: wm_event_stats shows zero events: $stats" >&2
  tail -n 80 "$log_file" >&2 || true
  exit 5
fi

echo "wm event refresh smoke passed"
echo "wm_event_stats: $stats"
tail -n 20 "$log_file"

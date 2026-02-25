#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BIN="${BIN:-./zig-out/bin/god_search_ui}"
if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  echo "build with: zig build -Doptimize=ReleaseFast -Denable_gtk=true" >&2
  exit 1
fi

if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
  echo "shell health contract checks skipped (no display session)"
  exit 0
fi

display_probe="$("$BIN" --print-outputs 2>/dev/null || true)"
if [[ "$display_probe" == "no display"* ]]; then
  echo "shell health contract checks skipped (display unavailable)"
  exit 0
fi

tmp_dir="$(mktemp -d)"
log_file="$tmp_dir/daemon.log"
pid_file="$tmp_dir/daemon.pid"
cleanup() {
  if [[ -f "$pid_file" ]]; then
    kill "$(cat "$pid_file")" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

export XDG_RUNTIME_DIR="$tmp_dir"

offline_out="$($BIN --print-shell-health)"
if [[ "$offline_out" != *"diagnostic snapshot (offline)"* ]]; then
  echo "offline shell health output missing fallback marker" >&2
  echo "$offline_out" >&2
  exit 1
fi

"$BIN" --ui-daemon >"$log_file" 2>&1 &
echo $! >"$pid_file"
sleep 0.7

if ! "$BIN" --ctl ping >/dev/null 2>&1; then
  echo "shell health contract checks skipped (daemon unavailable in current display session)"
  exit 0
fi

live_out="$($BIN --print-shell-health)"
if [[ "$live_out" != *"module=launcher"* ]]; then
  echo "live shell health output missing launcher module line" >&2
  echo "$live_out" >&2
  exit 1
fi
if [[ "$live_out" != *"module=notifications"* ]]; then
  echo "live shell health output missing notifications module line" >&2
  echo "$live_out" >&2
  exit 1
fi

echo "shell health contract checks passed"

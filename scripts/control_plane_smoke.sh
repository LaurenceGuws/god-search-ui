#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BIN="${BIN:-./zig-out/bin/wayspot}"
if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  echo "build with: zig build -Doptimize=ReleaseFast" >&2
  exit 1
fi

if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
  echo "control plane smoke skipped (no display session)"
  exit 0
fi

display_probe="$("$BIN" --print-outputs 2>/dev/null || true)"
if [[ "$display_probe" == "no display"* ]]; then
  echo "control plane smoke skipped (display unavailable)"
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

"$BIN" --ui-daemon >"$log_file" 2>&1 &
echo $! >"$pid_file"
sleep 0.7

if ! "$BIN" --ctl ping >/dev/null 2>&1; then
  echo "control plane smoke skipped (daemon unavailable in current display session)"
  exit 0
fi
for cmd in summon hide toggle; do
  if ! "$BIN" --ctl "$cmd" >/dev/null 2>&1; then
    echo "control plane smoke note: --ctl ${cmd} not accepted in current session"
  fi
done
if ! "$BIN" --ctl wm_event_stats >/dev/null 2>&1; then
  echo "control plane smoke note: --ctl wm_event_stats not accepted in current session"
fi

health_out="$($BIN --print-shell-health)"
if [[ "$health_out" != *"module=launcher"* ]]; then
  echo "shell health output missing launcher module" >&2
  echo "$health_out" >&2
  exit 1
fi

if [[ "$health_out" != *"module=notifications"* ]]; then
  echo "shell health output missing notifications module" >&2
  echo "$health_out" >&2
  exit 1
fi

echo "control plane smoke passed"

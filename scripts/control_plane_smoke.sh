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
  echo "control plane smoke skipped (no display session)"
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

"$BIN" --ctl ping >/dev/null
"$BIN" --ctl summon >/dev/null
"$BIN" --ctl hide >/dev/null
"$BIN" --ctl toggle >/dev/null

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

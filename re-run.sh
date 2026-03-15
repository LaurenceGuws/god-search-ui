#!/usr/bin/env bash
set -euo pipefail

# Rebuild + restart daemon + summon UI in one step.
# Keep runtime/build flags in one place below (or override via env vars).
#
# Optional overrides:
#   RERUN_BUILD_FLAGS="-Doptimize=ReleaseFast"
#   RERUN_DAEMON_ARGS="--ui-daemon"
#   RERUN_BIN="./zig-out/bin/wayspot"
#   RERUN_LOG="$HOME/.local/state/wayspot/daemon.log"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

: "${RERUN_BUILD_FLAGS:=-Doptimize=ReleaseFast}"
: "${RERUN_DAEMON_ARGS:=--ui-daemon}"
: "${RERUN_BIN:=./zig-out/bin/wayspot}"
: "${RERUN_LOG:=$HOME/.local/state/wayspot/daemon.log}"
: "${RERUN_KILL_TARGET:=true}"

if [[ -f "$ROOT_DIR/.rerun.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.rerun.env"
fi

read -r -a build_flags <<<"$RERUN_BUILD_FLAGS"
read -r -a daemon_args <<<"$RERUN_DAEMON_ARGS"

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
sock="$runtime_dir/wayspot.sock"

mkdir -p "$(dirname "$RERUN_LOG")"

echo "[re-run] building: zig build ${build_flags[*]}"
zig build "${build_flags[@]}"

if [[ "$RERUN_KILL_TARGET" == "true" ]]; then
    echo "[re-run] stopping existing daemon variants (--ui-daemon)"
    mapfile -t matched_pids < <(
        pgrep -a -f 'wayspot.*(--ui-daemon)' | awk '{print $1}' || true
    )
    if ((${#matched_pids[@]} == 0)); then
        echo "[re-run] no existing daemon found"
    else
        echo "[re-run] killing: ${matched_pids[*]}"
    fi
    for pid in "${matched_pids[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
else
    echo "[re-run] skipping daemon kill (RERUN_KILL_TARGET=false)"
fi
rm -f "$sock" 2>/dev/null || true

echo "[re-run] starting daemon: $RERUN_BIN ${daemon_args[*]}"
nohup "$RERUN_BIN" "${daemon_args[@]}" >"$RERUN_LOG" 2>&1 &
disown

echo "[re-run] waiting for control socket"
for _ in {1..30}; do
  if "$RERUN_BIN" --ctl ping >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

echo "[re-run] summoning UI"
"$RERUN_BIN" --ctl summon

echo "[re-run] done"
echo "[re-run] daemon log: $RERUN_LOG"

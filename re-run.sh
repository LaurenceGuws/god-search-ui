#!/usr/bin/env bash
set -euo pipefail

# Rebuild + restart daemon + summon UI in one step.
# Keep runtime/build flags in one place below (or override via env vars).
#
# Optional overrides:
#   RERUN_BUILD_FLAGS="-Doptimize=ReleaseFast -Denable_gtk=true -Denable_lua_config=true -Denable_layer_shell=true"
#   RERUN_SURFACE_MODE="layer-shell"
#   RERUN_DAEMON_ARGS="--ui-daemon"
#   RERUN_BIN="./zig-out/bin/god_search_ui"
#   RERUN_LOG="$HOME/.local/state/god-search-ui/daemon.log"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

: "${RERUN_BUILD_FLAGS:=-Doptimize=ReleaseFast -Denable_gtk=true -Denable_lua_config=true -Denable_layer_shell=true}"
: "${RERUN_SURFACE_MODE:=layer-shell}"
: "${RERUN_DAEMON_ARGS:=--ui-daemon}"
: "${RERUN_BIN:=./zig-out/bin/god_search_ui}"
: "${RERUN_LOG:=$HOME/.local/state/god-search-ui/daemon.log}"

if [[ -f "$ROOT_DIR/.rerun.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.rerun.env"
fi

read -r -a build_flags <<<"$RERUN_BUILD_FLAGS"
read -r -a daemon_args <<<"$RERUN_DAEMON_ARGS"

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
sock="$runtime_dir/god-search-ui.sock"

mkdir -p "$(dirname "$RERUN_LOG")"

echo "[re-run] building: zig build ${build_flags[*]}"
zig build "${build_flags[@]}"

echo "[re-run] stopping existing daemon"
pkill -x god_search_ui 2>/dev/null || true
rm -f "$sock" 2>/dev/null || true

echo "[re-run] starting daemon: GOD_SEARCH_SURFACE_MODE=$RERUN_SURFACE_MODE $RERUN_BIN ${daemon_args[*]}"
nohup env GOD_SEARCH_SURFACE_MODE="$RERUN_SURFACE_MODE" "$RERUN_BIN" "${daemon_args[@]}" >"$RERUN_LOG" 2>&1 &
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

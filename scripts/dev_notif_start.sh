#!/usr/bin/env bash
set -euo pipefail

BIN="${BIN:-./zig-out/bin/god-search-ui}"
MODE="${1:-start}"
WAIT_SECS="${WAIT_SECS:-6}"
LOG_PATH="${LOG_PATH:-$HOME/.local/state/god-search-ui/daemon.log}"
MASK_SWAYNC="${MASK_SWAYNC:-0}"

usage() {
  cat <<'USAGE'
Usage: scripts/dev_notif_start.sh [start|status|stop] [--mask-swaync]

Modes:
  start         Stop competing daemons, start god-search-ui --ui-daemon, wait for bus ownership.
  status        Print current org.freedesktop.Notifications owner info.
  stop          Stop god-search-ui daemon.

Options:
  --mask-swaync  Mask swaync.service via systemd user to prevent auto-activation takeover.

Environment:
  BIN            Path to god-search-ui binary (default: ./zig-out/bin/god-search-ui)
  WAIT_SECS      Max seconds to wait for bus ownership (default: 6)
  LOG_PATH       Daemon log path (default: ~/.local/state/god-search-ui/daemon.log)
  MASK_SWAYNC    Same as --mask-swaync when set to 1
USAGE
}

bus_info() {
  gdbus call --session \
    --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.GetServerInformation 2>/dev/null || true
}

wait_for_owner() {
  local deadline
  deadline=$((SECONDS + WAIT_SECS))
  while (( SECONDS <= deadline )); do
    local info
    info="$(bus_info)"
    if [[ "$info" == *"god-search-ui"* ]]; then
      echo "$info"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

mask_swaync() {
  systemctl --user daemon-reload || true
  systemctl --user mask --now swaync.service >/dev/null 2>&1 || true
}

stop_competitors() {
  systemctl --user stop swaync.service swaync.socket >/dev/null 2>&1 || true
  pkill -x swaync >/dev/null 2>&1 || true
}

start_daemon() {
  mkdir -p "$(dirname "$LOG_PATH")"
  pkill -x god-search-ui >/dev/null 2>&1 || true
  nohup "$BIN" --ui-daemon >"$LOG_PATH" 2>&1 & disown
}

if [[ "$MODE" == "--help" || "$MODE" == "-h" || "$MODE" == "help" ]]; then
  usage
  exit 0
fi

if [[ "${2:-}" == "--mask-swaync" || "$MODE" == "--mask-swaync" || "$MASK_SWAYNC" == "1" ]]; then
  MASK_SWAYNC=1
  if [[ "$MODE" == "--mask-swaync" ]]; then
    MODE="start"
  fi
fi

case "$MODE" in
  start)
    [[ -x "$BIN" ]] || { echo "error: missing binary at $BIN" >&2; exit 1; }
    if [[ "$MASK_SWAYNC" == "1" ]]; then
      echo "[dev-notif-start] masking swaync.service"
      mask_swaync
    fi
    echo "[dev-notif-start] stopping competing notification daemons"
    stop_competitors
    echo "[dev-notif-start] starting god-search-ui daemon"
    start_daemon
    if info="$(wait_for_owner)"; then
      echo "[dev-notif-start] owner ready: $info"
      echo "[dev-notif-start] test with: notify-send -a \"god-search-ui\" \"smoke\" \"hello\""
      exit 0
    fi
    echo "[dev-notif-start] ERROR: bus ownership did not stabilize within ${WAIT_SECS}s" >&2
    echo "[dev-notif-start] current owner: $(bus_info)" >&2
    echo "[dev-notif-start] recent log tail:" >&2
    tail -n 80 "$LOG_PATH" >&2 || true
    exit 2
    ;;
  status)
    echo "[dev-notif-start] owner: $(bus_info)"
    ;;
  stop)
    pkill -x god-search-ui >/dev/null 2>&1 || true
    echo "[dev-notif-start] stopped god-search-ui"
    ;;
  *)
    usage
    exit 1
    ;;
esac

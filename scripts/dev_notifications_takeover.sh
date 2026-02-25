#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-takeover}"
BIN="${BIN:-./zig-out/bin/god_search_ui}"
SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/god-search-ui.sock"

usage() {
    cat <<'USAGE'
Usage: scripts/dev_notifications_takeover.sh [takeover|restore|status]

Modes:
  takeover  Stop swaync, start god-search-ui --ui-daemon, verify bus owner.
  restore   Kill god-search-ui daemon and restart swaync service/socket.
  status    Print current org.freedesktop.Notifications owner info.
USAGE
}

bus_info() {
    gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.GetServerInformation 2>/dev/null || true
}

case "$MODE" in
    takeover)
        echo "[dev-notify] stopping swaync"
        systemctl --user stop swaync.service swaync.socket 2>/dev/null || true
        pkill -x swaync 2>/dev/null || true

        if "$BIN" --ctl ping >/dev/null 2>&1; then
            echo "[dev-notify] god-search-ui daemon already running"
        else
            echo "[dev-notify] starting god-search-ui --ui-daemon"
            "$BIN" --ui-daemon >/tmp/god-search-ui-dev-notify.log 2>&1 &
            sleep 0.8
        fi

        if ! "$BIN" --ctl ping >/dev/null 2>&1; then
            echo "[dev-notify] ERROR: control ping failed"
            echo "[dev-notify] tail /tmp/god-search-ui-dev-notify.log"
            tail -n 50 /tmp/god-search-ui-dev-notify.log 2>/dev/null || true
            exit 1
        fi

        INFO="$(bus_info)"
        echo "[dev-notify] bus owner: ${INFO:-<none>}"
        if [[ "$INFO" != *"god-search-ui"* ]]; then
            echo "[dev-notify] WARNING: bus owner is not god-search-ui"
            exit 2
        fi

        echo "[dev-notify] takeover complete"
        ;;
    restore)
        echo "[dev-notify] stopping god-search-ui daemon"
        pkill -x god_search_ui 2>/dev/null || true
        rm -f "$SOCKET_PATH" 2>/dev/null || true

        echo "[dev-notify] starting swaync"
        systemctl --user start swaync.socket swaync.service 2>/dev/null || true
        INFO="$(bus_info)"
        echo "[dev-notify] bus owner: ${INFO:-<none>}"
        ;;
    status)
        INFO="$(bus_info)"
        echo "[dev-notify] bus owner: ${INFO:-<none>}"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac

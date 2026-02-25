#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-takeover}"
BIN="${BIN:-./zig-out/bin/god_search_ui}"
SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/god-search-ui.sock"

usage() {
    cat <<'USAGE'
Usage: scripts/dev_notifications_takeover.sh [takeover|restore|status|smoke]

Modes:
  takeover  Stop swaync, start god-search-ui --ui-daemon, verify bus owner.
  restore   Kill god-search-ui daemon and restart swaync service/socket.
  status    Print current org.freedesktop.Notifications owner info.
  smoke     Run quick replace/close/timeout signal checks against current owner.
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
    smoke)
        echo "[dev-notify] running smoke checks"
        INFO="$(bus_info)"
        if [[ "$INFO" != *"god-search-ui"* ]]; then
            echo "[dev-notify] ERROR: org.freedesktop.Notifications is not owned by god-search-ui"
            echo "[dev-notify] current owner: ${INFO:-<none>}"
            exit 3
        fi

        ID1="$(notify-send -p "god-search-ui smoke" "replace-one")"
        ID2="$(notify-send -p -r "$ID1" "god-search-ui smoke" "replace-two")"
        echo "[dev-notify] replace ids: first=$ID1 second=$ID2"
        if [[ "$ID1" != "$ID2" ]]; then
            echo "[dev-notify] ERROR: replace-id mismatch"
            exit 4
        fi

        ACTION_OUT="$(gdbus call --session \
            --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications \
            --method org.freedesktop.Notifications.Notify \
            app 0 '' 'god-search-ui smoke action' 'click action button to emit ActionInvoked' \
            "['default','Open']" "{}" 5000)"
        echo "[dev-notify] action notify: $ACTION_OUT"
        if [[ "$ACTION_OUT" != *"uint32"* ]]; then
            echo "[dev-notify] ERROR: action notify call failed"
            exit 7
        fi

        timeout 6 dbus-monitor "interface='org.freedesktop.Notifications'" >/tmp/god-search-ui-notify-smoke.log 2>&1 &
        MON_PID=$!
        sleep 0.4
        gdbus call --session \
            --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications \
            --method org.freedesktop.Notifications.CloseNotification \
            "$ID1" >/dev/null
        notify-send -t 900 "god-search-ui smoke" "timeout-check"
        sleep 2
        kill "$MON_PID" 2>/dev/null || true
        wait "$MON_PID" 2>/dev/null || true

        echo "[dev-notify] signal extract:"
        rg -n "member=NotificationClosed|uint32 [0-9]+" /tmp/god-search-ui-notify-smoke.log | tail -n 10 || true
        rg -q "uint32 3" /tmp/god-search-ui-notify-smoke.log || { echo "[dev-notify] ERROR: missing reason=3 close signal"; exit 5; }
        rg -q "uint32 1" /tmp/god-search-ui-notify-smoke.log || { echo "[dev-notify] ERROR: missing reason=1 timeout signal"; exit 6; }
        echo "[dev-notify] smoke checks passed"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac

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
  smoke     Run replace/markup/persistent signal checks against current owner.
USAGE
}

bus_info() {
    gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.GetServerInformation 2>/dev/null || true
}

extract_uint() {
    printf '%s\n' "${1:-}" | rg -o -m1 '[0-9]+' | head -n1 || true
}

require_uint() {
    local value="$1"
    local label="$2"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "[dev-notify] ERROR: expected numeric id for $label, got: ${value:-<empty>}"
        exit 9
    fi
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
        CFG_OUT="$("$BIN" --print-config 2>/dev/null || true)"
        if [[ "$CFG_OUT" != *"show_close_button"* || "$CFG_OUT" != *"show_dbus_actions"* ]]; then
            echo "[dev-notify] ERROR: print-config missing notifications action policy fields"
            exit 10
        fi

        CAPS="$(gdbus call --session \
            --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications \
            --method org.freedesktop.Notifications.GetCapabilities)"
        echo "[dev-notify] capabilities: $CAPS"
        if [[ "$CAPS" != *"body-markup"* ]]; then
            echo "[dev-notify] ERROR: missing body-markup capability"
            exit 8
        fi

        ID1_RAW="$(notify-send -p "god-search-ui smoke" "replace-one" || true)"
        ID1="$(extract_uint "$ID1_RAW")"
        require_uint "$ID1" "replace first"

        ID2_RAW="$(notify-send -p -r "$ID1" "god-search-ui smoke" "replace-two" || true)"
        ID2="$(extract_uint "$ID2_RAW")"
        require_uint "$ID2" "replace second"
        echo "[dev-notify] replace ids: first=$ID1 second=$ID2"
        if [[ "$ID1" != "$ID2" ]]; then
            echo "[dev-notify] ERROR: replace-id mismatch"
            exit 4
        fi

        MARKUP_ID_RAW="$(notify-send -p \
            -a "god-search-ui" \
            -u normal \
            -t 4000 \
            "god-search-ui markup smoke" \
            "<b>Markup</b> body\nSecond line" || true)"
        MARKUP_ID="$(extract_uint "$MARKUP_ID_RAW")"
        require_uint "$MARKUP_ID" "markup notification"
        echo "[dev-notify] markup notify id=$MARKUP_ID"

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

        timeout 8 dbus-monitor "interface='org.freedesktop.Notifications'" >/tmp/god-search-ui-notify-smoke.log 2>&1 &
        MON_PID=$!
        sleep 0.4
        gdbus call --session \
            --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications \
            --method org.freedesktop.Notifications.CloseNotification \
            "$ID1" >/dev/null

        PERSIST_RAW="$(notify-send -p -a "god-search-ui" -u low -t 0 "persistent test" "Should stay until dismissed" || true)"
        PERSIST_ID="$(extract_uint "$PERSIST_RAW")"
        require_uint "$PERSIST_ID" "persistent notification"
        echo "[dev-notify] persistent notify id=$PERSIST_ID"

        sleep 0.5
        gdbus call --session \
            --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications \
            --method org.freedesktop.Notifications.CloseNotification \
            "$PERSIST_ID" >/dev/null

        notify-send -t 900 "god-search-ui smoke" "timeout-check"
        sleep 2.2
        kill "$MON_PID" 2>/dev/null || true
        wait "$MON_PID" 2>/dev/null || true

        echo "[dev-notify] signal extract:"
        rg -n "member=NotificationClosed|uint32 [0-9]+" /tmp/god-search-ui-notify-smoke.log | tail -n 10 || true
        rg -q "uint32 3" /tmp/god-search-ui-notify-smoke.log || { echo "[dev-notify] ERROR: missing reason=3 close signal"; exit 5; }
        rg -q "uint32 1" /tmp/god-search-ui-notify-smoke.log || { echo "[dev-notify] ERROR: missing reason=1 timeout signal"; exit 6; }
        echo "[dev-notify] note: click action button during smoke to observe ActionInvoked in dbus-monitor output"
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

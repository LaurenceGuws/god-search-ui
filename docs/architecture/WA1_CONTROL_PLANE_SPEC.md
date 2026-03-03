Status: active
Owner: shell
Last-Reviewed: 2026-03-03
Canonical: yes

# WA-1.1 Control Plane Spec

This spec defines the local control plane used by the daemon and CLI.

## Scope

In-scope:
- local Unix domain socket server in daemon mode
- request/response protocol for control commands
- CLI behavior (`--ui` path uses socket first)
- deterministic exit codes and failure handling

Out-of-scope:
- D-Bus integration
- auth beyond local filesystem ownership
- streaming/event subscriptions

## Socket

- Path: `$XDG_RUNTIME_DIR/god-search-ui.sock`
- Fallback when `XDG_RUNTIME_DIR` is missing: `/tmp/god-search-ui-$UID.sock`
- Type: Unix stream socket
- Ownership: current user only
- Recommended mode: `0600`

Startup rules:
1. Daemon attempts bind.
2. If bind fails due to existing socket, daemon tries connect probe.
3. If probe succeeds, daemon exits with "already running".
4. If probe fails, daemon removes stale socket and retries bind once.

Shutdown rules:
1. Close listener.
2. Unlink socket path.

## Wire Protocol

Transport: UTF-8 JSON, one request per connection, one response, then close.

Request schema:
```json
{
  "v": 1,
  "cmd": "ping|summon|hide|toggle|version|shell_health|wm_event_stats|refresh|query-mode|preview-mode|help"
}
```

Response schema:
```json
{
  "ok": true,
  "code": "ok",
  "message": "human readable"
}
```

Error response example:
```json
{
  "ok": false,
  "code": "bad_request",
  "message": "unknown command"
}
```

## Command Semantics

1. `ping`: health probe.
2. `version`: returns daemon version in `message`.
3. `summon`: show/focus launcher window.
4. `hide`: hide launcher window.
5. `toggle`: toggle visible/hidden state.
6. `shell_health`: returns compact module-health payload.
7. `wm_event_stats`: returns compact WM event-refresh counters.
8. `refresh`: force shell state refresh.
9. `query-mode`: print current mode.
10. `preview-mode`: print current preview mode state.
11. `help`: print control command help.

## CLI Behavior

`god-search-ui --ui`:
1. Attempt socket connect and send `summon`.
2. If daemon responds `ok`, exit immediately with code `0`.
3. If connect fails, continue local UI startup path.

Dedicated control commands:
- `god-search-ui --ctl ping`
- `god-search-ui --ctl summon`
- `god-search-ui --ctl hide`
- `god-search-ui --ctl toggle`
- `god-search-ui --ctl version`
- `god-search-ui --ctl shell_health`
- `god-search-ui --ctl wm_event_stats`
- `god-search-ui --ctl refresh`
- `god-search-ui --ctl query-mode`
- `god-search-ui --ctl preview-mode`
- `god-search-ui --ctl help`

## Exit Codes

- `0`: success
- `10`: daemon not reachable
- `13`: bad CLI arguments

## Notes

- Keep server single-threaded.
- Keep request buffer bounded (for example 4 KiB).
- Keep protocol versioned from day one (`v` field).
- Keep control-plane code under `src/ipc/`.

Status: active
Owner: shell
Last-Reviewed: 2026-02-25
Canonical: yes

# WA-1.1 Control Plane Spec (Unix Socket MVP)

This spec defines the first shell-daemon control plane slice for summon/hide control without process relaunch dependence.

## Scope

In-scope:
- local Unix domain socket server in daemon mode
- request/response protocol for shell control commands
- CLI client behavior (`--ui` path uses socket first)
- deterministic exit codes and failure handling

Out-of-scope:
- D-Bus integration
- auth/permissions beyond local filesystem ownership
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

## Wire Protocol (MVP)

Transport: UTF-8 JSON, one request per connection, one response, then close.

Request schema:
```json
{
  "v": 1,
  "cmd": "ping|summon|hide|toggle|version"
}
```

Response schema:
```json
{
  "ok": true,
  "code": "ok",
  "message": "human readable",
  "data": {}
}
```

Error response example:
```json
{
  "ok": false,
  "code": "bad_request",
  "message": "unknown command",
  "data": {}
}
```

Command semantics:
1. `ping`
   - health probe
   - side effects: none
2. `version`
   - returns app version/build metadata in `data`
3. `summon`
   - show/focus launcher window
4. `hide`
   - hide launcher window
5. `toggle`
   - toggle visible/hidden state

## CLI Behavior

`god-search-ui --ui`:
1. Attempt socket connect and send `summon`.
2. If daemon responds `ok`, exit immediately with code `0`.
3. If connect fails (`ENOENT`/`ECONNREFUSED`/timeout), spawn UI daemon process path as fallback.
4. Fallback instance should continue normal activate behavior.

Dedicated control commands (optional in same slice if simple):
- `god-search-ui --ctl ping`
- `god-search-ui --ctl hide`
- `god-search-ui --ctl toggle`

## Exit Codes

- `0`: success
- `10`: daemon not reachable
- `11`: protocol error / invalid response
- `12`: command rejected (known command, failed action)
- `13`: bad CLI arguments
- `14`: internal runtime error

## Timeouts

- client connect timeout: 100ms target, 250ms hard max
- request round-trip timeout: 200ms target, 500ms hard max

On timeout, client treats daemon as unavailable and uses fallback behavior where applicable.

## Logging

Server logs:
- listener start/stop
- command received (`cmd`, result)
- stale socket cleanup decisions

Client logs:
- connect success/failure
- fallback to spawn reason

## Minimal Test Matrix

1. `ping` against running daemon returns `ok`.
2. `summon` against running hidden daemon returns `ok` and window visible.
3. `hide` against visible daemon returns `ok` and window hidden.
4. stale socket file is cleaned and daemon starts successfully.
5. malformed JSON request returns `ok=false`, `code=bad_request`.
6. unknown command returns `ok=false`, `code=bad_request`.
7. client timeout path returns exit `10` and does not hang.
8. repeated summon spam does not create multiple daemons.

## Implementation Notes

- Keep server single-threaded in MVP; one connection at a time is enough.
- Use small bounded read buffer for requests (e.g. 4 KiB).
- Keep protocol versioned from day one (`v` field).
- Place control-plane code under a dedicated module path (recommended: `src/ipc/`).

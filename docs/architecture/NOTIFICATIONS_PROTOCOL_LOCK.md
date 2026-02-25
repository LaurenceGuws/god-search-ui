Status: active
Owner: shell
Last-Reviewed: 2026-02-25
Canonical: yes

# Notifications Protocol Lock (From Vendor Spec)

Source artifacts:
- `docs/vendor/notifications/notification-protocol.html`
- `docs/vendor/notifications/notification-hints.html`
- `docs/vendor/notifications/notification-markup.html`
- Publication/version from vendor index: freedesktop notification spec v1.3 (18 Aug 2024)

This file is an implementation lock for coding tasks. If vendor artifacts change, update this lock before changing daemon behavior.

## D-Bus Interface

- Service: `org.freedesktop.Notifications`
- Interface: `org.freedesktop.Notifications`
- Object path (implementation convention): `/org/freedesktop/Notifications`

## Locked Method Signatures

1. `GetCapabilities() -> as`
2. `Notify(app_name:s, replaces_id:u, app_icon:s, summary:s, body:s, actions:as, hints:a{sv}, expire_timeout:i) -> u`
3. `CloseNotification(id:u) -> ()`
4. `GetServerInformation() -> (name:s, vendor:s, version:s, spec_version:s)`

## Locked Signal Signatures

1. `NotificationClosed(id:u, reason:u)`
2. `ActionInvoked(id:u, action_key:s)`
3. `ActivationToken(id:u, activation_token:s)` (spec includes it; emission is conditional)

## NotificationClosed Reason Codes

1. `1`: expired
2. `2`: dismissed by user
3. `3`: closed via `CloseNotification`
4. `4`: undefined/reserved reasons

## Capabilities Contract (GetCapabilities)

MVP target capabilities to report only when actually implemented:
- `actions`
- `body`
- `body-markup`

Defer (report only once implemented):
- `action-icons`
- `body-hyperlinks`
- `body-images`
- `icon-static`
- `icon-multi`
- `persistence`
- `sound`

Important spec constraint:
- `icon-static` and `icon-multi` are mutually exclusive.

## Hints Contract (MVP Handling)

Standard hints exist, but server support is optional. MVP behavior:
1. Parse known hints if present:
   - `urgency` (BYTE)
   - `category` (STRING)
   - `desktop-entry` (STRING)
   - `transient` (BOOLEAN)
   - `resident` (BOOLEAN)
2. Ignore unknown/unsupported hints without error.
3. Keep `a{sv}` type handling strict.

## Markup Contract (MVP)

Spec-supported markup subset in body:
- `<b>`, `<i>`, `<u>`, `<a href=\"...\">`, `<img .../>`

MVP behavior:
1. Accept markup input in `body`.
2. If markup rendering is not implemented for a tag, sanitize/strip safely.
3. Never attempt full HTML rendering.

## Explicit MVP Deferrals

1. `ActivationToken` emission if no compositor activation-token source is available yet.
2. Image payload rendering (`image-data`/`icon_data`) until popup renderer supports it safely.
3. Sound hints (`sound-file`, `sound-name`, `suppress-sound`) until audio policy exists.

## Start Gate

Before notifications implementation starts:
1. Method/signal signatures above must match code exactly.
2. Every deferred feature must be documented in PR notes.

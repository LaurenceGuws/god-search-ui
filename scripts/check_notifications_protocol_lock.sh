#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="docs/architecture/NOTIFICATIONS_PROTOCOL_LOCK.md"
PROTO_FILE="docs/vendor/notifications/notification-protocol.txt"

test -f "$LOCK_FILE"
test -f "$PROTO_FILE"

# Core methods must be present in vendor protocol.
for method in GetCapabilities Notify CloseNotification GetServerInformation; do
  rg -q --fixed-strings "$method" "$PROTO_FILE"
done

# Core signals must be present in vendor protocol.
for signal in NotificationClosed ActionInvoked ActivationToken; do
  rg -q --fixed-strings "$signal" "$PROTO_FILE"
done

# Lock doc must include same method and signal identifiers.
for token in GetCapabilities Notify CloseNotification GetServerInformation NotificationClosed ActionInvoked ActivationToken; do
  rg -q --fixed-strings "$token" "$LOCK_FILE"
done

# Close reason codes from protocol must be represented in lock doc.
for code in "1" "2" "3" "4"; do
  rg -q --fixed-strings "\`${code}\`:" "$LOCK_FILE"
done

echo "notifications protocol lock check passed"

#!/usr/bin/env bash
set -euo pipefail

# Keep all Zig caches inside the project for sandboxed runs.
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-.zig-global-cache}"

usage() {
    cat <<'EOF'
Usage: scripts/dev.sh <command>

Commands:
  fmt      Run zig fmt
  build    Run zig build
  test     Run zig test (via zig build test)
  check    Run fmt + build + test
EOF
}

cmd="${1:-check}"

case "$cmd" in
fmt)
    zig fmt src build.zig
    ;;
build)
    zig build
    ;;
test)
    zig build test
    ;;
check)
    zig fmt --check src build.zig
    zig build
    zig build test
    ;;
*)
    usage
    exit 1
    ;;
esac

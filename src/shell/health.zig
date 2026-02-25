const std = @import("std");
const module_mod = @import("module.zig");

pub fn statusLabel(status: module_mod.HealthStatus) []const u8 {
    return switch (status) {
        .unknown => "unknown",
        .ready => "ready",
        .degraded => "degraded",
        .failed => "failed",
    };
}

pub fn formatEntry(allocator: std.mem.Allocator, entry: module_mod.ModuleHealthEntry) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "module={s} status={s} detail={s}",
        .{ entry.name, statusLabel(entry.health.status), entry.health.detail },
    );
}

test "statusLabel is stable for all health states" {
    try std.testing.expectEqualStrings("unknown", statusLabel(.unknown));
    try std.testing.expectEqualStrings("ready", statusLabel(.ready));
    try std.testing.expectEqualStrings("degraded", statusLabel(.degraded));
    try std.testing.expectEqualStrings("failed", statusLabel(.failed));
}

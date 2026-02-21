const std = @import("std");

pub const Stopwatch = struct {
    start_ns: i128,

    pub fn start() Stopwatch {
        return .{ .start_ns = std.time.nanoTimestamp() };
    }

    pub fn elapsedNs(self: Stopwatch) u64 {
        const now = std.time.nanoTimestamp();
        const diff = now - self.start_ns;
        if (diff <= 0) return 0;
        return @as(u64, @intCast(diff));
    }

    pub fn elapsedMs(self: Stopwatch) f64 {
        return @as(f64, @floatFromInt(self.elapsedNs())) / 1_000_000.0;
    }
};

test "stopwatch returns non-negative elapsed" {
    const sw = Stopwatch.start();
    try std.testing.expect(sw.elapsedNs() >= 0);
}

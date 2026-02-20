const std = @import("std");

pub const Level = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
};

pub const Logger = struct {
    min_level: Level = .info,

    pub fn init(min_level: Level) Logger {
        return .{ .min_level = min_level };
    }

    pub fn enabled(self: Logger, level: Level) bool {
        return @intFromEnum(level) >= @intFromEnum(self.min_level);
    }

    pub fn debug(self: Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.debug, fmt, args);
    }

    pub fn info(self: Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.info, fmt, args);
    }

    pub fn warn(self: Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.warn, fmt, args);
    }

    pub fn err(self: Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.err, fmt, args);
    }

    fn log(self: Logger, comptime level: Level, comptime fmt: []const u8, args: anytype) void {
        if (!self.enabled(level)) return;
        std.debug.print(prefix(level) ++ " " ++ fmt ++ "\n", args);
    }

    fn prefix(comptime level: Level) []const u8 {
        return switch (level) {
            .debug => "[DEBUG]",
            .info => "[INFO]",
            .warn => "[WARN]",
            .err => "[ERROR]",
        };
    }
};

test "enabled respects minimum level ordering" {
    const logger = Logger.init(.warn);
    try std.testing.expect(!logger.enabled(.debug));
    try std.testing.expect(!logger.enabled(.info));
    try std.testing.expect(logger.enabled(.warn));
    try std.testing.expect(logger.enabled(.err));
}

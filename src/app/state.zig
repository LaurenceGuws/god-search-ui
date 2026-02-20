const std = @import("std");

pub const UiMode = enum {
    idle,
    search,
};

pub const AppState = struct {
    mode: UiMode,
    query: []const u8,
    last_error: ?[]const u8,

    pub fn init() AppState {
        return .{
            .mode = .idle,
            .query = "",
            .last_error = null,
        };
    }
};

test "default state starts idle with empty query" {
    const state = AppState.init();
    try std.testing.expectEqual(UiMode.idle, state.mode);
    try std.testing.expectEqualStrings("", state.query);
    try std.testing.expect(state.last_error == null);
}

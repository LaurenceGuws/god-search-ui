const std = @import("std");
const search = @import("../search/mod.zig");
var test_command_capture: ?[]const u8 = null;

pub const ActionsProvider = struct {
    pub fn provider(self: *ActionsProvider) search.Provider {
        return .{
            .name = "actions",
            .context = self,
            .vtable = &.{
                .collect = collect,
                .health = health,
            },
        };
    }

    fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
        _ = context;
        try out.append(allocator, search.Candidate.init(.action, "Settings", "System", "settings"));
        try out.append(allocator, search.Candidate.init(.action, "Power menu", "Session", "power"));
        try out.append(allocator, search.Candidate.init(.action, "Restart Waybar", "System", "restart-waybar"));
        try out.append(allocator, search.Candidate.init(.action, "Notifications panel", "System", "notifications"));
    }

    fn health(context: *anyopaque) search.ProviderHealth {
        _ = context;
        return .ready;
    }
};

pub fn resolveActionCommand(action: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, action, "settings")) return "wlrlui";
    if (std.mem.eql(u8, action, "power")) return "wlogout";
    if (std.mem.eql(u8, action, "restart-waybar")) return "waybar --reload";
    if (std.mem.eql(u8, action, "notifications")) return "$HOME/.config/waybar/scripts/swaync-control.sh toggle";
    return null;
}

pub fn requiresConfirmation(action: []const u8) bool {
    return std.mem.eql(u8, action, "power");
}

pub fn executeAction(
    action: []const u8,
    runner: *const fn (command: []const u8) anyerror!void,
) !void {
    // `action` is an internal action id; `runner` executes the mapped command string.
    const command = resolveActionCommand(action) orelse return error.UnknownAction;
    try runner(command);
}

test "actions provider collects static action candidates" {
    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    var provider_impl = ActionsProvider{};
    const provider = provider_impl.provider();

    try provider.collect(std.testing.allocator, &list);
    try std.testing.expectEqual(@as(usize, 4), list.items.len);
    try std.testing.expectEqual(search.CandidateKind.action, list.items[0].kind);
    try std.testing.expectEqualStrings("settings", list.items[0].action);
}

test "execute action resolves command mapping" {
    const Runner = struct {
        fn run(command: []const u8) !void {
            test_command_capture = command;
        }
    };

    test_command_capture = null;
    try executeAction("restart-waybar", Runner.run);
    try std.testing.expect(test_command_capture != null);
    try std.testing.expectEqualStrings("waybar --reload", test_command_capture.?);
}

test "power action requires confirmation" {
    try std.testing.expect(requiresConfirmation("power"));
    try std.testing.expect(!requiresConfirmation("settings"));
}

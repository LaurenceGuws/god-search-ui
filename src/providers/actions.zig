const std = @import("std");
const search = @import("../search/mod.zig");
const tool_check = @import("tool_check.zig");
var test_command_capture: ?[]const u8 = null;

const Dependency = union(enum) {
    none,
    command: []const u8,
    home_relative_path: []const u8,
};

const ActionSpec = struct {
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
    command: []const u8,
    dependency: Dependency,
    confirm: bool = false,
};

const action_specs = [_]ActionSpec{
    .{
        .title = "Settings",
        .subtitle = "System",
        .action = "settings",
        .command = "wlrlui",
        .dependency = .{ .command = "wlrlui" },
    },
    .{
        .title = "Power menu",
        .subtitle = "Session",
        .action = "power",
        .command = "wlogout",
        .dependency = .{ .command = "wlogout" },
        .confirm = true,
    },
    .{
        .title = "Restart Waybar",
        .subtitle = "System",
        .action = "restart-waybar",
        .command = "waybar --reload",
        .dependency = .{ .command = "waybar" },
    },
    .{
        .title = "Notifications panel",
        .subtitle = "System",
        .action = "notifications",
        .command = "$HOME/.config/waybar/scripts/swaync-control.sh toggle",
        .dependency = .{ .home_relative_path = ".config/waybar/scripts/swaync-control.sh" },
    },
};

pub const ActionsProvider = struct {
    command_exists_fn: *const fn (name: []const u8) bool = tool_check.commandExistsCached,
    path_exists_fn: *const fn (path: []const u8) bool = pathExists,

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
        const self: *ActionsProvider = @ptrCast(@alignCast(context));
        for (action_specs) |spec| {
            if (!self.actionAvailable(spec)) continue;
            try out.append(allocator, search.Candidate.init(.action, spec.title, spec.subtitle, spec.action));
        }
    }

    fn health(context: *anyopaque) search.ProviderHealth {
        const self: *ActionsProvider = @ptrCast(@alignCast(context));
        var available_count: usize = 0;
        for (action_specs) |spec| {
            if (self.actionAvailable(spec)) available_count += 1;
        }
        if (available_count == 0) return .unavailable;
        if (available_count < action_specs.len) return .degraded;
        return .ready;
    }

    fn actionAvailable(self: *ActionsProvider, spec: ActionSpec) bool {
        return switch (spec.dependency) {
            .none => true,
            .command => |name| self.command_exists_fn(name),
            .home_relative_path => |relative_path| self.homeRelativePathExists(relative_path),
        };
    }

    fn homeRelativePathExists(self: *ActionsProvider, relative_path: []const u8) bool {
        const home = std.process.getEnvVarOwned(std.heap.page_allocator, "HOME") catch return false;
        defer std.heap.page_allocator.free(home);

        const path = std.fs.path.join(std.heap.page_allocator, &.{ home, relative_path }) catch return false;
        defer std.heap.page_allocator.free(path);

        return self.path_exists_fn(path);
    }
};

pub fn resolveActionCommand(action: []const u8) ?[]const u8 {
    for (action_specs) |spec| {
        if (std.mem.eql(u8, action, spec.action)) return spec.command;
    }
    return null;
}

pub fn requiresConfirmation(action: []const u8) bool {
    for (action_specs) |spec| {
        if (std.mem.eql(u8, action, spec.action)) return spec.confirm;
    }
    return false;
}

pub fn executeAction(
    action: []const u8,
    runner: *const fn (command: []const u8) anyerror!void,
) !void {
    // `action` is an internal action id; `runner` executes the mapped command string.
    const command = resolveActionCommand(action) orelse return error.UnknownAction;
    try runner(command);
}

fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

test "actions provider collects available action candidates only" {
    const Fake = struct {
        fn commandExists(name: []const u8) bool {
            return !std.mem.eql(u8, name, "wlogout");
        }

        fn pathExists(path: []const u8) bool {
            return std.mem.endsWith(u8, path, ".config/waybar/scripts/swaync-control.sh");
        }
    };

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    var provider_impl = ActionsProvider{
        .command_exists_fn = Fake.commandExists,
        .path_exists_fn = Fake.pathExists,
    };
    const provider = provider_impl.provider();

    try provider.collect(std.testing.allocator, &list);
    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expectEqual(search.CandidateKind.action, list.items[0].kind);
    try std.testing.expectEqualStrings("settings", list.items[0].action);
    try std.testing.expectEqualStrings("restart-waybar", list.items[1].action);
    try std.testing.expectEqualStrings("notifications", list.items[2].action);
}

test "actions provider health reflects dependency availability" {
    const FakeAllMissing = struct {
        fn commandExists(_: []const u8) bool {
            return false;
        }

        fn pathExists(_: []const u8) bool {
            return false;
        }
    };
    const FakePartial = struct {
        fn commandExists(name: []const u8) bool {
            return std.mem.eql(u8, name, "waybar");
        }

        fn pathExists(_: []const u8) bool {
            return false;
        }
    };

    var none_provider_impl = ActionsProvider{
        .command_exists_fn = FakeAllMissing.commandExists,
        .path_exists_fn = FakeAllMissing.pathExists,
    };
    try std.testing.expectEqual(search.ProviderHealth.unavailable, none_provider_impl.provider().health());

    var partial_provider_impl = ActionsProvider{
        .command_exists_fn = FakePartial.commandExists,
        .path_exists_fn = FakePartial.pathExists,
    };
    try std.testing.expectEqual(search.ProviderHealth.degraded, partial_provider_impl.provider().health());
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

test "execute action returns runner errors for failed commands" {
    const Runner = struct {
        fn run(_: []const u8) !void {
            return error.CommandFailed;
        }
    };

    try std.testing.expectError(error.CommandFailed, executeAction("settings", Runner.run));
}

test "power action requires confirmation" {
    try std.testing.expect(requiresConfirmation("power"));
    try std.testing.expect(!requiresConfirmation("settings"));
}

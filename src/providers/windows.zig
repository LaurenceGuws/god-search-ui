const std = @import("std");
const search = @import("../search/mod.zig");

pub const WindowsProvider = struct {
    owned_strings: std.ArrayListUnmanaged([]u8) = .{},
    had_runtime_failure: bool = false,
    list_windows_fn: *const fn (allocator: std.mem.Allocator) anyerror![]u8 = listWindowsWithSystemTools,
    has_tools_fn: *const fn () bool = hasSystemTools,

    pub fn deinit(self: *WindowsProvider, allocator: std.mem.Allocator) void {
        for (self.owned_strings.items) |item| allocator.free(item);
        self.owned_strings.deinit(allocator);
    }

    pub fn provider(self: *WindowsProvider) search.Provider {
        return .{
            .name = "windows",
            .context = self,
            .vtable = &.{
                .collect = collect,
                .health = health,
            },
        };
    }

    fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
        const self: *WindowsProvider = @ptrCast(@alignCast(context));
        if (!self.has_tools_fn()) {
            return;
        }

        const rows = self.list_windows_fn(allocator) catch |err| {
            self.had_runtime_failure = true;
            std.log.warn("windows provider query failed: {s}", .{@errorName(err)});
            return;
        };
        self.had_runtime_failure = false;
        defer allocator.free(rows);

        var lines = std.mem.splitScalar(u8, rows, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            var fields = std.mem.splitScalar(u8, line, '\t');
            const title = fields.next() orelse continue;
            const class = fields.next() orelse "Window";
            const address = fields.next() orelse continue;

            const kept_title = try self.keepString(allocator, title);
            const kept_class = try self.keepString(allocator, class);
            const kept_address = try self.keepString(allocator, address);
            try out.append(allocator, search.Candidate.init(.window, kept_title, kept_class, kept_address));
        }
    }

    fn health(context: *anyopaque) search.ProviderHealth {
        const self: *WindowsProvider = @ptrCast(@alignCast(context));
        if (!self.has_tools_fn()) return .degraded;
        if (self.had_runtime_failure) return .degraded;
        return .ready;
    }

    fn keepString(self: *WindowsProvider, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        const copy = try allocator.dupe(u8, value);
        try self.owned_strings.append(allocator, copy);
        return copy;
    }
};

fn hasSystemTools() bool {
    return commandExists("hyprctl") and commandExists("jq");
}

fn commandExists(name: []const u8) bool {
    const check_cmd = std.fmt.allocPrint(std.heap.page_allocator, "{s} --help >/dev/null 2>&1", .{name}) catch return false;
    defer std.heap.page_allocator.free(check_cmd);

    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "sh", "-lc", check_cmd },
    }) catch return false;
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    return result.term == .Exited and result.term.Exited == 0;
}

fn listWindowsWithSystemTools(allocator: std.mem.Allocator) ![]u8 {
    const query =
        "hyprctl clients -j | jq -r '.[] | select(.mapped == true and (.workspace.id // -1) >= 0) | \"\\((.title // \"\") | if length > 0 then . else (.class // \"Window\") end)\\t\\(.class // \"Window\")\\t\\(.address // \"\")\"'";
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "sh", "-lc", query },
    });
    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        return error.WindowQueryFailed;
    }
    allocator.free(result.stderr);
    return result.stdout;
}

test "windows provider parses command rows into candidates" {
    const Fake = struct {
        fn hasTools() bool {
            return true;
        }

        fn listWindows(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8,
                \\Terminal\tkitty\t0xabc
                \\Browser\tzen\t0xdef
                \\
            );
        }
    };

    var provider_impl = WindowsProvider{
        .list_windows_fn = Fake.listWindows,
        .has_tools_fn = Fake.hasTools,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(search.ProviderHealth.ready, provider.health());
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqual(search.CandidateKind.window, list.items[0].kind);
    try std.testing.expectEqualStrings("Terminal", list.items[0].title);
    try std.testing.expectEqualStrings("kitty", list.items[0].subtitle);
    try std.testing.expectEqualStrings("0xabc", list.items[0].action);
}

test "windows provider degrades when tools are unavailable" {
    const Fake = struct {
        fn hasTools() bool {
            return false;
        }

        fn listWindows(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8, "");
        }
    };

    var provider_impl = WindowsProvider{
        .list_windows_fn = Fake.listWindows,
        .has_tools_fn = Fake.hasTools,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(search.ProviderHealth.degraded, provider.health());
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}

test "windows provider runtime query failure degrades health while keeping UX graceful" {
    const Fake = struct {
        fn hasTools() bool {
            return true;
        }

        fn listWindows(_: std.mem.Allocator) ![]u8 {
            return error.WindowQueryFailed;
        }
    };

    var provider_impl = WindowsProvider{
        .list_windows_fn = Fake.listWindows,
        .has_tools_fn = Fake.hasTools,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 0), list.items.len);
    try std.testing.expectEqual(search.ProviderHealth.degraded, provider.health());
}

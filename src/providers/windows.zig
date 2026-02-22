const std = @import("std");
const search = @import("../search/mod.zig");
const tool_check = @import("tool_check.zig");

pub const WindowsProvider = struct {
    owned_strings_current: std.ArrayListUnmanaged([]u8) = .{},
    owned_strings_previous: std.ArrayListUnmanaged([]u8) = .{},
    had_runtime_failure: bool = false,
    list_windows_fn: *const fn (allocator: std.mem.Allocator) anyerror![]u8 = listWindowsWithSystemTools,
    has_tools_fn: *const fn () bool = hasSystemTools,

    pub fn deinit(self: *WindowsProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_current);
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        self.owned_strings_current.deinit(allocator);
        self.owned_strings_previous.deinit(allocator);
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
        self.rotateOwnedStringsForCollect(allocator);

        var lines = std.mem.splitScalar(u8, rows, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            var fields = std.mem.splitScalar(u8, line, '\t');
            const title = fields.next() orelse continue;
            const class = fields.next() orelse "Window";
            const address = fields.next() orelse continue;

            const kept_title = try self.keepJqTsvField(allocator, title);
            const kept_class = try self.keepJqTsvField(allocator, class);
            const kept_address = try self.keepJqTsvField(allocator, address);
            try out.append(allocator, search.Candidate.init(.window, kept_title, kept_class, kept_address));
        }
    }

    fn health(context: *anyopaque) search.ProviderHealth {
        const self: *WindowsProvider = @ptrCast(@alignCast(context));
        if (!self.has_tools_fn()) return .unavailable;
        if (self.had_runtime_failure) return .degraded;
        return .ready;
    }

    fn keepString(self: *WindowsProvider, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        const copy = try allocator.dupe(u8, value);
        try self.owned_strings_current.append(allocator, copy);
        return copy;
    }

    fn keepJqTsvField(self: *WindowsProvider, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        if (std.mem.indexOfScalar(u8, value, '\\') == null) {
            return self.keepString(allocator, value);
        }

        var decoded = std.ArrayList(u8).empty;
        defer decoded.deinit(allocator);

        var i: usize = 0;
        while (i < value.len) : (i += 1) {
            if (value[i] != '\\') {
                try decoded.append(allocator, value[i]);
                continue;
            }
            if (i + 1 >= value.len) {
                try decoded.append(allocator, '\\');
                continue;
            }

            i += 1;
            switch (value[i]) {
                'n' => try decoded.append(allocator, '\n'),
                'r' => try decoded.append(allocator, '\r'),
                't' => try decoded.append(allocator, '\t'),
                '\\' => try decoded.append(allocator, '\\'),
                else => {
                    try decoded.append(allocator, '\\');
                    try decoded.append(allocator, value[i]);
                },
            }
        }

        const copy = try decoded.toOwnedSlice(allocator);
        try self.owned_strings_current.append(allocator, copy);
        return copy;
    }

    fn rotateOwnedStringsForCollect(self: *WindowsProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        std.mem.swap(
            std.ArrayListUnmanaged([]u8),
            &self.owned_strings_current,
            &self.owned_strings_previous,
        );
        self.owned_strings_current.clearRetainingCapacity();
    }

    fn freeOwnedStrings(self: *WindowsProvider, allocator: std.mem.Allocator, strings: *std.ArrayListUnmanaged([]u8)) void {
        _ = self;
        for (strings.items) |item| allocator.free(item);
        strings.clearRetainingCapacity();
    }
};

fn hasSystemTools() bool {
    return tool_check.commandExistsCached("hyprctl") and tool_check.commandExistsCached("jq");
}

fn listWindowsWithSystemTools(allocator: std.mem.Allocator) ![]u8 {
    const query =
        "hyprctl clients -j | jq -r '.[] | select(.mapped == true and (.workspace.id // -1) >= 0) | [((.title // \"\") | if length > 0 then . else (.class // \"Window\") end), (.class // \"Window\"), (.address // \"\")] | @tsv'";
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

test "windows provider reports unavailable when tools are unavailable" {
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

    try std.testing.expectEqual(search.ProviderHealth.unavailable, provider.health());
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

test "windows provider keeps prior generations alive on transient failure" {
    const Fake = struct {
        fn hasTools() bool {
            return true;
        }

        fn listWindowsA(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8, "Terminal\tkitty\t0xaaa\n");
        }

        fn listWindowsB(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8, "Browser\tzen\t0xbbb\n");
        }

        fn listWindowsFail(_: std.mem.Allocator) ![]u8 {
            return error.WindowQueryFailed;
        }
    };

    var provider_impl = WindowsProvider{
        .list_windows_fn = Fake.listWindowsA,
        .has_tools_fn = Fake.hasTools,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);
    const first_title = list.items[0].title;
    const first_action = list.items[0].action;

    list.clearRetainingCapacity();
    provider_impl.list_windows_fn = Fake.listWindowsB;
    try provider.collect(std.testing.allocator, &list);
    const second_title = list.items[0].title;
    const second_action = list.items[0].action;

    const total_before_failure = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 6), total_before_failure);

    list.clearRetainingCapacity();
    provider_impl.list_windows_fn = Fake.listWindowsFail;
    try provider.collect(std.testing.allocator, &list);

    const total_after_failure = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(total_before_failure, total_after_failure);
    try std.testing.expectEqual(search.ProviderHealth.degraded, provider.health());
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
    try std.testing.expectEqualStrings("Terminal", first_title);
    try std.testing.expectEqualStrings("0xaaa", first_action);
    try std.testing.expectEqualStrings("Browser", second_title);
    try std.testing.expectEqualStrings("0xbbb", second_action);
}

test "windows provider decodes jq tsv escaped tabs and newlines" {
    const Fake = struct {
        fn hasTools() bool {
            return true;
        }

        fn listWindows(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8, "Title\\\\Thing\\tTabbed\\nName\tclass\\\\name\t0xabc\n");
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

    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("Title\\Thing\tTabbed\nName", list.items[0].title);
    try std.testing.expectEqualStrings("class\\name", list.items[0].subtitle);
    try std.testing.expectEqualStrings("0xabc", list.items[0].action);
}

test "windows provider rotates owned strings across collects with bounded growth" {
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
    const first_total = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 6), first_total);

    list.clearRetainingCapacity();
    try provider.collect(std.testing.allocator, &list);
    const second_total = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 12), second_total);

    list.clearRetainingCapacity();
    try provider.collect(std.testing.allocator, &list);
    const third_total = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 12), third_total);
}

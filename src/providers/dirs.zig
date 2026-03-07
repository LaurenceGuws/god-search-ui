const std = @import("std");
const search = @import("../search/mod.zig");
const tool_check = @import("tool_check.zig");

pub const DirsProvider = struct {
    owned_strings_current: std.ArrayListUnmanaged([]u8) = .{},
    owned_strings_previous: std.ArrayListUnmanaged([]u8) = .{},
    had_runtime_failure: bool = false,
    list_dirs_fn: *const fn (allocator: std.mem.Allocator) anyerror![]u8 = listDirsWithSystemTools,
    has_tools_fn: *const fn () bool = hasSystemTools,

    pub fn deinit(self: *DirsProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_current);
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        self.owned_strings_current.deinit(allocator);
        self.owned_strings_previous.deinit(allocator);
    }

    pub fn provider(self: *DirsProvider) search.Provider {
        return .{
            .name = "dirs",
            .context = self,
            .vtable = &.{
                .collect = collect,
                .health = health,
            },
        };
    }

    fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
        const self: *DirsProvider = @ptrCast(@alignCast(context));
        if (!self.has_tools_fn()) {
            return;
        }

        const rows = self.list_dirs_fn(allocator) catch |err| {
            self.had_runtime_failure = true;
            std.log.warn("dirs provider query failed: {s}", .{@errorName(err)});
            return;
        };
        self.had_runtime_failure = false;
        defer allocator.free(rows);
        self.rotateOwnedStringsForCollect(allocator);

        var lines = std.mem.splitScalar(u8, rows, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            const split_idx = std.mem.indexOfAny(u8, trimmed, " \t") orelse continue;
            const path_raw = std.mem.trimLeft(u8, trimmed[split_idx + 1 ..], " \t");
            const path = std.mem.trimRight(u8, path_raw, " \t\r");
            if (path.len == 0) continue;

            const base = std.fs.path.basename(path);
            const kept_base = try self.keepString(allocator, base);
            const kept_path = try self.keepString(allocator, path);
            try out.append(allocator, search.Candidate.init(.dir, kept_base, "Recent terminal location", kept_path));
        }
    }

    fn health(context: *anyopaque) search.ProviderHealth {
        const self: *DirsProvider = @ptrCast(@alignCast(context));
        if (!self.has_tools_fn()) return .unavailable;
        if (self.had_runtime_failure) return .degraded;
        return .ready;
    }

    fn keepString(self: *DirsProvider, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        const copy = try allocator.dupe(u8, value);
        try self.owned_strings_current.append(allocator, copy);
        return copy;
    }

    fn rotateOwnedStringsForCollect(self: *DirsProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        std.mem.swap(
            std.ArrayListUnmanaged([]u8),
            &self.owned_strings_current,
            &self.owned_strings_previous,
        );
        self.owned_strings_current.clearRetainingCapacity();
    }

    fn freeOwnedStrings(self: *DirsProvider, allocator: std.mem.Allocator, strings: *std.ArrayListUnmanaged([]u8)) void {
        _ = self;
        for (strings.items) |item| allocator.free(item);
        strings.clearRetainingCapacity();
    }
};

fn hasSystemTools() bool {
    return tool_check.commandExists("zoxide");
}

fn listDirsWithSystemTools(allocator: std.mem.Allocator) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zoxide", "query", "-ls" },
    });
    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        return error.DirQueryFailed;
    }
    allocator.free(result.stderr);
    return result.stdout;
}

test "dirs provider parses zoxide rows into candidates" {
    const Fake = struct {
        fn hasTools() bool {
            return true;
        }

        fn listDirs(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8,
                \\1226.0 /home/home/personal
                \\  94.5 /home/home/.config/hypr
                \\
            );
        }
    };

    var provider_impl = DirsProvider{
        .list_dirs_fn = Fake.listDirs,
        .has_tools_fn = Fake.hasTools,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(search.ProviderHealth.ready, provider.health());
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqual(search.CandidateKind.dir, list.items[0].kind);
    try std.testing.expectEqualStrings("personal", list.items[0].title);
    try std.testing.expectEqualStrings("/home/home/personal", list.items[0].action);
}

test "dirs provider reports unavailable when zoxide is unavailable" {
    const Fake = struct {
        fn hasTools() bool {
            return false;
        }

        fn listDirs(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8, "");
        }
    };

    var provider_impl = DirsProvider{
        .list_dirs_fn = Fake.listDirs,
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

test "dirs provider keeps full path when spaces exist" {
    const Fake = struct {
        fn hasTools() bool {
            return true;
        }

        fn listDirs(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8,
                \\  92.0 /home/home/personal/space path
                \\
            );
        }
    };

    var provider_impl = DirsProvider{
        .list_dirs_fn = Fake.listDirs,
        .has_tools_fn = Fake.hasTools,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("space path", list.items[0].title);
    try std.testing.expectEqualStrings("/home/home/personal/space path", list.items[0].action);
}

test "dirs provider runtime query failure degrades health while keeping UX graceful" {
    const Fake = struct {
        fn hasTools() bool {
            return true;
        }

        fn listDirs(_: std.mem.Allocator) ![]u8 {
            return error.DirQueryFailed;
        }
    };

    var provider_impl = DirsProvider{
        .list_dirs_fn = Fake.listDirs,
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

test "dirs provider keeps prior generations alive on transient failure" {
    const Fake = struct {
        fn hasTools() bool {
            return true;
        }

        fn listDirsA(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8,
                \\1.0 /tmp/alpha dir
                \\
            );
        }

        fn listDirsB(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8,
                \\2.0 /tmp/beta dir
                \\
            );
        }

        fn listDirsFail(_: std.mem.Allocator) ![]u8 {
            return error.DirQueryFailed;
        }
    };

    var provider_impl = DirsProvider{
        .list_dirs_fn = Fake.listDirsA,
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
    provider_impl.list_dirs_fn = Fake.listDirsB;
    try provider.collect(std.testing.allocator, &list);
    const second_title = list.items[0].title;
    const second_action = list.items[0].action;

    const total_before_failure = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 4), total_before_failure);

    list.clearRetainingCapacity();
    provider_impl.list_dirs_fn = Fake.listDirsFail;
    try provider.collect(std.testing.allocator, &list);

    const total_after_failure = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(total_before_failure, total_after_failure);
    try std.testing.expectEqual(search.ProviderHealth.degraded, provider.health());
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
    try std.testing.expectEqualStrings("alpha dir", first_title);
    try std.testing.expectEqualStrings("/tmp/alpha dir", first_action);
    try std.testing.expectEqualStrings("beta dir", second_title);
    try std.testing.expectEqualStrings("/tmp/beta dir", second_action);
}

test "dirs provider rotates owned strings across collects with bounded growth" {
    const Fake = struct {
        fn hasTools() bool {
            return true;
        }

        fn listDirs(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8,
                \\1226.0 /home/home/personal
                \\  94.5 /home/home/.config/hypr
                \\
            );
        }
    };

    var provider_impl = DirsProvider{
        .list_dirs_fn = Fake.listDirs,
        .has_tools_fn = Fake.hasTools,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);
    const first_total = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 4), first_total);

    list.clearRetainingCapacity();
    try provider.collect(std.testing.allocator, &list);
    const second_total = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 8), second_total);

    list.clearRetainingCapacity();
    try provider.collect(std.testing.allocator, &list);
    const third_total = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 8), third_total);
}

test "dirs provider trims crlf and trailing whitespace from parsed paths" {
    const Fake = struct {
        fn hasTools() bool {
            return true;
        }

        fn listDirs(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8,
                \\1.0 /tmp/alpha dir  \r
                \\2.0 /tmp/beta\t\r
                \\
            );
        }
    };

    var provider_impl = DirsProvider{
        .list_dirs_fn = Fake.listDirs,
        .has_tools_fn = Fake.hasTools,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("alpha dir", list.items[0].title);
    try std.testing.expectEqualStrings("/tmp/alpha dir", list.items[0].action);
    try std.testing.expectEqualStrings("beta", list.items[1].title);
    try std.testing.expectEqualStrings("/tmp/beta", list.items[1].action);
}

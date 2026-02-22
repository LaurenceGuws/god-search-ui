const std = @import("std");
const search = @import("../search/mod.zig");

pub const DirsProvider = struct {
    owned_strings: std.ArrayListUnmanaged([]u8) = .{},
    list_dirs_fn: *const fn (allocator: std.mem.Allocator) anyerror![]u8 = listDirsWithSystemTools,
    has_tools_fn: *const fn () bool = hasSystemTools,

    pub fn deinit(self: *DirsProvider, allocator: std.mem.Allocator) void {
        for (self.owned_strings.items) |item| allocator.free(item);
        self.owned_strings.deinit(allocator);
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

        const rows = self.list_dirs_fn(allocator) catch return;
        defer allocator.free(rows);

        var lines = std.mem.splitScalar(u8, rows, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len == 0) continue;
            const split_idx = std.mem.indexOfAny(u8, trimmed, " \t") orelse continue;
            const path = std.mem.trimLeft(u8, trimmed[split_idx + 1 ..], " \t");
            if (path.len == 0) continue;

            const base = std.fs.path.basename(path);
            const kept_base = try self.keepString(allocator, base);
            const kept_path = try self.keepString(allocator, path);
            try out.append(allocator, search.Candidate.init(.dir, kept_base, "Recent terminal location", kept_path));
        }
    }

    fn health(context: *anyopaque) search.ProviderHealth {
        const self: *DirsProvider = @ptrCast(@alignCast(context));
        if (!self.has_tools_fn()) return .degraded;
        return .ready;
    }

    fn keepString(self: *DirsProvider, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        const copy = try allocator.dupe(u8, value);
        try self.owned_strings.append(allocator, copy);
        return copy;
    }
};

fn hasSystemTools() bool {
    return commandExists("zoxide");
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

test "dirs provider degrades when zoxide is unavailable" {
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

    try std.testing.expectEqual(search.ProviderHealth.degraded, provider.health());
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

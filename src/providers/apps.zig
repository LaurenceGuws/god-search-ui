const std = @import("std");
const search = @import("../search/mod.zig");

pub const AppsProvider = struct {
    cache_path: []const u8,
    owned_strings_current: std.ArrayListUnmanaged([]u8) = .{},
    owned_strings_previous: std.ArrayListUnmanaged([]u8) = .{},
    had_runtime_failure: bool = false,

    pub fn init(cache_path: []const u8) AppsProvider {
        return .{
            .cache_path = cache_path,
        };
    }

    pub fn deinit(self: *AppsProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_current);
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        self.owned_strings_current.deinit(allocator);
        self.owned_strings_previous.deinit(allocator);
    }

    pub fn provider(self: *AppsProvider) search.Provider {
        return .{
            .name = "apps",
            .context = self,
            .vtable = &.{
                .collect = collect,
                .health = health,
            },
        };
    }

    fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
        const self: *AppsProvider = @ptrCast(@alignCast(context));
        self.rotateOwnedStringsForCollect(allocator);
        const data = std.fs.cwd().readFileAlloc(allocator, self.cache_path, 2 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                self.had_runtime_failure = false;
                try out.append(allocator, search.Candidate.init(.app, "App launcher", "Fallback", "__drun__"));
                return;
            },
            else => {
                self.had_runtime_failure = true;
                std.log.warn("apps provider cache read failed: {s}", .{@errorName(err)});
                try out.append(allocator, search.Candidate.init(.app, "App launcher", "Fallback", "__drun__"));
                return;
            },
        };
        defer allocator.free(data);

        var count: usize = 0;
        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |line| {
            const normalized_line = std.mem.trimRight(u8, line, "\r");
            if (normalized_line.len == 0) continue;
            var fields = std.mem.splitScalar(u8, normalized_line, '\t');
            const category = std.mem.trimRight(u8, fields.next() orelse continue, " \t\r");
            const name = std.mem.trimRight(u8, fields.next() orelse continue, " \t\r");
            const exec_cmd = std.mem.trimRight(u8, fields.next() orelse continue, " \t\r");
            const icon_name = std.mem.trimRight(u8, fields.next() orelse "", " \t\r");

            const kept_name = try self.keepString(allocator, name);
            const kept_category = try self.keepString(allocator, category);
            const kept_exec = try self.keepString(allocator, exec_cmd);
            const kept_icon = try self.keepString(allocator, icon_name);
            try out.append(allocator, search.Candidate.initWithIcon(.app, kept_name, kept_category, kept_exec, kept_icon));
            count += 1;
        }

        if (count == 0) {
            self.had_runtime_failure = true;
            try out.append(allocator, search.Candidate.init(.app, "App launcher", "Fallback", "__drun__"));
            return;
        }
        self.had_runtime_failure = false;
    }

    fn health(context: *anyopaque) search.ProviderHealth {
        const self: *AppsProvider = @ptrCast(@alignCast(context));
        std.fs.cwd().access(self.cache_path, .{}) catch return .degraded;
        if (self.had_runtime_failure) return .degraded;
        return .ready;
    }

    fn keepString(self: *AppsProvider, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        const copy = try allocator.dupe(u8, value);
        try self.owned_strings_current.append(allocator, copy);
        return copy;
    }

    fn rotateOwnedStringsForCollect(self: *AppsProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        std.mem.swap(
            std.ArrayListUnmanaged([]u8),
            &self.owned_strings_current,
            &self.owned_strings_previous,
        );
        self.owned_strings_current.clearRetainingCapacity();
    }

    fn freeOwnedStrings(self: *AppsProvider, allocator: std.mem.Allocator, strings: *std.ArrayListUnmanaged([]u8)) void {
        _ = self;
        for (strings.items) |item| allocator.free(item);
        strings.clearRetainingCapacity();
    }
};

test "apps provider collects rows from cache file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "apps.tsv",
        .data =
        \\Utilities\tKitty\tkitty\tkitty
        \\Internet\tFirefox\tfirefox\tfirefox
        \\
        ,
    });

    const cache_path = try tmp.dir.realpathAlloc(std.testing.allocator, "apps.tsv");
    defer std.testing.allocator.free(cache_path);

    var apps = AppsProvider.init(cache_path);
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(search.ProviderHealth.ready, provider.health());
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("Kitty", list.items[0].title);
    try std.testing.expectEqualStrings("Utilities", list.items[0].subtitle);
    try std.testing.expectEqualStrings("kitty", list.items[0].action);
    try std.testing.expectEqualStrings("kitty", list.items[0].icon);
}

test "apps provider accepts legacy three-column rows with empty icon metadata" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "apps.tsv",
        .data =
        \\Utilities\tKitty\tkitty
        \\Internet\tFirefox\tfirefox\tfirefox
        \\
        ,
    });

    const cache_path = try tmp.dir.realpathAlloc(std.testing.allocator, "apps.tsv");
    defer std.testing.allocator.free(cache_path);

    var apps = AppsProvider.init(cache_path);
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("Kitty", list.items[0].title);
    try std.testing.expectEqualStrings("", list.items[0].icon);
    try std.testing.expectEqualStrings("firefox", list.items[1].icon);
}

test "apps provider falls back when cache is missing" {
    var apps = AppsProvider.init("/tmp/non-existent-app-cache.tsv");
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(search.ProviderHealth.degraded, provider.health());
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("__drun__", list.items[0].action);
}

test "apps provider degrades when cache exists but no valid rows are parsed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "apps.tsv",
        .data =
        \\bad row
        \\still bad
        \\
        ,
    });

    const cache_path = try tmp.dir.realpathAlloc(std.testing.allocator, "apps.tsv");
    defer std.testing.allocator.free(cache_path);

    var apps = AppsProvider.init(cache_path);
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("__drun__", list.items[0].action);
    try std.testing.expectEqual(search.ProviderHealth.degraded, provider.health());
}

test "apps provider rotates owned strings across collects with bounded growth" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "apps.tsv",
        .data =
        \\Utilities\tKitty\tkitty\tkitty
        \\Internet\tFirefox\tfirefox\tfirefox
        \\
        ,
    });

    const cache_path = try tmp.dir.realpathAlloc(std.testing.allocator, "apps.tsv");
    defer std.testing.allocator.free(cache_path);

    var apps = AppsProvider.init(cache_path);
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);
    const first_total = apps.owned_strings_current.items.len + apps.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 8), first_total);

    list.clearRetainingCapacity();
    try provider.collect(std.testing.allocator, &list);
    const second_total = apps.owned_strings_current.items.len + apps.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 16), second_total);

    list.clearRetainingCapacity();
    try provider.collect(std.testing.allocator, &list);
    const third_total = apps.owned_strings_current.items.len + apps.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 16), third_total);
}

test "apps provider trims crlf and trailing whitespace from stored fields" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "apps.tsv",
        .data =
        \\Utilities  \tKitty\tkitty  \tkitty  \r
        \\Internet\tFirefox\tfirefox\r
        \\
        ,
    });

    const cache_path = try tmp.dir.realpathAlloc(std.testing.allocator, "apps.tsv");
    defer std.testing.allocator.free(cache_path);

    var apps = AppsProvider.init(cache_path);
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("Utilities", list.items[0].subtitle);
    try std.testing.expectEqualStrings("kitty", list.items[0].action);
    try std.testing.expectEqualStrings("kitty", list.items[0].icon);
    try std.testing.expectEqualStrings("firefox", list.items[1].action);
}

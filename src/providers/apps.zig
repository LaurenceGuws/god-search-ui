const std = @import("std");
const search = @import("../search/mod.zig");

pub const AppsProvider = struct {
    cache_path: []const u8,
    owned_strings: std.ArrayListUnmanaged([]u8) = .{},

    pub fn init(cache_path: []const u8) AppsProvider {
        return .{
            .cache_path = cache_path,
        };
    }

    pub fn deinit(self: *AppsProvider, allocator: std.mem.Allocator) void {
        for (self.owned_strings.items) |item| allocator.free(item);
        self.owned_strings.deinit(allocator);
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
        const data = std.fs.cwd().readFileAlloc(allocator, self.cache_path, 2 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                try out.append(search.Candidate.init(.app, "App launcher", "Fallback", "__drun__"));
                return;
            },
            else => return err,
        };
        defer allocator.free(data);

        var count: usize = 0;
        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            var fields = std.mem.splitScalar(u8, line, '\t');
            const category = fields.next() orelse continue;
            const name = fields.next() orelse continue;
            const exec_cmd = fields.next() orelse continue;

            const kept_name = try self.keepString(allocator, name);
            const kept_category = try self.keepString(allocator, category);
            const kept_exec = try self.keepString(allocator, exec_cmd);
            try out.append(search.Candidate.init(.app, kept_name, kept_category, kept_exec));
            count += 1;
        }

        if (count == 0) {
            try out.append(search.Candidate.init(.app, "App launcher", "Fallback", "__drun__"));
        }
    }

    fn health(context: *anyopaque) search.ProviderHealth {
        const self: *AppsProvider = @ptrCast(@alignCast(context));
        std.fs.cwd().access(self.cache_path, .{}) catch return .degraded;
        return .ready;
    }

    fn keepString(self: *AppsProvider, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        const copy = try allocator.dupe(u8, value);
        try self.owned_strings.append(allocator, copy);
        return copy;
    }
};

test "apps provider collects rows from cache file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "apps.tsv",
        .data =
        \\Utilities\tKitty\tkitty
        \\Internet\tFirefox\tfirefox
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

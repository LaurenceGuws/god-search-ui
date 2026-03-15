const std = @import("std");

pub fn configHomePath(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg| return xdg else |_| {}
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/.config", .{home});
}

pub fn homePath(allocator: std.mem.Allocator) ![]u8 {
    return std.process.getEnvVarOwned(allocator, "HOME");
}

pub fn tryJoin(allocator: std.mem.Allocator, parts: []const []const u8) ?[]u8 {
    return std.fs.path.join(allocator, parts) catch null;
}

pub fn cacheHomePath(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "XDG_CACHE_HOME")) |xdg| return xdg else |_| {}
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/.cache", .{home});
}

pub fn webCacheDir(allocator: std.mem.Allocator) ![]u8 {
    const cache_home = try cacheHomePath(allocator);
    defer allocator.free(cache_home);
    return std.fs.path.join(allocator, &.{ cache_home, "wayspot", "web" });
}

pub fn webCacheFilePath(allocator: std.mem.Allocator, file_name: []const u8) ![]u8 {
    const dir = try webCacheDir(allocator);
    defer allocator.free(dir);
    return std.fs.path.join(allocator, &.{ dir, file_name });
}

pub fn ensurePathExistsAbsolute(path: []const u8) !void {
    var fs_path = try std.fs.openDirAbsolute("/", .{});
    defer fs_path.close();
    try fs_path.makePath(path[1..]);
}

pub fn writeFileAtomicAbsolute(path: []const u8, contents: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return error.FileNotFound;
    try ensurePathExistsAbsolute(parent);
    const tmp_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}.tmp", .{path});
    defer std.heap.page_allocator.free(tmp_path);
    var file = try std.fs.createFileAbsolute(tmp_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(contents);
    try file.sync();
    try std.fs.renameAbsolute(tmp_path, path);
}

pub fn readFileAbsoluteAllocCompat(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, max_bytes);
}

pub fn fileExistsPath(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

pub fn sqliteHeaderLooksValid(path: []const u8) bool {
    var file = std.fs.openFileAbsolute(path, .{}) catch return false;
    defer file.close();

    var header: [16]u8 = undefined;
    const n = file.readAll(&header) catch return false;
    if (n < header.len) return false;
    return std.mem.eql(u8, header[0..], "SQLite format 3\x00");
}

pub fn looksLikeUrl(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "http://") or std.mem.startsWith(u8, value, "https://");
}

pub fn sqlite3Available() bool {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "sqlite3", "--version" },
        .max_output_bytes = 256,
    }) catch return false;
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    return result.term == .Exited and result.term.Exited == 0;
}

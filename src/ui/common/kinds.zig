const std = @import("std");

pub const UiKind = enum {
    unknown,
    action,
    app,
    window,
    dir,
    file,
    grep,
    module,
    dir_option,
    file_option,
};

pub fn parse(kind: []const u8) UiKind {
    if (std.mem.eql(u8, kind, "action")) return .action;
    if (std.mem.eql(u8, kind, "app")) return .app;
    if (std.mem.eql(u8, kind, "window")) return .window;
    if (std.mem.eql(u8, kind, "dir")) return .dir;
    if (std.mem.eql(u8, kind, "file")) return .file;
    if (std.mem.eql(u8, kind, "grep")) return .grep;
    if (std.mem.eql(u8, kind, "module")) return .module;
    if (std.mem.eql(u8, kind, "dir_option")) return .dir_option;
    if (std.mem.eql(u8, kind, "file_option")) return .file_option;
    return .unknown;
}

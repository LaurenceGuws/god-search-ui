const std = @import("std");
const search = @import("../../search/mod.zig");

pub const UiKind = enum {
    unknown,
    action,
    app,
    window,
    dir,
    file,
    grep,
    web,
    hint,
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
    if (std.mem.eql(u8, kind, "web")) return .web;
    if (std.mem.eql(u8, kind, "hint")) return .hint;
    if (std.mem.eql(u8, kind, "module")) return .module;
    if (std.mem.eql(u8, kind, "dir_option")) return .dir_option;
    if (std.mem.eql(u8, kind, "file_option")) return .file_option;
    return .unknown;
}

pub fn tag(kind: UiKind) []const u8 {
    return switch (kind) {
        .action => "action",
        .app => "app",
        .window => "window",
        .dir => "dir",
        .file => "file",
        .grep => "grep",
        .web => "web",
        .hint => "hint",
        .module => "module",
        .dir_option => "dir_option",
        .file_option => "file_option",
        .unknown => "unknown",
    };
}

pub fn statusLabel(kind: UiKind) []const u8 {
    return switch (kind) {
        .app => "app",
        .window => "window",
        .dir => "directory",
        .file => "file",
        .grep => "match",
        .web => "web search",
        .module => "module filter",
        .action => "action",
        .hint => "hint",
        else => "result",
    };
}

pub fn fromCandidateKind(kind: search.CandidateKind) UiKind {
    return switch (kind) {
        .app => .app,
        .window => .window,
        .dir => .dir,
        .file => .file,
        .grep => .grep,
        .web => .web,
        .action => .action,
        .hint => .hint,
    };
}

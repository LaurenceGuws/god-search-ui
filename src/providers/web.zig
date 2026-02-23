const std = @import("std");
const search = @import("../search/mod.zig");

pub fn appendRouteCandidates(
    allocator: std.mem.Allocator,
    parsed: search.Query,
    out: *search.CandidateList,
) !void {
    if (parsed.route != .web) return;
    const term = std.mem.trim(u8, parsed.term, " \t\r\n");
    if (term.len == 0) return;

    try out.append(allocator, .{
        .kind = .web,
        .title = "Search Web",
        .subtitle = term,
        .action = term,
        .icon = "web-browser-symbolic",
    });
}

test "appendRouteCandidates adds one web result for non-empty ? query" {
    var out = search.CandidateList.empty;
    defer out.deinit(std.testing.allocator);

    try appendRouteCandidates(std.testing.allocator, search.parseQuery("? dota 2"), &out);
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expectEqual(search.CandidateKind.web, out.items[0].kind);
    try std.testing.expectEqualStrings("Search Web", out.items[0].title);
    try std.testing.expectEqualStrings("dota 2", out.items[0].subtitle);
    try std.testing.expectEqualStrings("dota 2", out.items[0].action);
}

test "appendRouteCandidates ignores non-web and empty web terms" {
    var out = search.CandidateList.empty;
    defer out.deinit(std.testing.allocator);

    try appendRouteCandidates(std.testing.allocator, search.parseQuery("@ kitty"), &out);
    try appendRouteCandidates(std.testing.allocator, search.parseQuery("?   "), &out);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

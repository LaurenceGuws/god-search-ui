const std = @import("std");
const god_search_ui = @import("god_search_ui");

pub fn main() !void {
    std.debug.print("god-search-ui starting\n", .{});
    try god_search_ui.bufferedPrint();
}

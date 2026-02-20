const std = @import("std");
const god_search_ui = @import("god_search_ui");

pub fn main() !void {
    const state = god_search_ui.app.bootstrap();
    std.debug.print("god-search-ui starting (mode={s})\n", .{@tagName(state.mode)});
    try god_search_ui.bufferedPrint();
}

const std = @import("std");
const god_search_ui = @import("god_search_ui");

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    const state = god_search_ui.app.bootstrap();
    const logger = god_search_ui.app.Logger.init(.info);
    logger.info("god-search-ui starting (mode={s})", .{@tagName(state.mode)});

    if (args.len > 1 and std.mem.eql(u8, args[1], "--ui")) {
        try god_search_ui.ui.Shell.run();
        return;
    }

    try god_search_ui.bufferedPrint();
}

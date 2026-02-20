const std = @import("std");
const god_search_ui = @import("god_search_ui");

pub fn main() !void {
    const state = god_search_ui.app.bootstrap();
    const logger = god_search_ui.app.Logger.init(.info);
    logger.info("god-search-ui starting (mode={s})", .{@tagName(state.mode)});
    try god_search_ui.bufferedPrint();
}

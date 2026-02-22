const search = @import("../../search/mod.zig");

pub const QueryDispatch = struct {
    parsed: search.Query,
    use_dynamic: bool,
};

pub fn parseAndClassify(raw_query: []const u8) QueryDispatch {
    const parsed = search.parseQuery(raw_query);
    return .{
        .parsed = parsed,
        .use_dynamic = isDynamicRoute(parsed.route),
    };
}

fn isDynamicRoute(route: search.Route) bool {
    return route == .files or route == .grep;
}

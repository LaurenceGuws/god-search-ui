const std = @import("std");
const search_mod = @import("../../search/mod.zig");
const gtk_types = @import("types.zig");
const gtk_query = @import("query_helpers.zig");
const gtk_render = @import("render.zig");
const gtk_icons = @import("icons.zig");
const gtk_nav = @import("navigation.zig");
const gtk_widgets = @import("widgets.zig");
const gtk_status = @import("status.zig");

const UiContext = gtk_types.UiContext;
const GFALSE = gtk_types.GFALSE;

pub const AsyncHooks = struct {
    start_async_route_search: *const fn (*UiContext, std.mem.Allocator, []const u8) void,
    cancel_async_route_search: *const fn (*UiContext) void,
};

pub fn populateResults(ctx: *UiContext, query: []const u8, hooks: AsyncHooks) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    const query_trimmed = std.mem.trim(u8, query, " \t\r\n");

    if (query_trimmed.len == 0) {
        hooks.cancel_async_route_search(ctx);
        const empty_hash = std.hash.Wyhash.hash(0, "module-filter-menu");
        if (ctx.last_render_hash != empty_hash) {
            gtk_widgets.clearList(ctx.list);
            gtk_widgets.appendModuleFilterMenu(ctx.list, allocator);
            ctx.last_render_hash = empty_hash;
        }
        if (ctx.pending_power_confirm == GFALSE) {
            gtk_status.setStatus(ctx, "Pick a module (Enter) or type directly for blended search");
        }
        gtk_nav.selectFirstActionableRow(ctx);
        return;
    }

    if (gtk_query.shouldAsyncRouteQuery(query_trimmed)) {
        hooks.start_async_route_search(ctx, allocator, query_trimmed);
        return;
    }
    hooks.cancel_async_route_search(ctx);

    const ranked = ctx.service.searchQuery(allocator, query) catch |err| {
        renderSearchError(ctx, allocator, err);
        return;
    };
    defer allocator.free(ranked);

    renderRankedRows(ctx, allocator, query_trimmed, ranked, ranked.len);
    _ = ctx.service.drainScheduledRefresh(allocator) catch false;
    gtk_nav.selectFirstActionableRow(ctx);
}

pub fn renderSearchError(ctx: *UiContext, allocator: std.mem.Allocator, err: anyerror) void {
    const msg = std.fmt.allocPrint(allocator, "Search failed: {s}", .{@errorName(err)}) catch "Search failed";
    defer if (!std.mem.eql(u8, msg, "Search failed")) allocator.free(msg);

    gtk_widgets.clearList(ctx.list);
    gtk_widgets.appendInfoRow(ctx.list, msg);
    ctx.last_render_hash = std.hash.Wyhash.hash(0x5ea2c8d7, msg);
    gtk_status.setStatus(ctx, "Search failed");
}

pub fn renderRankedRows(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    query_trimmed: []const u8,
    ranked: []const search_mod.ScoredCandidate,
    total_len: usize,
) void {
    const limit = @min(ranked.len, 20);
    const rows = ranked[0..limit];
    const empty_query = query_trimmed.len == 0;
    const route_hint = gtk_query.routeHintForQuery(query_trimmed);
    const highlight_token = gtk_query.highlightTokenForQuery(query_trimmed);
    const has_app_glyph_fallback = gtk_icons.hasAppGlyphFallback(rows);
    const render_hash = gtk_render.computeRenderHash(query_trimmed, route_hint, rows, ranked.len);
    if (ctx.last_render_hash != render_hash) {
        gtk_widgets.clearList(ctx.list);
        if (route_hint) |hint| {
            gtk_widgets.appendInfoRow(ctx.list, hint);
        }
        if (rows.len == 0 and !empty_query and route_hint == null) {
            gtk_widgets.appendInfoRow(ctx.list, "No results");
            gtk_widgets.appendInfoRow(ctx.list, "Try routes: @ apps  # windows  ~ dirs  % files  & grep  > run  = calc  ? web");
        } else {
            gtk_render.appendGroupedRows(ctx, allocator, rows, highlight_token, .{ .candidate_icon_widget = gtk_icons.candidateIconWidget });
            if (total_len > limit) {
                gtk_widgets.appendInfoRow(ctx.list, "Showing top 20 results");
            }
        }
        ctx.last_render_hash = render_hash;
    }
    const query_flags = ctx.service.queryFlagsSnapshot();
    if (query_flags.last_query_used_stale_cache) {
        gtk_status.setStatus(ctx, "Refresh scheduled");
    } else if (query_flags.last_query_refreshed_cache) {
        gtk_status.setStatus(ctx, "Snapshot refreshed");
    } else if (empty_query and has_app_glyph_fallback and ctx.pending_power_confirm == GFALSE) {
        gtk_status.setStatus(ctx, "App icon fallback active (headless :icondiag for breakdown)");
    } else if (empty_query and ctx.pending_power_confirm == GFALSE) {
        gtk_status.setStatus(ctx, "Esc close | Ctrl+R refresh | @ apps # windows ~ dirs % files & grep > run = calc ? web");
    } else if (ctx.pending_power_confirm == GFALSE) {
        gtk_status.setStatus(ctx, "");
    }
}

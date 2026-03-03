const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_controller = @import("controller.zig");
const gtk_async_coord = @import("async_coordinator.zig");
const gtk_results_flow = @import("results_flow.zig");
const search_mod = @import("../../search/mod.zig");
const gtk_preview = @import("preview.zig");
const gtk_nav = @import("navigation.zig");
const gtk_async = @import("async_state.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiContext = gtk_types.UiContext;

pub fn afterActivate(ctx: *UiContext) void {
    gtk_controller.updateEntryRouteIcon(ctx, "");
    ctx.service.kickAsyncStartupPrewarm();
    gtk_controller.enableStartupKeyQueue(ctx);
    if (ctx.startup_key_queue_id != 0) {
        _ = c.g_source_remove(ctx.startup_key_queue_id);
        ctx.startup_key_queue_id = 0;
    }
    ctx.startup_key_queue_id = c.g_timeout_add(220, onStartupKeyQueueTimeout, ctx);
    if (ctx.focus_ready_logged == GFALSE) {
        ctx.focus_ready_logged = GTRUE;
        logStartupMetric(ctx, "startup.focus_ready_ms");
    }
    if (ctx.startup_idle_id != 0) {
        _ = c.g_source_remove(ctx.startup_idle_id);
        ctx.startup_idle_id = 0;
    }
    ctx.startup_idle_id = c.g_idle_add(onStartupReady, ctx);
}

fn onStartupReady(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    ctx.startup_idle_id = 0;

    const entry_text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
    const entry_query = if (entry_text_ptr != null)
        std.mem.span(@as([*:0]const u8, @ptrCast(entry_text_ptr)))
    else
        "";
    const persisted_query = getPersistedQuery(ctx);
    const query = if (entry_query.len > 0) entry_query else persisted_query;
    if (entry_query.len == 0 and persisted_query.len > 0) {
        hydrateEntryTextFromQuery(ctx, persisted_query);
    }
    const query_trimmed = std.mem.trim(u8, query, " \t\r\n");
    storeQueryText(ctx, query_trimmed);
    populateResults(ctx, query_trimmed);
    gtk_nav.updateScrollbarActiveClass(ctx);
    restoreListState(ctx);
    return GFALSE;
}

fn onStartupKeyQueueTimeout(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    ctx.startup_key_queue_id = 0;
    gtk_controller.flushAndDisableStartupKeyQueue(ctx);
    return GFALSE;
}

fn populateResults(ctx: *UiContext, query: []const u8) void {
    gtk_results_flow.populateResults(ctx, query, .{
        .start_async_route_search = startAsyncRouteSearch,
        .cancel_async_route_search = cancelAsyncRouteSearch,
    });
    gtk_preview.refreshFromSelection(ctx);
}

fn startAsyncRouteSearch(ctx: *UiContext, allocator: std.mem.Allocator, query_trimmed: []const u8) void {
    gtk_async_coord.startAsyncRouteSearch(ctx, allocator, query_trimmed, onAsyncSearchReady);
}

fn launchPendingAsyncQuery(ctx: *UiContext, allocator: std.mem.Allocator) bool {
    return gtk_async_coord.launchPendingAsyncQuery(ctx, allocator, onAsyncSearchReady);
}

fn cancelAsyncRouteSearch(ctx: *UiContext) void {
    gtk_async_coord.cancelAsyncRouteSearch(ctx);
}

fn onAsyncSearchReady(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const payload: *gtk_async.AsyncSearchResult = @ptrCast(@alignCast(user_data.?));
    const ctx = payload.ctx;
    gtk_async_coord.clearAsyncReadySourceIdIf(ctx, payload.ready_source_id);
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    if (gtk_async_coord.isAsyncShuttingDown(ctx)) return GFALSE;
    ctx.async_worker_active = GFALSE;
    if (payload.generation != ctx.async_search_generation) {
        if (!launchPendingAsyncQuery(ctx, allocator)) {
            gtk_async_coord.endAsyncSpinner(ctx);
            gtk_nav.selectFirstActionableRow(ctx);
        }
        return GFALSE;
    }

    gtk_async_coord.endAsyncSpinner(ctx);
    if (payload.search_error) |err| {
        gtk_results_flow.renderSearchError(ctx, allocator, err);
        gtk_nav.selectFirstActionableRow(ctx);
        return GFALSE;
    }

    var scored = allocator.alloc(search_mod.ScoredCandidate, payload.rows.len) catch return GFALSE;
    defer allocator.free(scored);
    for (payload.rows, 0..) |row, idx| {
        scored[idx] = .{
            .candidate = .{
                .kind = row.kind,
                .title = row.title,
                .subtitle = row.subtitle,
                .action = row.action,
                .icon = row.icon,
            },
            .score = row.score,
        };
    }

    gtk_results_flow.renderRankedRows(ctx, allocator, std.mem.trim(u8, payload.query, " \t\r\n"), scored, payload.total_len);
    restoreListState(ctx);
    return GFALSE;
}

pub fn storeQueryText(ctx: *UiContext, query: []const u8) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    if (ctx.last_query_text) |query_ptr| {
        allocator.free(query_ptr[0..ctx.last_query_len]);
        ctx.last_query_text = null;
        ctx.last_query_len = 0;
    }
    if (query.len == 0) return;
    const query_copy = allocator.dupe(u8, query) catch return;
    ctx.last_query_text = query_copy.ptr;
    ctx.last_query_len = query_copy.len;
}

pub fn clearStoredQuery(ctx: *UiContext) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    if (ctx.last_query_text) |query_ptr| {
        allocator.free(query_ptr[0..ctx.last_query_len]);
        ctx.last_query_text = null;
        ctx.last_query_len = 0;
    }
}

fn getPersistedQuery(ctx: *UiContext) []const u8 {
    if (ctx.last_query_text) |query_ptr| {
        return query_ptr[0..ctx.last_query_len];
    }
    return "";
}

fn hydrateEntryTextFromQuery(ctx: *UiContext, query: []const u8) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    const query_z = allocator.dupeZ(u8, query) catch return;
    defer allocator.free(query_z);
    c.gtk_editable_set_text(@ptrCast(ctx.entry), query_z.ptr);
    c.gtk_editable_set_position(@ptrCast(ctx.entry), -1);
}

fn restoreListState(ctx: *UiContext) void {
    var restored = false;
    if (ctx.last_selected_row_index >= 0) {
        const row = c.gtk_list_box_get_row_at_index(@ptrCast(ctx.list), ctx.last_selected_row_index);
        if (row != null) {
            c.gtk_list_box_select_row(@ptrCast(ctx.list), row);
            restored = true;
        }
    }
    if (!restored) {
        gtk_nav.selectFirstActionableRow(ctx);
    }

    const adjustment = c.gtk_scrolled_window_get_vadjustment(@ptrCast(ctx.scroller));
    if (adjustment == null) return;
    const page_size = c.gtk_adjustment_get_page_size(adjustment);
    const upper = c.gtk_adjustment_get_upper(adjustment);
    const max = @max(0.0, upper - page_size);
    const target = if (ctx.last_scroll_position < 0.0)
        0.0
    else if (ctx.last_scroll_position > max)
        max
    else
        ctx.last_scroll_position;
    c.gtk_adjustment_set_value(adjustment, target);
    gtk_nav.ensureSelectedRowVisible(ctx);
}

fn logStartupMetric(ctx: *UiContext, metric_name: []const u8) void {
    const now_ns = std.time.nanoTimestamp();
    const diff_ns = now_ns - ctx.launch_start_ns;
    const elapsed_ns: u64 = if (diff_ns <= 0) 0 else @as(u64, @intCast(diff_ns));
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    std.log.info("{s}={d:.2}", .{ metric_name, elapsed_ms });
}

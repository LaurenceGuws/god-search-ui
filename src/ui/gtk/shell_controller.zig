const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_query = @import("query_helpers.zig");
const gtk_async_coord = @import("async_coordinator.zig");
const gtk_async = @import("async_state.zig");
const gtk_nav = @import("navigation.zig");
const gtk_results_flow = @import("results_flow.zig");
const gtk_controller = @import("controller.zig");
const gtk_shell_lifecycle = @import("shell_lifecycle.zig");
const gtk_shell_startup = @import("shell_startup.zig");
const gtk_deferred_clear = @import("deferred_clear.zig");
const gtk_preview = @import("preview.zig");
const search_mod = @import("../../search/mod.zig");
const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;

pub const Hooks = struct {
    clear_power_confirmation: *const fn (*gtk_types.UiContext) void,
    set_status: *const fn (*gtk_types.UiContext, []const u8) void,
    log_startup_metric: *const fn (*gtk_types.UiContext, []const u8) void,
    populate_results: *const fn (*gtk_types.UiContext, []const u8) void,
};

pub fn onSearchChanged(ctx: *gtk_types.UiContext, hooks: Hooks) void {
    hooks.clear_power_confirmation(ctx);

    if (ctx.search_debounce_id != 0) {
        _ = c.g_source_remove(ctx.search_debounce_id);
        ctx.search_debounce_id = 0;
    }
    const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
    const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
    if (ctx.first_input_logged == GFALSE and query.len > 0) {
        ctx.first_input_logged = GTRUE;
        hooks.log_startup_metric(ctx, "startup.first_input_ms");
    }
    if (query.len > 0 and ctx.startup_key_queue_active == GTRUE) {
        if (ctx.startup_key_queue_id != 0) {
            _ = c.g_source_remove(ctx.startup_key_queue_id);
            ctx.startup_key_queue_id = 0;
        }
        gtk_controller.flushAndDisableStartupKeyQueue(ctx);
    }
    gtk_controller.updateEntryRouteIcon(ctx, query);
    gtk_shell_startup.storeQueryText(ctx, query);
    if (std.mem.trim(u8, query, " \t\r\n").len == 0) {
        cancelAsyncRouteSearch(ctx);
    }
    if (ctx.pending_power_confirm == GFALSE) {
        hooks.set_status(ctx, "Searching...");
    }
    const debounce_ms = gtk_query.searchDebounceMsForQuery(std.mem.trim(u8, query, " \t\r\n"));
    ctx.search_debounce_id = c.g_timeout_add(debounce_ms, onSearchDebouncedTimeout, ctx);
}

pub fn onSearchDebounced(ctx: *gtk_types.UiContext, hooks: Hooks) c.gboolean {
    ctx.search_debounce_id = 0;

    const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
    if (text_ptr == null) {
        hooks.populate_results(ctx, "");
        return GFALSE;
    }
    const query = std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr)));
    gtk_shell_startup.storeQueryText(ctx, query);
    hooks.populate_results(ctx, query);
    return GFALSE;
}

fn onSearchDebouncedTimeout(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *gtk_types.UiContext = @ptrCast(@alignCast(user_data.?));
    return onSearchDebounced(ctx, .{
        .clear_power_confirmation = noopClearPowerConfirmation,
        .set_status = noopSetStatus,
        .log_startup_metric = noopLogStartupMetric,
        .populate_results = populateResults,
    });
}

pub fn populateResults(ctx: *gtk_types.UiContext, query: []const u8) void {
    gtk_results_flow.populateResults(ctx, query, .{
        .start_async_route_search = startAsyncRouteSearch,
        .cancel_async_route_search = cancelAsyncRouteSearch,
    });
}

pub fn pollMoreResults(ctx: *gtk_types.UiContext, hooks: Hooks) void {
    if (!gtk_results_flow.shouldPollMoreOnScroll(ctx)) return;
    const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
    const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
    hooks.populate_results(ctx, query);
}

pub fn startAsyncRouteSearch(ctx: *gtk_types.UiContext, allocator: std.mem.Allocator, query_trimmed: []const u8) void {
    gtk_async_coord.startAsyncRouteSearch(ctx, allocator, query_trimmed, onAsyncSearchReadyShim);
}

pub fn cancelAsyncRouteSearch(ctx: *gtk_types.UiContext) void {
    gtk_async_coord.cancelAsyncRouteSearch(ctx);
}

pub fn launchPendingAsyncQuery(ctx: *gtk_types.UiContext, allocator: std.mem.Allocator) bool {
    return gtk_async_coord.launchPendingAsyncQuery(ctx, allocator, onAsyncSearchReadyShim);
}

pub fn onAsyncSearchReady(ctx: *gtk_types.UiContext, payload: *gtk_async.AsyncSearchResult, allocator: std.mem.Allocator) c.gboolean {
    gtk_async_coord.clearAsyncReadySourceIdIf(ctx, payload.ready_source_id);
    if (gtk_async_coord.isAsyncShuttingDown(ctx)) return GFALSE;
    ctx.async_worker_active = GFALSE;
    if (payload.generation != ctx.async_search_generation) {
        _ = launchPendingAsyncQuery(ctx, allocator);
        return GFALSE;
    }

    gtk_async_coord.endAsyncSpinner(ctx);
    if (payload.search_error) |err| {
        gtk_results_flow.renderSearchError(ctx, allocator, err);
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
    const query_trimmed = std.mem.trim(u8, payload.query, " \t\r\n");
    const had_selection = c.gtk_list_box_get_selected_row(@ptrCast(ctx.list)) != null;
    gtk_results_flow.cacheAndRenderAsyncRows(ctx, allocator, query_trimmed, scored, payload.total_len);
    if (!had_selection and ctx.result_window_limit <= 20) {
        gtk_nav.selectFirstActionableRow(ctx);
    }
    return GFALSE;
}

pub fn applyLauncherControlEvent(gtk_app: *c.GtkApplication, ui_ctx: ?*gtk_types.UiContext, event: @import("../../shell/mod.zig").module.Event, hooks: Hooks) void {
    switch (event) {
        .summon => if (ui_ctx) |ctx| {
            std.log.info(
                "ram_event=ui_summon query_hash={d} window_limit={d} visible={}",
                .{ ctx.result_query_hash, ctx.result_window_limit, c.gtk_widget_get_visible(ctx.window) == GTRUE },
            );
            summonExistingUi(ctx, hooks);
        } else c.g_application_activate(@ptrCast(gtk_app)),
        .hide => if (ui_ctx) |ctx| {
            hideSession(ctx, .control_hide);
        },
        .toggle => if (ui_ctx) |ctx| {
            if (c.gtk_widget_get_visible(ctx.window) == GTRUE) {
                hideSession(ctx, .control_toggle_hide);
            } else {
                std.log.info(
                    "ram_event=ui_toggle_show query_hash={d} window_limit={d}",
                    .{ ctx.result_query_hash, ctx.result_window_limit },
                );
                summonExistingUi(ctx, hooks);
            }
        } else c.g_application_activate(@ptrCast(gtk_app)),
        else => {},
    }
}

pub const HideReason = enum {
    escape,
    close_request,
    focus_lost,
    control_hide,
    control_toggle_hide,
};

pub fn hideSession(ctx: *gtk_types.UiContext, reason: HideReason) void {
    gtk_shell_lifecycle.captureListState(ctx);
    switch (reason) {
        .escape => std.log.info(
            "ram_event=ui_escape_hide query_hash={d} window_limit={d}",
            .{ ctx.result_query_hash, ctx.result_window_limit },
        ),
        .close_request => std.log.info(
            "ram_event=ui_close_request query_hash={d} window_limit={d} clear_query_on_close={}",
            .{
                ctx.result_query_hash,
                ctx.result_window_limit,
                ctx.clear_query_on_close == GTRUE,
            },
        ),
        .focus_lost => std.log.info(
            "ram_event=ui_focus_lost_hide query_hash={d} window_limit={d}",
            .{ ctx.result_query_hash, ctx.result_window_limit },
        ),
        .control_hide => std.log.info(
            "ram_event=ui_hide request query_hash={d} window_limit={d}",
            .{ ctx.result_query_hash, ctx.result_window_limit },
        ),
        .control_toggle_hide => std.log.info(
            "ram_event=ui_toggle_hide request query_hash={d} window_limit={d}",
            .{ ctx.result_query_hash, ctx.result_window_limit },
        ),
    }
    gtk_deferred_clear.request(ctx);
    gtk_preview.cancelPendingWork(ctx);
    if (reason == .close_request and ctx.clear_query_on_close == GTRUE) {
        clearQueryOnClose(ctx);
    }
    c.gtk_widget_set_visible(ctx.window, GFALSE);
}

pub fn onCloseRequest(ctx: *gtk_types.UiContext) c.gboolean {
    if (ctx.resident_mode != GTRUE) return GFALSE;
    hideSession(ctx, .close_request);
    return GTRUE;
}

pub fn onWindowFocusLost(ctx: *gtk_types.UiContext) void {
    if (ctx.resident_mode != GTRUE) return;
    if (c.gtk_widget_get_visible(ctx.window) != GTRUE) return;
    hideSession(ctx, .focus_lost);
}

fn summonExistingUi(ui_ctx: *gtk_types.UiContext, hooks: Hooks) void {
    c.gtk_window_present(@ptrCast(ui_ctx.window));
    _ = c.gtk_entry_grab_focus_without_selecting(@ptrCast(@alignCast(ui_ctx.entry)));
    const text_ptr = c.gtk_editable_get_text(@ptrCast(ui_ctx.entry));
    const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
    if (std.mem.trim(u8, query, " \t\r\n").len == 0) {
        ui_ctx.last_render_hash = 0;
        ui_ctx.last_selected_row_index = -1;
        ui_ctx.last_scroll_position = 0;
        hooks.populate_results(ui_ctx, "");
    }
    gtk_shell_startup.afterActivate(ui_ctx);
}

fn onAsyncSearchReadyShim(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const payload: *gtk_async.AsyncSearchResult = @ptrCast(@alignCast(user_data.?));
    const ctx = payload.ctx;
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    return onAsyncSearchReady(ctx, payload, allocator_ptr.*);
}

fn noopClearPowerConfirmation(_: *gtk_types.UiContext) void {}
fn noopSetStatus(_: *gtk_types.UiContext, _: []const u8) void {}
fn noopLogStartupMetric(_: *gtk_types.UiContext, _: []const u8) void {}

fn clearQueryOnClose(ctx: *gtk_types.UiContext) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    c.gtk_editable_set_text(@ptrCast(ctx.entry), "");
    c.gtk_editable_set_position(@ptrCast(ctx.entry), -1);
    ctx.last_selected_row_index = -1;
    ctx.last_scroll_position = 0;
    if (ctx.last_query_text) |query_ptr| {
        allocator.free(query_ptr[0..ctx.last_query_len]);
        ctx.last_query_text = null;
        ctx.last_query_len = 0;
    }
    ctx.clear_query_on_close = GFALSE;
}

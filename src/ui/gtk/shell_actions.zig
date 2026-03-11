const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_async = @import("async_state.zig");
const gtk_icons = @import("icons.zig");
const gtk_widgets = @import("widgets.zig");
const gtk_status = @import("status.zig");
const gtk_preview = @import("preview.zig");
const gtk_nav = @import("navigation.zig");
const gtk_menus = @import("menus.zig");
const providers_mod = @import("../../providers/mod.zig");
const search_mod = @import("../../search/mod.zig");
const config_mod = @import("../../config/mod.zig");
const runtime_tools = @import("../../config/runtime_tools.zig");
const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;

pub const Hooks = struct {
    set_status: *const fn (*gtk_types.UiContext, []const u8) void,
    populate_results: *const fn (*gtk_types.UiContext, []const u8) void,
};

pub fn refreshSnapshot(ctx: *gtk_types.UiContext, hooks: Hooks) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
    const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
    const parsed_query = search_mod.parseQuery(query);
    @import("shell_startup.zig").storeQueryText(ctx, query);
    if (refreshUnsupportedMessageForQuery(query)) |msg| {
        hooks.set_status(ctx, msg);
        return;
    }

    _ = parsed_query;
    gtk_async.clearAsyncSearchCache(ctx, allocator);
    ctx.service.clearDynamicState(allocator);
    providers_mod.invalidateWebCaches();
    providers_mod.invalidateAppsCache();
    gtk_icons.invalidateYaziIconCache();
    ctx.service.invalidateSnapshot();
    switch (ctx.service.scheduleRefreshFromEvent()) {
        .scheduled => beginRefreshSpinner(ctx, hooks),
        .skipped_running => beginRefreshSpinner(ctx, hooks),
        .failed_spawn => hooks.set_status(ctx, "Refresh failed"),
    }
}

pub fn reloadConfig(ctx: *gtk_types.UiContext, hooks: Hooks) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    var cfg = config_mod.load(allocator);
    defer cfg.deinit(allocator);
    if (config_mod.consumeLastLoadIssue(allocator)) |issue| {
        defer allocator.free(issue);
        config_mod.issue_notice.show(issue, "Fix config.lua and reload config (Ctrl+Shift+R).");
        hooks.set_status(ctx, "Config invalid: kept current settings (check notification)");
        return;
    }
    runtime_tools.apply(cfg);
    ctx.show_nerd_stats = if (cfg.ui.show_nerd_stats) GTRUE else GFALSE;
    gtk_async.clearAsyncSearchCache(ctx, allocator);
    ctx.service.clearDynamicState(allocator);
    gtk_icons.invalidateYaziIconCache();
    config_mod.issue_notice.clearIfActive();
    hooks.set_status(ctx, "Config reloaded");
}

pub fn showDirActionMenu(ctx: *gtk_types.UiContext, allocator: std.mem.Allocator, dir_path: []const u8, hooks: Hooks) void {
    gtk_menus.showDirActionMenu(ctx, allocator, dir_path, .{
        .set_status = hooks.set_status,
        .select_first = gtk_nav.selectFirstActionableRow,
    });
}

pub fn showFileActionMenu(ctx: *gtk_types.UiContext, allocator: std.mem.Allocator, file_action: []const u8, hooks: Hooks) void {
    gtk_menus.showFileActionMenu(ctx, allocator, file_action, .{
        .set_status = hooks.set_status,
        .select_first = gtk_nav.selectFirstActionableRow,
    });
}

pub fn showLaunchFeedback(ctx: *gtk_types.UiContext, message: []const u8) void {
    gtk_status.showLaunchFeedback(ctx, message, .{
        .select_first = gtk_nav.selectFirstActionableRow,
    });
}

pub fn setStatus(ctx: *gtk_types.UiContext, message: []const u8) void {
    gtk_status.setStatus(ctx, message);
}

pub fn togglePreview(ctx: *gtk_types.UiContext) void {
    gtk_preview.toggle(ctx);
}

fn beginRefreshSpinner(ctx: *gtk_types.UiContext, hooks: Hooks) void {
    ctx.refresh_inflight = GTRUE;
    if (ctx.refresh_spinner_id != 0) return;
    ctx.refresh_spinner_phase = 0;
    updateRefreshSpinnerFrame(ctx, hooks);
    ctx.refresh_spinner_id = c.g_timeout_add(120, onRefreshSpinnerTick, ctx);
}

fn endRefreshSpinner(ctx: *gtk_types.UiContext) void {
    ctx.refresh_inflight = GFALSE;
    if (ctx.refresh_spinner_id != 0) {
        _ = c.g_source_remove(ctx.refresh_spinner_id);
        ctx.refresh_spinner_id = 0;
    }
    gtk_widgets.clearAsyncRows(ctx.list);
    ctx.last_render_hash = 0;
}

fn onRefreshSpinnerTick(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *gtk_types.UiContext = @ptrCast(@alignCast(user_data.?));
    if (ctx.refresh_inflight == GFALSE) {
        ctx.refresh_spinner_id = 0;
        return GFALSE;
    }
    if (!ctx.service.refreshInFlight()) {
        endRefreshSpinner(ctx);
        const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
        const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
        setStatus(ctx, "Snapshot refreshed");
        @import("shell_controller.zig").populateResults(ctx, query);
        return GFALSE;
    }
    updateRefreshSpinnerFrame(ctx, .{
        .set_status = setStatus,
        .populate_results = @import("shell_controller.zig").populateResults,
    });
    return GTRUE;
}

fn updateRefreshSpinnerFrame(ctx: *gtk_types.UiContext, hooks: Hooks) void {
    _ = hooks;
    const frames = [_][]const u8{ "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏", "⠋", "⠙" };
    const frame = frames[ctx.refresh_spinner_phase % frames.len];
    ctx.refresh_spinner_phase +%= 1;
    gtk_widgets.clearAsyncRows(ctx.list);
    gtk_widgets.appendAsyncRow(ctx.list, frame, "Refreshing cached modules...");
    ctx.last_render_hash = 0;
    if (ctx.pending_power_confirm == GFALSE) {
        var status_buf: [40]u8 = undefined;
        const status_msg = std.fmt.bufPrint(&status_buf, "{s} Refreshing cache...", .{frame}) catch "Refreshing cache...";
        setStatus(ctx, status_msg);
    }
}

fn refreshUnsupportedMessageForQuery(query: []const u8) ?[]const u8 {
    const parsed = search_mod.parseQuery(query);
    return switch (parsed.route) {
        .calc => "Calculator updates as you type (no cache refresh needed)",
        .grep => "Grep runs live with rg (no cache refresh needed)",
        .files => "File search runs live with fd (no cache refresh needed)",
        .notifications => "Notifications route is live (no cache refresh needed)",
        .run => "Run command executes live (no cache refresh needed)",
        else => null,
    };
}

const std = @import("std");
const search_mod = @import("../../search/mod.zig");
const history_access = @import("../../app/search_service/history_access.zig");
const gtk_types = @import("types.zig");
const gtk_render = @import("render.zig");
const gtk_icons = @import("icons.zig");
const gtk_nav = @import("navigation.zig");
const gtk_widgets = @import("widgets.zig");
const gtk_status = @import("status.zig");

const UiContext = gtk_types.UiContext;
const c = gtk_types.c;
const GFALSE = gtk_types.GFALSE;

pub fn render(ctx: *UiContext, allocator: std.mem.Allocator, hot_render_rows: usize, on_refresh_pending: *const fn (*UiContext) void) void {
    switch (ctx.service.staticQueryExecution()) {
        .ready => {},
        .refreshing, .cache_cold => {
            _ = ctx.service.scheduleRefreshFromEvent();
            on_refresh_pending(ctx);
            return;
        },
    }

    const apps = ctx.service.searchQuery(allocator, "@ ") catch {
        renderUnavailable(ctx);
        return;
    };
    defer allocator.free(apps);

    const dirs = ctx.service.searchQuery(allocator, "~ ") catch {
        renderUnavailable(ctx);
        return;
    };
    defer allocator.free(dirs);

    var history: []const []const u8 = &.{};
    var history_owned = false;
    if (ctx.service.historySnapshotNewestFirstOwned(allocator)) |snapshot| {
        history = snapshot;
        history_owned = true;
    } else |_| {}
    defer if (history_owned) history_access.freeSnapshot(allocator, history);

    var merged = std.ArrayList(search_mod.ScoredCandidate).empty;
    defer merged.deinit(allocator);

    appendScoredRows(&merged, allocator, apps, history);

    var zide_dirs_added: usize = 0;
    for (dirs) |row| {
        if (!isZideDirCandidate(row.candidate)) continue;
        appendScoredRow(&merged, allocator, row, history) catch break;
        zide_dirs_added += 1;
    }

    if (zide_dirs_added == 0) {
        appendScoredRows(&merged, allocator, dirs, history);
    }

    const had_selection = c.gtk_list_box_get_selected_row(@ptrCast(ctx.list)) != null;
    gtk_widgets.clearList(ctx.list);
    gtk_widgets.appendModuleFilterMenu(ctx.list, allocator);
    if (merged.items.len > 0) {
        std.mem.sort(search_mod.ScoredCandidate, merged.items, {}, loadoutLessThan);
        gtk_widgets.appendSectionSeparatorRow(ctx.list);
        gtk_widgets.appendHeaderRow(ctx.list, "Suggested For You");
        gtk_render.appendOrderedRows(ctx, allocator, merged.items, "", .{
            .candidate_icon_widget = gtk_icons.candidateIconWidget,
        });
        ctx.last_render_hash = std.hash.Wyhash.hash(0x4dd8f0, "default-loadout-with-modules");
    } else {
        ctx.last_render_hash = std.hash.Wyhash.hash(0x4dd8f0, "default-loadout-modules-only");
    }
    if (!had_selection and ctx.result_window_limit <= hot_render_rows) {
        gtk_nav.selectFirstActionableRow(ctx);
    }
}

fn renderUnavailable(ctx: *UiContext) void {
    gtk_widgets.clearList(ctx.list);
    gtk_widgets.appendInfoRow(ctx.list, "Default loadout unavailable");
    ctx.last_render_hash = std.hash.Wyhash.hash(0x91f3aa, "default-loadout-unavailable");
    if (ctx.pending_power_confirm == GFALSE) {
        gtk_status.setStatus(ctx, "Type to search");
    }
}

fn appendScoredRows(
    merged: *std.ArrayList(search_mod.ScoredCandidate),
    allocator: std.mem.Allocator,
    rows: []const search_mod.ScoredCandidate,
    history: []const []const u8,
) void {
    for (rows) |row| {
        appendScoredRow(merged, allocator, row, history) catch break;
    }
}

fn appendScoredRow(
    merged: *std.ArrayList(search_mod.ScoredCandidate),
    allocator: std.mem.Allocator,
    row: search_mod.ScoredCandidate,
    history: []const []const u8,
) !void {
    const freq = actionFrequency(row.candidate.action, history);
    try merged.append(allocator, .{
        .candidate = row.candidate,
        .score = @as(i32, @intCast(freq * 1000)),
    });
}

fn actionFrequency(action: []const u8, history: []const []const u8) u32 {
    var count: u32 = 0;
    for (history) |entry| {
        if (std.mem.eql(u8, entry, action)) count += 1;
    }
    return count;
}

fn isZideDirCandidate(candidate: search_mod.Candidate) bool {
    if (candidate.kind != .dir) return false;
    return std.mem.indexOf(u8, candidate.action, "/zide") != null or
        std.mem.indexOf(u8, candidate.subtitle, "/zide") != null or
        std.mem.indexOf(u8, candidate.title, "zide") != null;
}

fn loadoutLessThan(_: void, a: search_mod.ScoredCandidate, b: search_mod.ScoredCandidate) bool {
    if (a.score != b.score) return a.score > b.score;
    const title_order = std.mem.order(u8, a.candidate.title, b.candidate.title);
    if (title_order != .eq) return title_order == .lt;
    return std.mem.order(u8, a.candidate.action, b.candidate.action) == .lt;
}

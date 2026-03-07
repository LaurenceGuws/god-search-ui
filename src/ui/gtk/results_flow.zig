const std = @import("std");
const search_mod = @import("../../search/mod.zig");
const history_access = @import("../../app/search_service/history_access.zig");
const gtk_types = @import("types.zig");
const gtk_async_state = @import("async_state.zig");
const gtk_query = @import("query_helpers.zig");
const gtk_render = @import("render.zig");
const gtk_icons = @import("icons.zig");
const gtk_nav = @import("navigation.zig");
const gtk_widgets = @import("widgets.zig");
const gtk_status = @import("status.zig");
const gtk_deferred_clear = @import("deferred_clear.zig");

const UiContext = gtk_types.UiContext;
const c = gtk_types.c;
const GFALSE = gtk_types.GFALSE;
const GTRUE = gtk_types.GTRUE;
const hot_render_rows: usize = 20;
const max_poll_windows: usize = 10;
const max_polled_rows: usize = hot_render_rows * max_poll_windows;
const default_async_cache_ttl_ns: i128 = 10 * std.time.ns_per_s;

pub const AsyncHooks = struct {
    start_async_route_search: *const fn (*UiContext, std.mem.Allocator, []const u8) void,
    cancel_async_route_search: *const fn (*UiContext) void,
};

pub fn populateResults(ctx: *UiContext, query: []const u8, hooks: AsyncHooks) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    const query_trimmed = std.mem.trim(u8, query, " \t\r\n");
    const hash = std.hash.Wyhash.hash(0x1fe2cd, query_trimmed);
    const current_dynamic = gtk_query.shouldAsyncRouteQuery(query_trimmed);
    if (ctx.result_query_hash != hash) {
        ctx.result_query_hash = hash;
        ctx.result_total_len = 0;
        ctx.result_window_limit = hot_render_rows;
        gtk_async_state.clearAsyncSearchCache(ctx, allocator);
    }

    if (query_trimmed.len == 0) {
        if (ctx.last_query_dynamic == GTRUE) {
            gtk_deferred_clear.request(ctx);
        }
        ctx.last_query_dynamic = GFALSE;
        ctx.active_query_hash = 0;
        ctx.active_query_started_ns = 0;
        gtk_async_state.clearAsyncSearchCache(ctx, allocator);
        hooks.cancel_async_route_search(ctx);
        renderDefaultLoadout(ctx, allocator);
        return;
    }
    ctx.last_query_dynamic = if (current_dynamic) GTRUE else GFALSE;
    if (ctx.active_query_hash != hash) {
        ctx.active_query_hash = hash;
        ctx.active_query_started_ns = std.time.nanoTimestamp();
    }

    if (current_dynamic) {
        if (renderFromAsyncCache(ctx, allocator, query_trimmed)) {
            return;
        }
        std.log.info("results_flow.populate start async route_query={s} hash={d}", .{ query_trimmed, hash });
        hooks.start_async_route_search(ctx, allocator, query_trimmed);
        return;
    }
    hooks.cancel_async_route_search(ctx);

    switch (ctx.service.staticQueryExecution()) {
        .ready => {},
        .refreshing, .cache_cold => {
            _ = ctx.service.scheduleRefreshFromEvent();
            renderStaticRefreshPending(ctx);
            return;
        },
    }

    const ranked = ctx.service.searchQuery(allocator, query) catch |err| {
        renderSearchError(ctx, allocator, err);
        return;
    };
    defer allocator.free(ranked);

    const had_selection = c.gtk_list_box_get_selected_row(@ptrCast(ctx.list)) != null;
    renderWithScrollRetention(ctx, allocator, query_trimmed, ranked, ranked.len);
    _ = ctx.service.maybeStartRequestedRefreshWorker();
    if (!had_selection and ctx.result_window_limit <= hot_render_rows) {
        gtk_nav.selectFirstActionableRow(ctx);
    }
}

fn renderStaticRefreshPending(ctx: *UiContext) void {
    gtk_widgets.clearList(ctx.list);
    gtk_widgets.appendAsyncRow(ctx.list, "⟳", "Refreshing cached modules...");
    ctx.last_render_hash = 0;
    gtk_status.setStatus(ctx, "⟳ Refreshing cache...");
}

fn renderFromAsyncCache(ctx: *UiContext, allocator: std.mem.Allocator, query_trimmed: []const u8) bool {
    const hash = std.hash.Wyhash.hash(0x1fe2cd, query_trimmed);
    if (!gtk_async_state.asyncCacheKnownForQuery(ctx, hash)) return false;
    const cached_rows: []const search_mod.ScoredCandidate = if (gtk_async_state.asyncCachedRows(ctx, hash)) |rows|
        rows
    else
        &[_]search_mod.ScoredCandidate{};
    const parsed_query = search_mod.parseQuery(query_trimmed);
    const cache_ttl_ns = asyncCacheTtlNsForRoute(parsed_query.route);
    const created_ns = gtk_async_state.asyncCacheCreatedNs(ctx, hash);
    const now_ns = std.time.nanoTimestamp();
    if (created_ns > 0 and now_ns > created_ns and now_ns - created_ns > cache_ttl_ns) {
        std.log.info("results_flow.cache invalidated query={s} reason=ttl_expired age_ns={d}", .{
            query_trimmed,
            now_ns - created_ns,
        });
        gtk_async_state.clearAsyncSearchCache(ctx, allocator);
        return false;
    }
    if ((parsed_query.route == .grep or parsed_query.route == .files) and cachedRowsContainMissingPaths(cached_rows)) {
        std.log.info("results_flow.cache invalidated query={s} reason=missing_paths", .{query_trimmed});
        gtk_async_state.clearAsyncSearchCache(ctx, allocator);
        return false;
    }
    const total_len = gtk_async_state.asyncCachedTotalLen(ctx, hash);
    const route_hint = gtk_query.routeHintForQuery(query_trimmed);
    std.log.info(
        "results_flow.cache hit query={s} total={d} cached={d} route_hint={s} window_limit={d}",
        .{
            query_trimmed,
            total_len,
            cached_rows.len,
            route_hint orelse "",
            ctx.result_window_limit,
        },
    );
    renderWithScrollRetention(ctx, allocator, query_trimmed, cached_rows, total_len);
    return true;
}

fn asyncCacheTtlNsForRoute(route: search_mod.Route) i128 {
    return switch (route) {
        .grep, .files => 8 * std.time.ns_per_s,
        .packages, .icons, .web => 20 * std.time.ns_per_s,
        .nerd_icons, .emoji, .notifications => 60 * std.time.ns_per_s,
        .calc => 5 * std.time.ns_per_s,
        else => default_async_cache_ttl_ns,
    };
}

fn cachedRowsContainMissingPaths(rows: []const search_mod.ScoredCandidate) bool {
    for (rows) |row| {
        const candidate = row.candidate;
        const path = switch (candidate.kind) {
            .grep => grepActionPath(candidate.action),
            .file, .dir => std.mem.trim(u8, candidate.action, " \t\r\n"),
            else => "",
        };
        if (path.len == 0) continue;
        if (!pathExists(path)) return true;
    }
    return false;
}

fn grepActionPath(action: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, action, " \t\r\n");
    if (trimmed.len == 0) return "";
    if (std.mem.lastIndexOfScalar(u8, trimmed, ':')) |idx| {
        if (idx + 1 < trimmed.len and isDigitsOnly(trimmed[idx + 1 ..])) {
            return trimmed[0..idx];
        }
    }
    return trimmed;
}

fn isDigitsOnly(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |ch| {
        if (!std.ascii.isDigit(ch)) return false;
    }
    return true;
}

fn pathExists(path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        std.fs.accessAbsolute(path, .{}) catch return false;
        return true;
    }
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn cacheAndRenderAsyncRows(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    query: []const u8,
    ranked: []const search_mod.ScoredCandidate,
    total_len: usize,
) void {
    const query_trimmed = std.mem.trim(u8, query, " \t\r\n");
    const hash = std.hash.Wyhash.hash(0x1fe2cd, query_trimmed);
    const parsed_query = search_mod.parseQuery(query_trimmed);
    const route = @tagName(parsed_query.route);
    gtk_async_state.cacheAsyncSearchRows(
        ctx,
        allocator,
        hash,
        total_len,
        ranked,
        route,
        parsed_query.term.len,
        @as(usize, ctx.result_window_limit),
    );
    std.log.info(
        "results_flow.cache store query={s} total={d} rows={d} query_hash={d}",
        .{ query_trimmed, total_len, ranked.len, hash },
    );
    renderWithScrollRetention(ctx, allocator, query_trimmed, ranked, total_len);
}

fn renderWithScrollRetention(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    query_trimmed: []const u8,
    ranked: []const search_mod.ScoredCandidate,
    total_len: usize,
) void {
    const selected_row = c.gtk_list_box_get_selected_row(@ptrCast(ctx.list));
    const selected_index = if (selected_row != null)
        c.gtk_list_box_row_get_index(@ptrCast(selected_row))
    else
        -1;
    const adjustment = c.gtk_scrolled_window_get_vadjustment(@ptrCast(ctx.scroller));
    const previous_value = if (adjustment != null)
        c.gtk_adjustment_get_value(adjustment)
    else
        0.0;

    renderRankedRows(ctx, allocator, query_trimmed, ranked, total_len);

    if (adjustment == null) return;
    const upper = c.gtk_adjustment_get_upper(adjustment);
    const page = c.gtk_adjustment_get_page_size(adjustment);
    const max_value = @max(0.0, upper - page);
    c.gtk_adjustment_set_value(adjustment, @min(max_value, previous_value));

    if (selected_index >= 0) {
        const restored = c.gtk_list_box_get_row_at_index(@ptrCast(ctx.list), selected_index);
        if (restored != null) {
            c.gtk_list_box_select_row(@ptrCast(ctx.list), restored);
        }
    }
}

fn renderDefaultLoadout(ctx: *UiContext, allocator: std.mem.Allocator) void {
    switch (ctx.service.staticQueryExecution()) {
        .ready => {},
        .refreshing, .cache_cold => {
            _ = ctx.service.scheduleRefreshFromEvent();
            renderStaticRefreshPending(ctx);
            return;
        },
    }

    const apps = ctx.service.searchQuery(allocator, "@ ") catch {
        gtk_widgets.clearList(ctx.list);
        gtk_widgets.appendInfoRow(ctx.list, "Default loadout unavailable");
        ctx.last_render_hash = std.hash.Wyhash.hash(0x91f3aa, "default-loadout-unavailable");
        if (ctx.pending_power_confirm == GFALSE) {
            gtk_status.setStatus(ctx, "Type to search");
        }
        return;
    };
    defer allocator.free(apps);

    const dirs = ctx.service.searchQuery(allocator, "~ ") catch {
        gtk_widgets.clearList(ctx.list);
        gtk_widgets.appendInfoRow(ctx.list, "Default loadout unavailable");
        ctx.last_render_hash = std.hash.Wyhash.hash(0x91f3aa, "default-loadout-unavailable");
        if (ctx.pending_power_confirm == GFALSE) {
            gtk_status.setStatus(ctx, "Type to search");
        }
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

    for (apps) |row| {
        const freq = actionFrequency(row.candidate.action, history);
        merged.append(allocator, .{
            .candidate = row.candidate,
            .score = @as(i32, @intCast(freq * 1000)),
        }) catch break;
    }

    var zide_dirs_added: usize = 0;
    for (dirs) |row| {
        if (!isZideDirCandidate(row.candidate)) continue;
        const freq = actionFrequency(row.candidate.action, history);
        merged.append(allocator, .{
            .candidate = row.candidate,
            .score = @as(i32, @intCast(freq * 1000)),
        }) catch break;
        zide_dirs_added += 1;
    }

    if (zide_dirs_added == 0) {
        for (dirs) |row| {
            const freq = actionFrequency(row.candidate.action, history);
            merged.append(allocator, .{
                .candidate = row.candidate,
                .score = @as(i32, @intCast(freq * 1000)),
            }) catch break;
        }
    }

    if (merged.items.len == 0) {
        gtk_widgets.clearList(ctx.list);
        gtk_widgets.appendInfoRow(ctx.list, "No default suggestions");
        ctx.last_render_hash = std.hash.Wyhash.hash(0x4dd8f0, "default-loadout-empty");
        if (ctx.pending_power_confirm == GFALSE) {
            gtk_status.setStatus(ctx, "Type to search");
        }
        return;
    }

    std.mem.sort(search_mod.ScoredCandidate, merged.items, {}, loadoutLessThan);
    const had_selection = c.gtk_list_box_get_selected_row(@ptrCast(ctx.list)) != null;
    renderWithScrollRetention(ctx, allocator, "", merged.items, merged.items.len);
    if (!had_selection and ctx.result_window_limit <= hot_render_rows) {
        gtk_nav.selectFirstActionableRow(ctx);
    }
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

pub fn renderSearchError(ctx: *UiContext, allocator: std.mem.Allocator, err: anyerror) void {
    markUiQueryCompleted(ctx);
    ctx.result_total_len = 0;
    const dynamic_msg = switch (err) {
        error.StreamTooLong, error.StdoutStreamTooLong => null,
        else => std.fmt.allocPrint(allocator, "Search failed: {s}", .{@errorName(err)}) catch null,
    };
    defer if (dynamic_msg) |owned| allocator.free(owned);
    const msg = dynamic_msg orelse switch (err) {
        error.StreamTooLong, error.StdoutStreamTooLong => "Search output too large. Refine your query.",
        else => "Search failed",
    };

    gtk_widgets.clearList(ctx.list);
    gtk_widgets.appendInfoRow(ctx.list, msg);
    ctx.last_render_hash = std.hash.Wyhash.hash(0x5ea2c8d7, msg);
    if (ctx.pending_power_confirm == GFALSE) {
        gtk_status.setStatus(ctx, switch (err) {
            error.StreamTooLong, error.StdoutStreamTooLong => "Search output too large; refine query",
            else => "Search failed",
        });
    }
}

pub fn renderRankedRows(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    query_trimmed: []const u8,
    ranked: []const search_mod.ScoredCandidate,
    total_len: usize,
) void {
    markUiQueryCompleted(ctx);
    ctx.result_total_len = total_len;
    const limit = @min(ranked.len, @as(usize, @intCast(ctx.result_window_limit)));
    const rows = ranked[0..limit];
    const empty_query = query_trimmed.len == 0;
    const route_hint = gtk_query.routeHintForQuery(query_trimmed);
    const highlight_token = gtk_query.highlightTokenForQuery(query_trimmed);
    const has_app_glyph_fallback = gtk_icons.hasAppGlyphFallback(rows);
    const render_hash = gtk_render.computeRenderHash(query_trimmed, route_hint, rows, ranked.len, limit);
    if (ctx.last_render_hash != render_hash) {
        gtk_widgets.clearList(ctx.list);
        if (route_hint) |hint| {
            gtk_widgets.appendInfoRow(ctx.list, hint);
        }
        if (rows.len == 0 and !empty_query and route_hint == null) {
            gtk_widgets.appendInfoRow(ctx.list, "No results");
            gtk_widgets.appendInfoRow(ctx.list, "Try routes: @ apps  # windows  ! workspaces  ~ dirs  % files  & grep  + packages  ^ icons  * nerd  : emoji  > run  = calc  ? web");
        } else {
            if (empty_query and route_hint == null) {
                gtk_render.appendOrderedRows(ctx, allocator, rows, highlight_token, .{ .candidate_icon_widget = gtk_icons.candidateIconWidget });
            } else {
            gtk_render.appendGroupedRows(ctx, allocator, rows, highlight_token, .{ .candidate_icon_widget = gtk_icons.candidateIconWidget });
            }
            if (total_len > limit) {
                const more = std.fmt.allocPrint(allocator, "Showing top {d} results", .{limit}) catch "Showing results";
                defer if (!std.mem.eql(u8, more, "Showing results")) allocator.free(more);
                gtk_widgets.appendInfoRow(ctx.list, more);
            }
        }
        ctx.last_render_hash = render_hash;
    }
    const query_flags = ctx.service.queryFlagsSnapshot();
    if (ctx.pending_power_confirm == GTRUE) {
        return;
    }
    if (query_flags.last_query_had_provider_runtime_failure) {
        gtk_status.setStatus(ctx, "Some providers failed; results may be incomplete");
    } else if (query_flags.last_query_used_stale_cache) {
        gtk_status.setStatus(ctx, "Refresh scheduled");
    } else if (query_flags.last_query_refreshed_cache) {
        gtk_status.setStatus(ctx, "Snapshot refreshed");
    } else if (empty_query and has_app_glyph_fallback) {
        gtk_status.setStatus(ctx, "App icon fallback active (headless :icondiag for breakdown)");
    } else if (empty_query) {
        gtk_status.setStatus(ctx, "Esc close | Ctrl+P preview | Ctrl+R refresh | @ apps # windows ! workspaces ~ dirs % files & grep + packages ^ icons * nerd : emoji > run = calc ? web");
    } else {
        gtk_status.setStatus(ctx, "");
    }
}

fn markUiQueryCompleted(ctx: *UiContext) void {
    if (ctx.active_query_hash == 0 or ctx.active_query_started_ns <= 0) return;
    const now = std.time.nanoTimestamp();
    if (now <= ctx.active_query_started_ns) return;
    const elapsed_ns: u64 = @intCast(now - ctx.active_query_started_ns);
    ctx.last_ui_query_total_ns = elapsed_ns;
    ctx.active_query_started_ns = 0;
}

pub fn shouldPollMoreOnScroll(ctx: *UiContext) bool {
    const adjustment = c.gtk_scrolled_window_get_vadjustment(@ptrCast(ctx.scroller)) orelse return false;
    const value = c.gtk_adjustment_get_value(adjustment);
    const page = c.gtk_adjustment_get_page_size(adjustment);
    const upper = c.gtk_adjustment_get_upper(adjustment);
    if (upper <= page) return false;

    const remaining = upper - (value + page);
    if (remaining > 24.0) return false;

    const total_len = resultTotalLenForPolling(ctx);
    const current: usize = @intCast(ctx.result_window_limit);
    if (total_len <= current) return false;

    if (current >= max_polled_rows) return false;
    const next = if (current > max_polled_rows - hot_render_rows)
        max_polled_rows
    else
        current + hot_render_rows;
    if (next == current) return false;
    std.log.info("scroll poll increasing window {d} -> {d} for query_hash={d}", .{
        current,
        next,
        ctx.result_query_hash,
    });
    ctx.result_window_limit = @intCast(next);
    return true;
}

fn resultTotalLenForPolling(ctx: *UiContext) usize {
    if (gtk_async_state.asyncCacheKnownForQuery(ctx, ctx.result_query_hash)) {
        return gtk_async_state.asyncCachedTotalLen(ctx, ctx.result_query_hash);
    }
    return ctx.result_total_len;
}

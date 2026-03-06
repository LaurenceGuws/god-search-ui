const std = @import("std");
const gtk_types = @import("types.zig");
const CandidateKind = gtk_types.CandidateKind;
const search_mod = @import("../../search/mod.zig");
const UiContext = gtk_types.UiContext;

pub const AsyncRenderedRow = struct {
    kind: CandidateKind,
    score: i32,
    title: []u8,
    subtitle: []u8,
    action: []u8,
    icon: []u8,
};

pub const AsyncSearchResult = struct {
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    generation: u64,
    ready_source_id: gtk_types.c.guint,
    total_len: usize,
    query: []u8,
    rows: []AsyncRenderedRow,
    search_error: ?anyerror,
    on_ready: *const fn (?*anyopaque) callconv(.c) gtk_types.c.gboolean,
};

const min_cached_rows: usize = 80;
const max_cached_rows: usize = 400;

pub fn queuePendingAsyncQuery(ctx: *UiContext, allocator: std.mem.Allocator, query_owned: []u8) void {
    if (ctx.async_pending_query_ptr) |ptr| {
        const prev = ptr[0..ctx.async_pending_query_len];
        allocator.free(prev);
    }
    ctx.async_pending_query_ptr = query_owned.ptr;
    ctx.async_pending_query_len = query_owned.len;
}

pub fn clearAsyncSearchCache(ctx: *UiContext, allocator: std.mem.Allocator) void {
    if (ctx.async_cached_rows_ptr) |ptr| {
        const cached = ptr[0..ctx.async_cached_rows_len];
        for (cached) |cached_row| {
            if (cached_row.candidate.title.len > 0) allocator.free(cached_row.candidate.title);
            if (cached_row.candidate.subtitle.len > 0) allocator.free(cached_row.candidate.subtitle);
            if (cached_row.candidate.action.len > 0) allocator.free(cached_row.candidate.action);
            if (cached_row.candidate.icon.len > 0) allocator.free(cached_row.candidate.icon);
        }
        allocator.free(cached);
        ctx.async_cached_rows_ptr = null;
        ctx.async_cached_rows_len = 0;
    }
    ctx.async_cached_query_hash = 0;
    ctx.async_cached_total_len = 0;
    ctx.async_cached_created_ns = 0;
}

pub fn cacheAsyncSearchRows(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    query_hash: u64,
    total_len: usize,
    rows: []const search_mod.ScoredCandidate,
    route: []const u8,
    query_term_len: usize,
    window_limit: usize,
) void {
    clearAsyncSearchCache(ctx, allocator);
    const cache_cap = cacheCapForWindowLimit(window_limit);
    const keep_rows = @min(rows.len, cache_cap);
    if (rows.len > cache_cap) {
        std.log.warn("async cache truncated rows={d} kept={d} cap={d}", .{ rows.len, keep_rows, cache_cap });
    }
    if (keep_rows == 0) {
        ctx.async_cached_query_hash = query_hash;
        ctx.async_cached_total_len = total_len;
        ctx.async_cached_created_ns = std.time.nanoTimestamp();
        return;
    }
    const cached_rows = allocator.alloc(search_mod.ScoredCandidate, keep_rows) catch return;
    var copied: usize = 0;
    var cached_bytes: usize = 0;
    for (rows[0..keep_rows], 0..) |row, idx| {
        const title = allocator.dupe(u8, row.candidate.title) catch {
            for (cached_rows[0..copied]) |cached_row| {
                if (cached_row.candidate.title.len > 0) allocator.free(cached_row.candidate.title);
                if (cached_row.candidate.subtitle.len > 0) allocator.free(cached_row.candidate.subtitle);
                if (cached_row.candidate.action.len > 0) allocator.free(cached_row.candidate.action);
                if (cached_row.candidate.icon.len > 0) allocator.free(cached_row.candidate.icon);
            }
            allocator.free(cached_rows);
            return;
        };
        cached_bytes += title.len;
        const subtitle = allocator.dupe(u8, row.candidate.subtitle) catch {
            allocator.free(title);
            for (cached_rows[0..copied]) |cached_row| {
                if (cached_row.candidate.title.len > 0) allocator.free(cached_row.candidate.title);
                if (cached_row.candidate.subtitle.len > 0) allocator.free(cached_row.candidate.subtitle);
                if (cached_row.candidate.action.len > 0) allocator.free(cached_row.candidate.action);
                if (cached_row.candidate.icon.len > 0) allocator.free(cached_row.candidate.icon);
            }
            allocator.free(cached_rows);
            return;
        };
        cached_bytes += subtitle.len;
        const action = allocator.dupe(u8, row.candidate.action) catch {
            allocator.free(subtitle);
            allocator.free(title);
            for (cached_rows[0..copied]) |cached_row| {
                if (cached_row.candidate.title.len > 0) allocator.free(cached_row.candidate.title);
                if (cached_row.candidate.subtitle.len > 0) allocator.free(cached_row.candidate.subtitle);
                if (cached_row.candidate.action.len > 0) allocator.free(cached_row.candidate.action);
                if (cached_row.candidate.icon.len > 0) allocator.free(cached_row.candidate.icon);
            }
            allocator.free(cached_rows);
            return;
        };
        cached_bytes += action.len;
        const icon = allocator.dupe(u8, row.candidate.icon) catch {
            allocator.free(action);
            allocator.free(subtitle);
            allocator.free(title);
            for (cached_rows[0..copied]) |cached_row| {
                if (cached_row.candidate.title.len > 0) allocator.free(cached_row.candidate.title);
                if (cached_row.candidate.subtitle.len > 0) allocator.free(cached_row.candidate.subtitle);
                if (cached_row.candidate.action.len > 0) allocator.free(cached_row.candidate.action);
                if (cached_row.candidate.icon.len > 0) allocator.free(cached_row.candidate.icon);
            }
            allocator.free(cached_rows);
            return;
        };
        cached_bytes += icon.len;
        cached_rows[idx] = .{
            .score = row.score,
            .candidate = .{
                .kind = row.candidate.kind,
                .title = title,
                .subtitle = subtitle,
                .action = action,
                .icon = icon,
            },
        };
        copied += 1;
    }
    ctx.async_cached_rows_ptr = cached_rows.ptr;
    ctx.async_cached_rows_len = copied;
    ctx.async_cached_query_hash = query_hash;
    ctx.async_cached_total_len = total_len;
    ctx.async_cached_created_ns = std.time.nanoTimestamp();
    std.log.info(
        "ram_event=async_cache_store query_hash={d} route={s} query_term_len={d} emitted_rows={d} owned_item_count={d} owned_bytes={d} generation_count={d} pruned_count={d} window_limit={d} cached_rows={d} cached_bytes={d}",
        .{
            query_hash,
            route,
            query_term_len,
            rows.len,
            copied,
            cached_bytes,
            0,
            0,
            window_limit,
            copied,
            cached_bytes,
        },
    );
}

fn cacheCapForWindowLimit(window_limit: usize) usize {
    const scaled = std.math.mul(usize, window_limit, 5) catch std.math.maxInt(usize);
    return std.math.clamp(scaled, min_cached_rows, max_cached_rows);
}

pub fn asyncCachedRows(ctx: *UiContext, query_hash: u64) ?[]search_mod.ScoredCandidate {
    if (ctx.async_cached_query_hash != query_hash) return null;
    if (ctx.async_cached_rows_ptr == null) return null;
    return ctx.async_cached_rows_ptr.?[0..ctx.async_cached_rows_len];
}

pub fn asyncCachedTotalLen(ctx: *UiContext, query_hash: u64) usize {
    if (ctx.async_cached_query_hash != query_hash) return 0;
    return ctx.async_cached_total_len;
}

pub fn asyncCacheKnownForQuery(ctx: *UiContext, query_hash: u64) bool {
    return ctx.async_cached_query_hash == query_hash;
}

pub fn asyncCacheCreatedNs(ctx: *UiContext, query_hash: u64) i128 {
    if (ctx.async_cached_query_hash != query_hash) return 0;
    return ctx.async_cached_created_ns;
}

pub fn takePendingAsyncQuery(ctx: *UiContext) ?[]u8 {
    const ptr = ctx.async_pending_query_ptr orelse return null;
    const slice = ptr[0..ctx.async_pending_query_len];
    ctx.async_pending_query_ptr = null;
    ctx.async_pending_query_len = 0;
    return slice;
}

pub fn freePendingAsyncQuery(ctx: *UiContext) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    if (ctx.async_pending_query_ptr) |ptr| {
        allocator.free(ptr[0..ctx.async_pending_query_len]);
        ctx.async_pending_query_ptr = null;
        ctx.async_pending_query_len = 0;
    }
}

pub fn freeAsyncSearchResult(payload: *AsyncSearchResult) void {
    const allocator = payload.allocator;
    allocator.free(payload.query);
    for (payload.rows) |row| {
        if (row.title.len > 0) allocator.free(row.title);
        if (row.subtitle.len > 0) allocator.free(row.subtitle);
        if (row.action.len > 0) allocator.free(row.action);
        if (row.icon.len > 0) allocator.free(row.icon);
    }
    if (payload.rows.len > 0) allocator.free(payload.rows);
    allocator.destroy(payload);
}

test "cacheCapForWindowLimit clamps low, mid, and high ranges" {
    try std.testing.expectEqual(min_cached_rows, cacheCapForWindowLimit(0));
    try std.testing.expectEqual(@as(usize, 100), cacheCapForWindowLimit(20));
    try std.testing.expectEqual(max_cached_rows, cacheCapForWindowLimit(1000));
}

test "cacheCapForWindowLimit saturates overflow inputs to max cap" {
    const huge = std.math.maxInt(usize);
    try std.testing.expectEqual(max_cached_rows, cacheCapForWindowLimit(huge));
}

const std = @import("std");
const query_metrics = @import("query_metrics.zig");

pub const QueryFlagsSnapshot = struct {
    last_query_refreshed_cache: bool,
    last_query_used_stale_cache: bool,
    last_query_had_provider_runtime_failure: bool,
};

pub fn markRefreshed(
    query_mu: *std.Thread.Mutex,
    last_query_refreshed_cache: *bool,
) void {
    query_mu.lock();
    defer query_mu.unlock();
    query_metrics.markRefreshed(last_query_refreshed_cache);
}

pub fn setElapsed(
    query_mu: *std.Thread.Mutex,
    last_query_elapsed_ns: *u64,
    elapsed_ns: u64,
) void {
    query_mu.lock();
    defer query_mu.unlock();
    query_metrics.setElapsed(last_query_elapsed_ns, elapsed_ns);
}

pub fn resetFlags(
    query_mu: *std.Thread.Mutex,
    last_query_refreshed_cache: *bool,
    last_query_used_stale_cache: *bool,
    last_query_had_provider_runtime_failure: *bool,
) void {
    query_mu.lock();
    defer query_mu.unlock();
    query_metrics.resetFlags(
        last_query_refreshed_cache,
        last_query_used_stale_cache,
        last_query_had_provider_runtime_failure,
    );
}

pub fn readFlags(
    query_mu: *std.Thread.Mutex,
    last_query_refreshed_cache: *const bool,
    last_query_used_stale_cache: *const bool,
    last_query_had_provider_runtime_failure: *const bool,
) QueryFlagsSnapshot {
    query_mu.lock();
    defer query_mu.unlock();
    return .{
        .last_query_refreshed_cache = last_query_refreshed_cache.*,
        .last_query_used_stale_cache = last_query_used_stale_cache.*,
        .last_query_had_provider_runtime_failure = last_query_had_provider_runtime_failure.*,
    };
}

pub fn readElapsed(
    query_mu: *std.Thread.Mutex,
    last_query_elapsed_ns: *const u64,
) u64 {
    query_mu.lock();
    defer query_mu.unlock();
    return last_query_elapsed_ns.*;
}

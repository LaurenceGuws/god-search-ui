pub fn resetFlags(last_query_refreshed_cache: *bool, last_query_used_stale_cache: *bool) void {
    last_query_refreshed_cache.* = false;
    last_query_used_stale_cache.* = false;
}

pub fn setElapsed(last_query_elapsed_ns: *u64, elapsed_ns: u64) void {
    last_query_elapsed_ns.* = elapsed_ns;
}

pub fn markRefreshed(last_query_refreshed_cache: *bool) void {
    last_query_refreshed_cache.* = true;
}

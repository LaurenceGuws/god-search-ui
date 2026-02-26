const std = @import("std");

pub const RefreshOutcome = enum {
    scheduled,
    skipped_running,
    failed_spawn,
};

var events = std.atomic.Value(u64).init(0);
var scheduled = std.atomic.Value(u64).init(0);
var skipped = std.atomic.Value(u64).init(0);
var failed = std.atomic.Value(u64).init(0);

pub fn record(result: RefreshOutcome) void {
    _ = events.fetchAdd(1, .monotonic);
    switch (result) {
        .scheduled => _ = scheduled.fetchAdd(1, .monotonic),
        .skipped_running => _ = skipped.fetchAdd(1, .monotonic),
        .failed_spawn => _ = failed.fetchAdd(1, .monotonic),
    }
}

pub fn snapshotAlloc(allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "events={d};scheduled={d};skipped={d};failed={d}",
        .{
            events.load(.monotonic),
            scheduled.load(.monotonic),
            skipped.load(.monotonic),
            failed.load(.monotonic),
        },
    );
}

pub fn resetForTest() void {
    events.store(0, .monotonic);
    scheduled.store(0, .monotonic);
    skipped.store(0, .monotonic);
    failed.store(0, .monotonic);
}

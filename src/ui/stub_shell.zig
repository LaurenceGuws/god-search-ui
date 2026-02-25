const std = @import("std");
const app = @import("../app/mod.zig");
const headless_controller = @import("headless/controller.zig");

pub const Shell = struct {
    pub const RunOptions = struct {
        resident_mode: bool = false,
        start_hidden: bool = false,
    };

    pub fn run(allocator: std.mem.Allocator, service: *app.SearchService, _: *app.TelemetrySink, options: RunOptions) !void {
        _ = options;
        try headless_controller.run(allocator, service);
    }
};

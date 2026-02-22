const std = @import("std");
const app = @import("../app/mod.zig");
const headless_controller = @import("headless/controller.zig");

pub const Shell = struct {
    pub fn run(allocator: std.mem.Allocator, service: *app.SearchService, _: *app.TelemetrySink) !void {
        try headless_controller.run(allocator, service);
    }
};

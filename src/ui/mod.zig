const build_options = @import("build_options");

pub const placement = @import("placement/mod.zig");
pub const surfaces = @import("surfaces/mod.zig");
pub const Shell = if (build_options.enable_gtk)
    @import("gtk_shell.zig").Shell
else
    @import("stub_shell.zig").Shell;

pub const Diagnostics = if (build_options.enable_gtk)
    @import("gtk/diagnostics.zig").Diagnostics
else
    struct {
        pub fn printOutputs(_: @import("std").mem.Allocator) !void {
            var stdout_buffer: [64]u8 = undefined;
            var stdout_writer = @import("std").fs.File.stdout().writer(&stdout_buffer);
            const out = &stdout_writer.interface;
            try out.print("[]\n", .{});
            try out.flush();
        }

        pub fn printShellHealth(allocator: @import("std").mem.Allocator) !void {
            var stdout_buffer: [256]u8 = undefined;
            var stdout_writer = @import("std").fs.File.stdout().writer(&stdout_buffer);
            const out = &stdout_writer.interface;
            _ = allocator;
            try out.print("[\"module=launcher status=unknown detail=gtk-disabled\",\"module=notifications status=unknown detail=gtk-disabled\"]\n", .{});
            try out.flush();
        }
    };

const std = @import("std");
const gtk_types = @import("types.zig");
const wm_adapter = @import("../../wm/adapter.zig");

const c = gtk_types.c;

pub const GdkAdapter = struct {
    display: *c.GdkDisplay,

    pub fn adapter(self: *GdkAdapter) wm_adapter.Adapter {
        return .{
            .name = "gdk",
            .context = self,
            .vtable = &.{
                .list_outputs = listOutputs,
                .free_outputs = freeOutputs,
                .work_area = workArea,
                .focus_hint = focusHint,
            },
        };
    }

    fn listOutputs(context: *anyopaque, allocator: std.mem.Allocator) ![]wm_adapter.Output {
        const self: *GdkAdapter = @ptrCast(@alignCast(context));
        const monitors = c.gdk_display_get_monitors(self.display) orelse return allocator.alloc(wm_adapter.Output, 0);
        const count_raw = c.g_list_model_get_n_items(monitors);
        const count: usize = @intCast(count_raw);
        var outputs = try allocator.alloc(wm_adapter.Output, count);
        var built: usize = 0;
        errdefer {
            for (outputs[0..built]) |out| allocator.free(out.name);
            allocator.free(outputs);
        }

        for (outputs, 0..) |*out, idx| {
            const item = c.g_list_model_get_item(monitors, @intCast(idx)) orelse return error.OutputQueryFailed;
            defer c.g_object_unref(item);

            const monitor: *c.GdkMonitor = @ptrCast(@alignCast(item));
            var geometry: c.GdkRectangle = undefined;
            c.gdk_monitor_get_geometry(monitor, &geometry);

            const connector = c.gdk_monitor_get_connector(monitor);
            const name = if (connector != null)
                try allocator.dupe(u8, std.mem.span(@as([*:0]const u8, @ptrCast(connector))))
            else
                try std.fmt.allocPrint(allocator, "monitor-{d}", .{idx});
            errdefer allocator.free(name);

            out.* = .{
                .name = name,
                .x = geometry.x,
                .y = geometry.y,
                .width = geometry.width,
                .height = geometry.height,
                .scale_milli = 1000,
            };
            built += 1;
        }

        return outputs;
    }

    fn freeOutputs(_: *anyopaque, allocator: std.mem.Allocator, outputs: []wm_adapter.Output) void {
        for (outputs) |out| allocator.free(out.name);
        allocator.free(outputs);
    }

    fn workArea(_: *anyopaque, _: std.mem.Allocator, _: []const u8) !?wm_adapter.WorkArea {
        return null;
    }

    fn focusHint(_: *anyopaque, _: std.mem.Allocator) !?wm_adapter.FocusHint {
        return null;
    }
};

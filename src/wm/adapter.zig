const std = @import("std");

pub const Output = struct {
    name: []const u8,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    scale_milli: u16 = 1000,
};

pub const WorkArea = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const FocusHint = struct {
    output_name: ?[]const u8 = null,
};

pub const MonitorPolicy = enum {
    focused,
    primary,
    by_name,
};

pub const MonitorTarget = struct {
    policy: MonitorPolicy = .focused,
    output_name: ?[]const u8 = null,
};

pub const Adapter = struct {
    name: []const u8,
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        list_outputs: *const fn (context: *anyopaque, allocator: std.mem.Allocator) anyerror![]Output,
        free_outputs: *const fn (context: *anyopaque, allocator: std.mem.Allocator, outputs: []Output) void,
        work_area: *const fn (context: *anyopaque, allocator: std.mem.Allocator, output_name: []const u8) anyerror!?WorkArea,
        focus_hint: *const fn (context: *anyopaque, allocator: std.mem.Allocator) anyerror!?FocusHint,
    };

    pub fn listOutputs(self: Adapter, allocator: std.mem.Allocator) ![]Output {
        return self.vtable.list_outputs(self.context, allocator);
    }

    pub fn freeOutputs(self: Adapter, allocator: std.mem.Allocator, outputs: []Output) void {
        self.vtable.free_outputs(self.context, allocator, outputs);
    }

    pub fn workArea(self: Adapter, allocator: std.mem.Allocator, output_name: []const u8) !?WorkArea {
        return self.vtable.work_area(self.context, allocator, output_name);
    }

    pub fn focusHint(self: Adapter, allocator: std.mem.Allocator) !?FocusHint {
        return self.vtable.focus_hint(self.context, allocator);
    }
};

pub fn selectOutput(
    outputs: []const Output,
    focus_hint: ?FocusHint,
    target: MonitorTarget,
) ?usize {
    if (outputs.len == 0) return null;

    switch (target.policy) {
        .by_name => {
            const wanted = target.output_name orelse return 0;
            for (outputs, 0..) |out, idx| {
                if (std.mem.eql(u8, out.name, wanted)) return idx;
            }
            return 0;
        },
        .focused => {
            if (focus_hint) |hint| {
                if (hint.output_name) |name| {
                    for (outputs, 0..) |out, idx| {
                        if (std.mem.eql(u8, out.name, name)) return idx;
                    }
                }
            }
            return 0;
        },
        .primary => return 0,
    }
}

test "selectOutput prioritizes focused output when available" {
    const outputs = [_]Output{
        .{ .name = "DP-1", .x = 0, .y = 0, .width = 1920, .height = 1080 },
        .{ .name = "HDMI-A-1", .x = 1920, .y = 0, .width = 1920, .height = 1080 },
    };

    const idx = selectOutput(&outputs, .{ .output_name = "HDMI-A-1" }, .{ .policy = .focused });
    try std.testing.expectEqual(@as(usize, 1), idx.?);
}

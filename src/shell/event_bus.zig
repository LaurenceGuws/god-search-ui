const std = @import("std");
const module_mod = @import("module.zig");

pub const Subscriber = struct {
    context: *anyopaque,
    on_event: *const fn (context: *anyopaque, event: module_mod.Event) void,
};

pub const EventBus = struct {
    allocator: std.mem.Allocator,
    subscribers: std.ArrayList(Subscriber),

    pub fn init(allocator: std.mem.Allocator) EventBus {
        return .{
            .allocator = allocator,
            .subscribers = std.ArrayList(Subscriber).empty,
        };
    }

    pub fn deinit(self: *EventBus) void {
        self.subscribers.deinit(self.allocator);
    }

    pub fn subscribe(self: *EventBus, sub: Subscriber) !void {
        try self.subscribers.append(self.allocator, sub);
    }

    pub fn emit(self: *EventBus, event: module_mod.Event) void {
        for (self.subscribers.items) |sub| {
            sub.on_event(sub.context, event);
        }
    }
};

test "event bus emits typed events to all subscribers in order" {
    const allocator = std.testing.allocator;

    const Counter = struct {
        summon_count: usize = 0,
        custom: []const u8 = "",

        fn onEvent(ctx: *anyopaque, event: module_mod.Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            switch (event) {
                .summon => self.summon_count += 1,
                .custom => |value| self.custom = value,
                else => {},
            }
        }
    };

    var a = Counter{};
    var b = Counter{};

    var bus = EventBus.init(allocator);
    defer bus.deinit();
    try bus.subscribe(.{ .context = &a, .on_event = Counter.onEvent });
    try bus.subscribe(.{ .context = &b, .on_event = Counter.onEvent });

    bus.emit(.summon);
    bus.emit(.{ .custom = "ping" });

    try std.testing.expectEqual(@as(usize, 1), a.summon_count);
    try std.testing.expectEqual(@as(usize, 1), b.summon_count);
    try std.testing.expectEqualStrings("ping", a.custom);
    try std.testing.expectEqualStrings("ping", b.custom);
}

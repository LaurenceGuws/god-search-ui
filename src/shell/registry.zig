const std = @import("std");
const module_mod = @import("module.zig");

const ModuleFactory = module_mod.ModuleFactory;
const ModuleInstance = module_mod.ModuleInstance;
const Event = module_mod.Event;

pub const Registry = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry),
    started: bool = false,

    const Entry = struct {
        factory: ModuleFactory,
        instance: ?ModuleInstance = null,
    };

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(Entry).empty,
        };
    }

    pub fn deinit(self: *Registry) void {
        self.stopAll();
        self.entries.deinit(self.allocator);
    }

    pub fn register(self: *Registry, factory: ModuleFactory) !void {
        try self.entries.append(self.allocator, .{ .factory = factory });
    }

    pub fn startAll(self: *Registry) !void {
        for (self.entries.items) |*entry| {
            if (entry.instance == null) {
                entry.instance = try entry.factory.init(self.allocator, entry.factory.context);
            }
            try entry.instance.?.start();
        }
        self.started = true;
    }

    pub fn stopAll(self: *Registry) void {
        if (!self.started and self.entries.items.len == 0) return;
        var i: usize = self.entries.items.len;
        while (i > 0) {
            i -= 1;
            var entry = &self.entries.items[i];
            if (entry.instance) |*instance| {
                instance.stop();
                instance.deinit(self.allocator);
                entry.instance = null;
            }
        }
        self.started = false;
    }

    pub fn broadcast(self: *Registry, event: Event) void {
        for (self.entries.items) |*entry| {
            if (entry.instance) |*instance| {
                instance.handleEvent(event);
            }
        }
    }

    pub fn healthSnapshot(self: *Registry, allocator: std.mem.Allocator) ![]module_mod.ModuleHealthEntry {
        var out = std.ArrayList(module_mod.ModuleHealthEntry).empty;
        errdefer out.deinit(allocator);
        for (self.entries.items) |*entry| {
            const health = if (entry.instance) |*instance|
                instance.health()
            else
                module_mod.ModuleHealth{ .status = .unknown, .detail = "not started" };
            try out.append(allocator, .{ .name = entry.factory.name, .health = health });
        }
        return out.toOwnedSlice(allocator);
    }
};

test "registry starts in registration order and stops in reverse order" {
    const allocator = std.testing.allocator;

    const Recorder = struct {
        items: [8][]const u8 = undefined,
        len: usize = 0,

        fn push(self: *@This(), item: []const u8) void {
            self.items[self.len] = item;
            self.len += 1;
        }
    };

    const Ctx = struct {
        name: []const u8,
        recorder: *Recorder,
    };

    const TestState = struct {
        name: []const u8,
        recorder: *Recorder,

        fn start(ptr: *anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.recorder.push(if (std.mem.eql(u8, self.name, "launcher")) "start:launcher" else "start:notifications");
        }

        fn stop(ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.recorder.push(if (std.mem.eql(u8, self.name, "launcher")) "stop:launcher" else "stop:notifications");
        }

        fn handleEvent(ptr: *anyopaque, event: Event) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            if (event != .summon) return;
            self.recorder.push(if (std.mem.eql(u8, self.name, "launcher")) "event:summon:launcher" else "event:summon:notifications");
        }

        fn health(_: *anyopaque) module_mod.ModuleHealth {
            return .{ .status = .ready, .detail = "ok" };
        }

        fn deinit(alloc: std.mem.Allocator, ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            alloc.destroy(self);
        }
    };

    const Init = struct {
        fn init(alloc: std.mem.Allocator, ctx_ptr: *anyopaque) !ModuleInstance {
            const ctx: *Ctx = @ptrCast(@alignCast(ctx_ptr));
            const state = try alloc.create(TestState);
            state.* = .{ .name = ctx.name, .recorder = ctx.recorder };
            return .{
                .name = ctx.name,
                .state = state,
                .vtable = &.{
                    .start = TestState.start,
                    .stop = TestState.stop,
                    .handle_event = TestState.handleEvent,
                    .health = TestState.health,
                    .deinit = TestState.deinit,
                },
            };
        }
    };

    var recorder = Recorder{};
    var launcher_ctx = Ctx{ .name = "launcher", .recorder = &recorder };
    var notifications_ctx = Ctx{ .name = "notifications", .recorder = &recorder };

    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registry.register(.{ .name = "launcher", .context = &launcher_ctx, .init = Init.init });
    try registry.register(.{ .name = "notifications", .context = &notifications_ctx, .init = Init.init });
    try registry.startAll();
    registry.broadcast(.summon);
    registry.stopAll();

    try std.testing.expectEqual(@as(usize, 6), recorder.len);
    try std.testing.expectEqualStrings("start:launcher", recorder.items[0]);
    try std.testing.expectEqualStrings("start:notifications", recorder.items[1]);
    try std.testing.expectEqualStrings("event:summon:launcher", recorder.items[2]);
    try std.testing.expectEqualStrings("event:summon:notifications", recorder.items[3]);
    try std.testing.expectEqualStrings("stop:notifications", recorder.items[4]);
    try std.testing.expectEqualStrings("stop:launcher", recorder.items[5]);
}

test "health snapshot reports unknown state before start" {
    const allocator = std.testing.allocator;

    const Ctx = struct {
        fn init(_: std.mem.Allocator, _: *anyopaque) !ModuleInstance {
            return error.NotImplemented;
        }
    };

    var registry = Registry.init(allocator);
    defer registry.deinit();

    var dummy: u8 = 0;
    try registry.register(.{ .name = "dummy", .context = &dummy, .init = Ctx.init });

    const snapshot = try registry.healthSnapshot(allocator);
    defer allocator.free(snapshot);

    try std.testing.expectEqual(@as(usize, 1), snapshot.len);
    try std.testing.expectEqualStrings("dummy", snapshot[0].name);
    try std.testing.expectEqual(module_mod.HealthStatus.unknown, snapshot[0].health.status);
}

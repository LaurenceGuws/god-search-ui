const std = @import("std");

pub const NotifyRequest = struct {
    app_name: []const u8,
    summary: []const u8,
    body: []const u8,
    replaces_id: u32 = 0,
    expire_timeout: i32 = -1,
    has_actions: bool = false,
};

pub const Notification = struct {
    app_name: []u8,
    summary: []u8,
    body: []u8,
    expire_timeout: i32,
    has_actions: bool,
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(u32, Notification),
    next_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(u32, Notification).init(allocator),
        };
    }

    pub fn deinit(self: *Store) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            freeNotification(self.allocator, entry.value_ptr.*);
        }
        self.map.deinit();
    }

    pub fn len(self: *const Store) usize {
        return self.map.count();
    }

    pub fn notify(self: *Store, req: NotifyRequest) !u32 {
        if (req.replaces_id != 0 and self.map.getPtr(req.replaces_id) != null) {
            try self.replace(req.replaces_id, req);
            return req.replaces_id;
        }

        const id = try self.allocateId();
        try self.map.put(id, try duplicateNotification(self.allocator, req));
        return id;
    }

    pub fn close(self: *Store, id: u32) bool {
        const owned = self.map.fetchRemove(id) orelse return false;
        freeNotification(self.allocator, owned.value);
        return true;
    }

    fn replace(self: *Store, id: u32, req: NotifyRequest) !void {
        const slot = self.map.getPtr(id) orelse return;
        freeNotification(self.allocator, slot.*);
        slot.* = try duplicateNotification(self.allocator, req);
    }

    fn allocateId(self: *Store) !u32 {
        var attempts: usize = 0;
        var id = self.next_id;

        while (attempts <= std.math.maxInt(u32)) : (attempts += 1) {
            if (id == 0) id = 1;
            if (!self.map.contains(id)) {
                self.next_id = id +% 1;
                if (self.next_id == 0) self.next_id = 1;
                return id;
            }
            id +%= 1;
        }

        return error.NoFreeNotificationId;
    }
};

fn duplicateNotification(allocator: std.mem.Allocator, req: NotifyRequest) !Notification {
    return .{
        .app_name = try allocator.dupe(u8, req.app_name),
        .summary = try allocator.dupe(u8, req.summary),
        .body = try allocator.dupe(u8, req.body),
        .expire_timeout = req.expire_timeout,
        .has_actions = req.has_actions,
    };
}

fn freeNotification(allocator: std.mem.Allocator, notification: Notification) void {
    allocator.free(notification.app_name);
    allocator.free(notification.summary);
    allocator.free(notification.body);
}

test "store notify allocates ids and close removes" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const first = try store.notify(.{
        .app_name = "app-a",
        .summary = "hello",
        .body = "body-a",
    });
    const second = try store.notify(.{
        .app_name = "app-b",
        .summary = "world",
        .body = "body-b",
    });

    try std.testing.expectEqual(@as(u32, 1), first);
    try std.testing.expectEqual(@as(u32, 2), second);
    try std.testing.expectEqual(@as(usize, 2), store.len());

    try std.testing.expect(store.close(first));
    try std.testing.expectEqual(@as(usize, 1), store.len());
    try std.testing.expect(!store.close(first));
}

test "store notify replaces existing id" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const id = try store.notify(.{
        .app_name = "app-a",
        .summary = "summary-1",
        .body = "body-1",
    });

    const replaced = try store.notify(.{
        .app_name = "app-a",
        .summary = "summary-2",
        .body = "body-2",
        .replaces_id = id,
        .has_actions = true,
        .expire_timeout = 5000,
    });

    try std.testing.expectEqual(id, replaced);
    try std.testing.expectEqual(@as(usize, 1), store.len());
    const entry = store.map.get(id) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("summary-2", entry.summary);
    try std.testing.expectEqualStrings("body-2", entry.body);
    try std.testing.expectEqual(@as(i32, 5000), entry.expire_timeout);
    try std.testing.expect(entry.has_actions);
}

const std = @import("std");

pub const CandidateKind = enum {
    app,
    window,
    workspace,
    dir,
    file,
    grep,
    web,
    notification,
    action,
    hint,
};

pub const Candidate = struct {
    kind: CandidateKind,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
    icon: []const u8,

    pub fn init(kind: CandidateKind, title: []const u8, subtitle: []const u8, action: []const u8) Candidate {
        return .{
            .kind = kind,
            .title = title,
            .subtitle = subtitle,
            .action = action,
            .icon = "",
        };
    }

    pub fn initWithIcon(kind: CandidateKind, title: []const u8, subtitle: []const u8, action: []const u8, icon: []const u8) Candidate {
        return .{
            .kind = kind,
            .title = title,
            .subtitle = subtitle,
            .action = action,
            .icon = icon,
        };
    }
};

pub const CandidateList = std.ArrayList(Candidate);

pub const ProviderHealth = enum {
    ready,
    degraded,
    unavailable,
};

pub const Provider = struct {
    name: []const u8,
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        collect: *const fn (context: *anyopaque, allocator: std.mem.Allocator, out: *CandidateList) anyerror!void,
        health: *const fn (context: *anyopaque) ProviderHealth,
    };

    pub fn collect(self: Provider, allocator: std.mem.Allocator, out: *CandidateList) !void {
        try self.vtable.collect(self.context, allocator, out);
    }

    pub fn health(self: Provider) ProviderHealth {
        return self.vtable.health(self.context);
    }
};

const FakeProviderContext = struct {
    pub fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *CandidateList) !void {
        _ = context;
        try out.append(allocator, .init(.action, "Settings", "System", "settings"));
    }

    pub fn health(context: *anyopaque) ProviderHealth {
        _ = context;
        return .ready;
    }
};

test "provider interface can collect candidates" {
    var list = CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    var context = FakeProviderContext{};
    const provider = Provider{
        .name = "fake",
        .context = &context,
        .vtable = &.{
            .collect = FakeProviderContext.collect,
            .health = FakeProviderContext.health,
        },
    };

    try provider.collect(std.testing.allocator, &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqual(ProviderHealth.ready, provider.health());
    try std.testing.expectEqualStrings("Settings", list.items[0].title);
}

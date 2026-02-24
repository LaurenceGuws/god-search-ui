const std = @import("std");

var cache_lock: std.Thread.Mutex = .{};
var cache: std.StringHashMapUnmanaged(bool) = .{};
var command_exists_runner: *const fn (name: []const u8) bool = commandExistsUncached;

pub fn commandExistsCached(name: []const u8) bool {
    cache_lock.lock();
    if (cache.get(name)) |value| {
        cache_lock.unlock();
        return value;
    }
    cache_lock.unlock();

    const value = command_exists_runner(name);

    cache_lock.lock();
    defer cache_lock.unlock();
    if (cache.get(name)) |existing| return existing;
    const key = std.heap.page_allocator.dupe(u8, name) catch return value;
    cache.put(std.heap.page_allocator, key, value) catch {
        std.heap.page_allocator.free(key);
        return value;
    };
    return value;
}

fn commandExistsUncached(name: []const u8) bool {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ name, "--help" },
    }) catch return false;
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    // Some CLIs (including `hyprctl`) return non-zero for `--help` while still being present.
    // Existence check only needs a successful spawn/exec, not a zero help exit code.
    return true;
}

fn clearCacheForTests() void {
    cache_lock.lock();
    defer cache_lock.unlock();

    var it = cache.iterator();
    while (it.next()) |entry| {
        std.heap.page_allocator.free(entry.key_ptr.*);
    }
    cache.deinit(std.heap.page_allocator);
    cache = .{};
}

test "commandExistsCached reuses prior command result for repeated checks" {
    const Fake = struct {
        var calls: usize = 0;

        fn run(name: []const u8) bool {
            calls += 1;
            return std.mem.eql(u8, name, "present");
        }
    };

    clearCacheForTests();
    command_exists_runner = Fake.run;
    defer {
        command_exists_runner = commandExistsUncached;
        clearCacheForTests();
    }

    try std.testing.expect(commandExistsCached("present"));
    try std.testing.expect(commandExistsCached("present"));
    try std.testing.expectEqual(@as(usize, 1), Fake.calls);
}

test "commandExistsCached tracks each command key independently" {
    const Fake = struct {
        var calls: usize = 0;

        fn run(name: []const u8) bool {
            calls += 1;
            return std.mem.eql(u8, name, "alpha");
        }
    };

    clearCacheForTests();
    command_exists_runner = Fake.run;
    defer {
        command_exists_runner = commandExistsUncached;
        clearCacheForTests();
    }

    try std.testing.expect(commandExistsCached("alpha"));
    try std.testing.expect(!commandExistsCached("beta"));
    try std.testing.expect(commandExistsCached("alpha"));
    try std.testing.expect(!commandExistsCached("beta"));
    try std.testing.expectEqual(@as(usize, 2), Fake.calls);
}

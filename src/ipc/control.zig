const std = @import("std");

pub const Command = enum {
    ping,
    summon,
    hide,
    toggle,
    version,
    shell_health,
    wm_event_stats,
};

pub const HandlerResult = struct {
    ok: bool,
    code: []const u8,
    message: []const u8,
};

pub const Handler = *const fn (Command, *anyopaque) HandlerResult;
pub const QueryHandler = *const fn (std.mem.Allocator, Command, *anyopaque) anyerror!?[]u8;

const Request = struct {
    v: u32 = 0,
    cmd: []const u8 = "",
};

const Response = struct {
    ok: bool = false,
    code: []const u8 = "",
    message: []const u8 = "",
};

const connect_timeout_ms: u64 = 250;
const response_timeout_ms: i32 = 500;

pub const Server = struct {
    allocator: std.mem.Allocator,
    socket_path: []u8,
    listener_fd: std.posix.socket_t,
    handler: Handler,
    query_handler: ?QueryHandler,
    user_data: *anyopaque,
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,

    pub fn init(
        allocator: std.mem.Allocator,
        handler: Handler,
        query_handler: ?QueryHandler,
        user_data: *anyopaque,
    ) !Server {
        const socket_path = try defaultSocketPathAlloc(allocator);
        const listener_fd = try bindListener(socket_path);
        return .{
            .allocator = allocator,
            .socket_path = socket_path,
            .listener_fd = listener_fd,
            .handler = handler,
            .query_handler = query_handler,
            .user_data = user_data,
        };
    }

    pub fn start(self: *Server) !void {
        self.thread = try std.Thread.spawn(.{}, serverMain, .{self});
    }

    pub fn deinit(self: *Server) void {
        self.stop_flag.store(true, .seq_cst);
        std.posix.close(self.listener_fd);
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
        std.posix.unlink(self.socket_path) catch {};
        self.allocator.free(self.socket_path);
    }
};

pub fn trySendCommand(allocator: std.mem.Allocator, cmd: Command) !bool {
    const response = try sendCommand(allocator, cmd);
    defer response.deinit();
    if (!response.value.ok) return false;
    return std.mem.eql(u8, response.value.code, "ok");
}

pub fn queryCommandMessage(allocator: std.mem.Allocator, cmd: Command) !?[]u8 {
    const response = try sendCommand(allocator, cmd);
    defer response.deinit();
    if (!response.value.ok) return null;
    if (!std.mem.eql(u8, response.value.code, "ok")) return null;
    const msg = try allocator.dupe(u8, response.value.message);
    return msg;
}

fn sendCommand(allocator: std.mem.Allocator, cmd: Command) !std.json.Parsed(Response) {
    const socket_path = try defaultSocketPathAlloc(allocator);
    defer allocator.free(socket_path);

    const fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK, 0) catch |err| {
        if (err == error.AddressFamilyNotSupported) return error.NoSocketSupport;
        return err;
    };
    defer std.posix.close(fd);

    const addr = try std.net.Address.initUnix(socket_path);
    const connected = try connectWithRetryTimeout(fd, &addr.any, addr.getOsSockLen(), connect_timeout_ms);
    if (!connected) return error.ConnectTimeout;

    const request = try std.fmt.allocPrint(allocator, "{{\"v\":1,\"cmd\":\"{s}\"}}", .{@tagName(cmd)});
    defer allocator.free(request);
    _ = try std.posix.write(fd, request);
    std.posix.shutdown(fd, .send) catch {};

    var poll_fds = [_]std.posix.pollfd{
        .{
            .fd = fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
    };
    const poll_count = std.posix.poll(&poll_fds, response_timeout_ms) catch return error.PollFailed;
    if (poll_count <= 0) return error.PollTimeout;
    if ((poll_fds[0].revents & std.posix.POLL.IN) == 0) return error.NoPollInput;

    var response_buf: [1024]u8 = undefined;
    const n = std.posix.read(fd, &response_buf) catch return error.ReadFailed;
    if (n == 0) return error.EmptyResponse;

    const parsed = std.json.parseFromSlice(Response, allocator, response_buf[0..n], .{}) catch return error.BadResponse;
    return parsed;
}

pub fn defaultSocketPathAlloc(allocator: std.mem.Allocator) ![]u8 {
    const xdg_runtime = std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR") catch null;
    if (xdg_runtime) |runtime_dir| {
        defer allocator.free(runtime_dir);
        return std.fmt.allocPrint(allocator, "{s}/god-search-ui.sock", .{runtime_dir});
    }

    const uid = std.posix.getuid();
    return std.fmt.allocPrint(allocator, "/tmp/god-search-ui-{d}.sock", .{uid});
}

fn bindListener(socket_path: []const u8) !std.posix.socket_t {
    const fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, 0);
    errdefer std.posix.close(fd);

    const addr = try std.net.Address.initUnix(socket_path);
    std.posix.bind(fd, &addr.any, addr.getOsSockLen()) catch |err| {
        if (err == error.AddressInUse) {
            if (!isSocketLive(socket_path)) {
                std.posix.unlink(socket_path) catch {};
                try std.posix.bind(fd, &addr.any, addr.getOsSockLen());
            } else {
                return error.AddressInUse;
            }
        } else {
            return err;
        }
    };
    try std.posix.listen(fd, 32);
    std.posix.fchmodat(std.posix.AT.FDCWD, socket_path, 0o600, 0) catch {};
    return fd;
}

fn isSocketLive(socket_path: []const u8) bool {
    const fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, 0) catch return false;
    defer std.posix.close(fd);
    const addr = std.net.Address.initUnix(socket_path) catch return false;
    std.posix.connect(fd, &addr.any, addr.getOsSockLen()) catch return false;
    return true;
}

fn serverMain(server: *Server) void {
    while (!server.stop_flag.load(.seq_cst)) {
        const client_fd = std.posix.accept(server.listener_fd, null, null, std.posix.SOCK.CLOEXEC) catch |err| {
            switch (err) {
                error.WouldBlock, error.ConnectionAborted => continue,
                error.FileDescriptorNotASocket, error.OperationNotSupported, error.SystemResources, error.ProcessFdQuotaExceeded => continue,
                else => {
                    if (server.stop_flag.load(.seq_cst)) break;
                    continue;
                },
            }
        };
        handleClient(server, client_fd);
        std.posix.close(client_fd);
    }
}

fn handleClient(server: *Server, client_fd: std.posix.socket_t) void {
    var buf: [4096]u8 = undefined;
    const n = std.posix.read(client_fd, &buf) catch {
        writeResponse(client_fd, false, "read_error", "Failed to read request");
        return;
    };
    if (n == 0) {
        writeResponse(client_fd, false, "bad_request", "Empty request");
        return;
    }

    var parsed = std.json.parseFromSlice(Request, server.allocator, buf[0..n], .{}) catch {
        writeResponse(client_fd, false, "bad_request", "Invalid JSON");
        return;
    };
    defer parsed.deinit();

    if (parsed.value.v != 1) {
        writeResponse(client_fd, false, "bad_request", "Unsupported protocol version");
        return;
    }

    const cmd = parseCommand(parsed.value.cmd) orelse {
        writeResponse(client_fd, false, "bad_request", "Unknown command");
        return;
    };

    switch (cmd) {
        .ping => writeResponse(client_fd, true, "ok", "pong"),
        .version => writeResponse(client_fd, true, "ok", "dev"),
        .shell_health => {
            const query = server.query_handler orelse {
                writeResponse(client_fd, false, "rejected", "No query handler");
                return;
            };
            const msg_opt = query(server.allocator, cmd, server.user_data) catch {
                writeResponse(client_fd, false, "rejected", "Query failed");
                return;
            };
            if (msg_opt) |msg| {
                defer server.allocator.free(msg);
                writeResponse(client_fd, true, "ok", msg);
            } else {
                writeResponse(client_fd, false, "rejected", "No data");
            }
        },
        .wm_event_stats => {
            const query = server.query_handler orelse {
                writeResponse(client_fd, false, "rejected", "No query handler");
                return;
            };
            const msg_opt = query(server.allocator, cmd, server.user_data) catch {
                writeResponse(client_fd, false, "rejected", "Query failed");
                return;
            };
            if (msg_opt) |msg| {
                defer server.allocator.free(msg);
                writeResponse(client_fd, true, "ok", msg);
            } else {
                writeResponse(client_fd, false, "rejected", "No data");
            }
        },
        else => {
            const result = server.handler(cmd, server.user_data);
            writeResponse(client_fd, result.ok, result.code, result.message);
        },
    }
}

fn parseCommand(value: []const u8) ?Command {
    inline for (std.meta.fields(Command)) |field| {
        if (std.mem.eql(u8, value, field.name)) {
            return @field(Command, field.name);
        }
    }
    return null;
}

fn writeResponse(fd: std.posix.socket_t, ok: bool, code: []const u8, message: []const u8) void {
    var buf: [1024]u8 = undefined;
    const json = std.fmt.bufPrint(
        &buf,
        "{{\"ok\":{s},\"code\":\"{s}\",\"message\":\"{s}\"}}",
        .{ if (ok) "true" else "false", code, message },
    ) catch return;
    _ = std.posix.write(fd, json) catch {};
}

fn connectWithRetryTimeout(fd: std.posix.socket_t, sockaddr: *const std.posix.sockaddr, socklen: std.posix.socklen_t, timeout_ms: u64) !bool {
    const start_ns = std.time.nanoTimestamp();
    const timeout_ns = timeout_ms * std.time.ns_per_ms;

    while (true) {
        std.posix.connect(fd, sockaddr, socklen) catch |err| switch (err) {
            error.WouldBlock, error.FileNotFound, error.ConnectionRefused, error.ConnectionResetByPeer, error.NetworkUnreachable, error.AddressNotAvailable => {
                const now_ns = std.time.nanoTimestamp();
                if (now_ns - start_ns >= @as(i128, @intCast(timeout_ns))) return false;
                std.Thread.sleep(5 * std.time.ns_per_ms);
                continue;
            },
            else => return err,
        };
        return true;
    }
}

test "bindListener replaces stale occupied path and binds socket" {
    const allocator = std.testing.allocator;
    const pid = std.posix.getpid();
    const path = try std.fmt.allocPrint(allocator, "/tmp/god-search-ui-stale-{d}.sock", .{pid});
    defer allocator.free(path);
    std.posix.unlink(path) catch {};
    defer std.posix.unlink(path) catch {};

    const file = try std.fs.createFileAbsolute(path, .{});
    file.close();

    const fd = try bindListener(path);
    defer std.posix.close(fd);

    const stat = try std.posix.fstatat(std.posix.AT.FDCWD, path, 0);
    try std.testing.expect(std.posix.S.ISSOCK(stat.mode));
}

test "bindListener sets user-only socket permissions" {
    const allocator = std.testing.allocator;
    const pid = std.posix.getpid();
    const path = try std.fmt.allocPrint(allocator, "/tmp/god-search-ui-mode-{d}.sock", .{pid});
    defer allocator.free(path);
    std.posix.unlink(path) catch {};
    defer std.posix.unlink(path) catch {};

    const fd = try bindListener(path);
    defer std.posix.close(fd);

    const stat = try std.posix.fstatat(std.posix.AT.FDCWD, path, 0);
    try std.testing.expectEqual(@as(u32, 0o600), stat.mode & 0o777);
}

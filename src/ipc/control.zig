const std = @import("std");

pub const Command = enum {
    ping,
    summon,
    hide,
    toggle,
    version,
};

pub const HandlerResult = enum {
    ok,
    rejected,
};

pub const Handler = *const fn (Command, *anyopaque) HandlerResult;

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
    user_data: *anyopaque,
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,

    pub fn init(
        allocator: std.mem.Allocator,
        handler: Handler,
        user_data: *anyopaque,
    ) !Server {
        const socket_path = try defaultSocketPathAlloc(allocator);
        const listener_fd = try bindListener(socket_path);
        return .{
            .allocator = allocator,
            .socket_path = socket_path,
            .listener_fd = listener_fd,
            .handler = handler,
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
    const socket_path = try defaultSocketPathAlloc(allocator);
    defer allocator.free(socket_path);

    const fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, 0) catch |err| {
        if (err == error.AddressFamilyNotSupported) return false;
        return err;
    };
    defer std.posix.close(fd);

    const addr = try std.net.Address.initUnix(socket_path);
    const connected = try connectWithRetryTimeout(fd, &addr.any, addr.getOsSockLen(), connect_timeout_ms);
    if (!connected) return false;

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
    const poll_count = std.posix.poll(&poll_fds, response_timeout_ms) catch return false;
    if (poll_count <= 0) return false;
    if ((poll_fds[0].revents & std.posix.POLL.IN) == 0) return false;

    var response_buf: [1024]u8 = undefined;
    const n = std.posix.read(fd, &response_buf) catch return false;
    if (n == 0) return false;

    var parsed = std.json.parseFromSlice(Response, allocator, response_buf[0..n], .{}) catch return false;
    defer parsed.deinit();
    if (!parsed.value.ok) return false;
    return std.mem.eql(u8, parsed.value.code, "ok");
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
        else => {
            const result = server.handler(cmd, server.user_data);
            if (result == .ok) {
                writeResponse(client_fd, true, "ok", "accepted");
            } else {
                writeResponse(client_fd, false, "rejected", "Command rejected");
            }
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
    var buf: [512]u8 = undefined;
    const json = std.fmt.bufPrint(
        &buf,
        "{{\"ok\":{s},\"code\":\"{s}\",\"message\":\"{s}\",\"data\":{{}}}}",
        .{ if (ok) "true" else "false", code, message },
    ) catch return;
    _ = std.posix.write(fd, json) catch {};
}

fn connectWithRetryTimeout(fd: std.posix.socket_t, sockaddr: *const std.posix.sockaddr, socklen: std.posix.socklen_t, timeout_ms: u64) !bool {
    const start_ns = std.time.nanoTimestamp();
    const timeout_ns = timeout_ms * std.time.ns_per_ms;

    while (true) {
        std.posix.connect(fd, sockaddr, socklen) catch |err| switch (err) {
            error.FileNotFound,
            error.ConnectionRefused,
            error.ConnectionResetByPeer,
            error.NetworkUnreachable,
            error.AddressNotAvailable => {
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

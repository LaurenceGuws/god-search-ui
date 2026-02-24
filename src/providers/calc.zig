const std = @import("std");

pub const CalcError = error{
    UnexpectedToken,
    InvalidNumber,
    DivideByZero,
    ExpectedValue,
    MissingRightParen,
    ExpectedNumber,
    InvalidExponent,
};

pub fn evaluateExpression(input: []const u8) !f64 {
    var p = Parser{ .input = input };
    const value = try p.parseExpr();
    p.skipWs();
    if (!p.eof()) return error.UnexpectedToken;
    if (std.math.isNan(value) or std.math.isInf(value)) return error.InvalidNumber;
    return value;
}

pub fn formatNumberAlloc(allocator: std.mem.Allocator, value: f64) ![]u8 {
    if (value == 0) return allocator.dupe(u8, "0");

    const rounded = @round(value);
    if (@abs(value - rounded) < 1e-12 and rounded >= -9_007_199_254_740_992 and rounded <= 9_007_199_254_740_992) {
        return std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(rounded))});
    }

    const raw = try std.fmt.allocPrint(allocator, "{d:.12}", .{value});
    errdefer allocator.free(raw);
    const trimmed = trimDecimalString(raw);
    if (trimmed.len == raw.len) return raw;
    defer allocator.free(raw);
    return allocator.dupe(u8, trimmed);
}

fn trimDecimalString(value: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, value, '.') == null) return value;
    var end = value.len;
    while (end > 0 and value[end - 1] == '0') : (end -= 1) {}
    if (end > 0 and value[end - 1] == '.') end -= 1;
    return if (end == 0) "0" else value[0..end];
}

const Parser = struct {
    input: []const u8,
    i: usize = 0,

    fn eof(self: *Parser) bool {
        return self.i >= self.input.len;
    }

    fn peek(self: *Parser) ?u8 {
        if (self.eof()) return null;
        return self.input[self.i];
    }

    fn skipWs(self: *Parser) void {
        while (self.i < self.input.len and std.ascii.isWhitespace(self.input[self.i])) : (self.i += 1) {}
    }

    fn parseExpr(self: *Parser) CalcError!f64 {
        var value = try self.parseTerm();
        while (true) {
            self.skipWs();
            const ch = self.peek() orelse return value;
            if (ch != '+' and ch != '-') return value;
            self.i += 1;
            const rhs = try self.parseTerm();
            value = if (ch == '+') value + rhs else value - rhs;
        }
    }

    fn parseTerm(self: *Parser) CalcError!f64 {
        var value = try self.parseUnary();
        while (true) {
            self.skipWs();
            const ch = self.peek() orelse return value;
            if (ch != '*' and ch != '/') return value;
            self.i += 1;
            const rhs = try self.parseUnary();
            if (ch == '*') {
                value *= rhs;
            } else {
                if (rhs == 0) return error.DivideByZero;
                value /= rhs;
            }
        }
    }

    fn parseUnary(self: *Parser) CalcError!f64 {
        self.skipWs();
        const ch = self.peek() orelse return error.ExpectedValue;
        if (ch == '+') {
            self.i += 1;
            return self.parseUnary();
        }
        if (ch == '-') {
            self.i += 1;
            return -(try self.parseUnary());
        }
        return self.parsePrimary();
    }

    fn parsePrimary(self: *Parser) CalcError!f64 {
        self.skipWs();
        const ch = self.peek() orelse return error.ExpectedValue;
        if (ch == '(') {
            self.i += 1;
            const v = try self.parseExpr();
            self.skipWs();
            if (self.peek() != ')') return error.MissingRightParen;
            self.i += 1;
            return v;
        }
        return self.parseNumber();
    }

    fn parseNumber(self: *Parser) CalcError!f64 {
        self.skipWs();
        const start = self.i;
        var saw_digit = false;
        var saw_dot = false;
        while (self.i < self.input.len) {
            const ch = self.input[self.i];
            if (std.ascii.isDigit(ch)) {
                saw_digit = true;
                self.i += 1;
                continue;
            }
            if (ch == '.' and !saw_dot) {
                saw_dot = true;
                self.i += 1;
                continue;
            }
            break;
        }
        if (!saw_digit) return error.ExpectedNumber;

        if (self.i < self.input.len and (self.input[self.i] == 'e' or self.input[self.i] == 'E')) {
            var j = self.i + 1;
            if (j < self.input.len and (self.input[j] == '+' or self.input[j] == '-')) j += 1;
            var exp_digits = false;
            while (j < self.input.len and std.ascii.isDigit(self.input[j])) : (j += 1) {
                exp_digits = true;
            }
            if (!exp_digits) return error.InvalidExponent;
            self.i = j;
        }

        return std.fmt.parseFloat(f64, self.input[start..self.i]) catch error.InvalidNumber;
    }
};

test "evaluateExpression handles precedence and parens" {
    try std.testing.expectApproxEqAbs(@as(f64, 7), try evaluateExpression("1 + 2*3"), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 9), try evaluateExpression("(1 + 2) * 3"), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, -2.5), try evaluateExpression("-5/2"), 1e-9);
}

test "evaluateExpression supports decimals and exponent notation" {
    try std.testing.expectApproxEqAbs(@as(f64, 1250), try evaluateExpression("1.25e3"), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 3), try evaluateExpression(".5 + 2.5"), 1e-9);
}

test "evaluateExpression returns parse and runtime errors" {
    try std.testing.expectError(error.DivideByZero, evaluateExpression("1/0"));
    try std.testing.expectError(error.MissingRightParen, evaluateExpression("(1+2"));
    try std.testing.expectError(error.ExpectedNumber, evaluateExpression("foo"));
}

test "formatNumberAlloc trims trailing zeros and integer decimals" {
    const a = try formatNumberAlloc(std.testing.allocator, 7.0);
    defer std.testing.allocator.free(a);
    try std.testing.expectEqualStrings("7", a);

    const b = try formatNumberAlloc(std.testing.allocator, 3.125000000000);
    defer std.testing.allocator.free(b);
    try std.testing.expectEqualStrings("3.125", b);
}

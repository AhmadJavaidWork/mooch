const std = @import("std");
const utils = @import("utils.zig");

const Self = @This();

request_line: RequestLine,
headers: Headers,
body: ?[]const u8 = null,

pub const Method = enum(u8) {
    get,
    post,
    connect,
    options,
};

pub const RequestErrors = error{
    MalformedRequestLine,
    NoMethodInRequestLine,
    NoURIInRequestLine,
    NoHttpVersionInRequestLine,
    NoHTTPInVersionInRequestLine,
    NoHttpVersionNumInRequestLine,
    MethodNotSupported,
};

pub const RequestLine = struct {
    method: Method,
    path: []const u8,
    version: []const u8,

    pub fn deinit(self: *RequestLine, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.version);
    }

    fn parseMethod(str: []const u8) !Method {
        return utils.iStringToEnum(Method, str) orelse error.MethodNotSupported;
    }

    pub fn format(self: *const RequestLine, writer: *std.Io.Writer) !void {
        try writer.print("RequestLine {{ method: {}, path: {s}, version: {s} }}", .{ self.method, self.path, self.version });
    }
};

pub const Headers = struct {
    headers: std.StringHashMapUnmanaged([]const u8) = .empty,

    pub fn deinit(self: *Headers, allocator: std.mem.Allocator) void {
        var it = self.headers.iterator();

        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit(allocator);
    }

    pub fn get(self: *Headers, allocator: std.mem.Allocator, key: []const u8) !?[]const u8 {
        const l_key = try std.ascii.allocLowerString(allocator, key);
        defer allocator.free(l_key);
        return self.headers.get(l_key);
    }

    pub fn put(self: *Headers, allocator: std.mem.Allocator, k: []const u8, v: []const u8) !void {
        const key = try std.ascii.allocLowerString(allocator, k);
        const val = try allocator.dupe(u8, v);
        try self.headers.put(allocator, key, val);
    }

    pub fn format(self: *const Headers, writer: *std.Io.Writer) !void {
        var it = self.headers.iterator();
        try writer.print("Headers: {{", .{});
        while (it.next()) |entry| {
            try writer.print(" {s}: {s}", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        try writer.print(" }}", .{});
    }
};

pub const Parser = struct {
    reader: *std.Io.Reader,

    pub fn parseRequestLine(self: *Parser, allocator: std.mem.Allocator) !RequestLine {
        const line = try self.reader.takeDelimiter('\r') orelse return RequestErrors.MalformedRequestLine;

        const lf = self.reader.takeByte() catch return RequestErrors.MalformedRequestLine;
        if (lf != '\n') {
            return error.MalformedRequest;
        }

        var line_iter = std.mem.tokenizeAny(u8, line, " ");

        const method_str: []const u8 = line_iter.next() orelse return RequestErrors.NoMethodInRequestLine;
        const method: Method = try parseMethod(method_str);

        const path_view: []const u8 = line_iter.next() orelse return RequestErrors.NoURIInRequestLine;
        const path = try allocator.dupe(u8, path_view);
        errdefer allocator.free(path);

        const version_view: []const u8 = line_iter.next() orelse return RequestErrors.NoHttpVersionInRequestLine;

        var version_view_iter = std.mem.splitScalar(u8, version_view, '/');
        _ = version_view_iter.next() orelse return RequestErrors.NoHTTPInVersionInRequestLine;
        const version_num_view: []const u8 = version_view_iter.next() orelse return RequestErrors.NoHttpVersionNumInRequestLine;
        const version = try allocator.dupe(u8, version_num_view);

        return .{
            .method = method,
            .path = path,
            .version = version,
        };
    }

    fn parseMethod(str: []const u8) !Method {
        return utils.iStringToEnum(Method, str) orelse RequestErrors.MethodNotSupported;
    }

    pub fn parseHeaders(self: *Parser, allocator: std.mem.Allocator) !Headers {
        var headers: Headers = .{};
        while (try self.reader.takeDelimiter('\r')) |line| {
            const lf = try self.reader.takeByte();
            if (lf != '\n') {
                return error.MalformedRequest;
            }

            if (line.len == 0) {
                break;
            }

            const colon_idx = std.mem.indexOf(u8, line, ":") orelse return error.MalformedRequestHeader;

            const key = line[0..colon_idx];
            const value = std.mem.trim(u8, line[colon_idx + 1 ..], " \t");

            try headers.put(allocator, key, value);
        }
        return headers;
    }

    pub fn parseBody(self: *Parser, allocator: std.mem.Allocator, method: Method, content_length: usize) !?[]const u8 {
        return switch (method) {
            .post => try allocator.dupe(u8, try self.reader.take(content_length)),
            else => null,
        };
    }
};

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.request_line.deinit(allocator);
    self.headers.deinit(allocator);
    if (self.body) |body| {
        allocator.free(body);
    }
}

pub fn format(self: *const Self, writer: *std.Io.Writer) !void {
    try writer.print("Request {{\n  request_line: {f},\n  headers: {f}", .{ self.request_line, self.headers });
    if (self.body) |body| {
        try writer.print("\n  body: {s}", .{body});
    }
    try writer.print("\n}}", .{});
}

test "request line" {
    const lines = [_][]const u8{
        "GET /where?q=now HTTP/1.1\r\n",
        "GET http://www.example.org/pub/WWW/TheProject.html HTTP/1.1\r\n",
        "CONNECT www.example.com:80 HTTP/1.1\r\n",
        "OPTIONS * HTTP/1.1\r\n",
    };
    const allocator = std.testing.allocator;

    const expected = [_]RequestLine{
        .{ .method = .get, .path = "/where?q=now", .version = "1.1" },
        .{ .method = .get, .path = "http://www.example.org/pub/WWW/TheProject.html", .version = "1.1" },
        .{ .method = .connect, .path = "www.example.com:80", .version = "1.1" },
        .{ .method = .options, .path = "*", .version = "1.1" },
    };

    for (lines, 0..) |line, i| {
        var reader: std.Io.Reader = .fixed(line);
        var parser = Parser{ .reader = &reader };

        const e = expected[i];

        var actual = try parser.parseRequestLine(allocator);
        defer actual.deinit(allocator);
        try std.testing.expectEqual(e.method, actual.method);
        try std.testing.expectEqualStrings(e.path, actual.path);
        try std.testing.expectEqualStrings(e.version, actual.version);
    }
}

test "invalid request line" {
    const lines = [_][]const u8{
        "",
        "GET/where?q=now HTTP/1.1\r\n",
        "\r\n",
        "GET HTTP/1.1\r\n",
        "GET * 1.1\r\n",
    };
    const allocator = std.testing.allocator;

    const expected = [_]RequestErrors{
        RequestErrors.MalformedRequestLine,
        RequestErrors.MethodNotSupported,
        RequestErrors.NoMethodInRequestLine,
        RequestErrors.NoHttpVersionInRequestLine,
        RequestErrors.NoHttpVersionNumInRequestLine,
    };

    for (lines, 0..) |line, i| {
        var reader: std.Io.Reader = .fixed(line);
        var parser = Parser{ .reader = &reader };

        const e = expected[i];

        const actual = parser.parseRequestLine(allocator);
        try std.testing.expectError(e, actual);
    }
}

test "headers" {
    const headers = [_][]const u8{
        "Content-Length: 123\r\n\r\n",
        "Content-Type:     \t\t\t application/json \t\t\t      \r\n\r\n",
    };

    const allocator = std.testing.allocator;
    const Header = struct {
        key: []const u8,
        val: []const u8,
    };

    const expected = [_]Header{
        .{ .key = "content-length", .val = "123" },
        .{ .key = "content-type", .val = "application/json" },
    };

    for (headers, 0..) |header, i| {
        var reader: std.Io.Reader = .fixed(header);
        var parser = Parser{ .reader = &reader };

        const e = expected[i];

        var actual_headers = try parser.parseHeaders(allocator);
        defer actual_headers.deinit(allocator);
        const val = try actual_headers.get(allocator, e.key);

        try std.testing.expect(val != null);

        if (val) |v| {
            try std.testing.expectEqualStrings(e.val, v);
        }
    }
}

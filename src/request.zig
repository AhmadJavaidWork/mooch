const std = @import("std");
const Headers = @import("headers.zig");
const utils = @import("utils.zig");

const Self = @This();

request_line: RequestLine,
headers: Headers,
body: ?[]const u8 = null,
state: State = State.init,

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
    MalformedVersionNumber,
    MethodNotSupported,
    MalformedFieldLine,
};

pub fn init() Self {
    return .{
        .request_line = RequestLine{
            .method = .get,
            .path = "/",
            .version = "HTTP/1.1",
        },
        .headers = Headers{ .headers = .empty },
    };
}

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

pub const State = enum(u8) {
    init,
    parsing_request_line,
    parsing_headers,
    parsing_body,
    done,
};

pub fn parse(self: *Self, allocator: std.mem.Allocator, reader: *std.Io.Reader) !void {
    while (self.state != State.done) {
        switch (self.state) {
            .init => {
                self.state = State.parsing_request_line;
            },
            .parsing_request_line => {
                self.request_line = try parseRequestLine(allocator, reader);
                self.state = State.parsing_headers;
            },
            .parsing_headers => {
                self.headers = try parseHeaders(allocator, reader);
                self.state = State.parsing_body;
            },
            .parsing_body => {
                const content_length_header = try self.headers.get(allocator, "Content-Length");
                if (content_length_header) |val| {
                    const content_length = try std.fmt.parseInt(usize, val, 10);
                    self.body = try parseBody(allocator, reader, self.request_line.method, content_length);
                }
                self.state = State.done;
            },
            .done => {
                break;
            },
        }
    }
}

fn parseRequestLine(allocator: std.mem.Allocator, reader: *std.Io.Reader) !RequestLine {
    try takeEmptyLines(reader);
    const line = try takeLine(reader);

    var line_iter = std.mem.tokenizeAny(u8, line, " ");

    const method_str: []const u8 = line_iter.next() orelse return RequestErrors.NoMethodInRequestLine;
    const method: Method = try strToMethod(method_str);

    const path_view: []const u8 = line_iter.next() orelse return RequestErrors.NoURIInRequestLine;
    const path = try allocator.dupe(u8, path_view);
    errdefer allocator.free(path);

    const version_view: []const u8 = line_iter.next() orelse return RequestErrors.NoHttpVersionInRequestLine;

    if (!std.mem.startsWith(u8, version_view, "HTTP/")) {
        return RequestErrors.MalformedVersionNumber;
    }

    const version = try allocator.dupe(u8, version_view);

    return .{
        .method = method,
        .path = path,
        .version = version,
    };
}

fn takeEmptyLines(reader: *std.Io.Reader) !void {
    var start: usize = reader.seek;

    while (true) {
        const line = reader.takeDelimiter('\r') catch {
            return RequestErrors.MalformedRequestLine;
        } orelse return RequestErrors.MalformedRequestLine;
        const lf = reader.takeByte() catch return RequestErrors.MalformedRequestLine;
        if (lf != '\n') {
            return RequestErrors.MalformedRequestLine;
        }

        if (line.len > 0) break;

        start = reader.seek;
    }

    reader.seek = start;
    return;
}

fn takeLine(reader: *std.Io.Reader) ![]const u8 {
    const line = reader.takeDelimiter('\r') catch {
        return RequestErrors.MalformedRequestLine;
    } orelse return RequestErrors.MalformedRequestLine;

    const lf = reader.takeByte() catch return RequestErrors.MalformedRequestLine;
    if (lf != '\n') {
        return RequestErrors.MalformedRequestLine;
    }

    return line;
}

fn strToMethod(str: []const u8) !Method {
    return utils.iStringToEnum(Method, str) orelse RequestErrors.MethodNotSupported;
}

fn parseHeaders(allocator: std.mem.Allocator, reader: *std.Io.Reader) !Headers {
    var headers: Headers = .{};
    while (try reader.takeDelimiter('\r')) |line| {
        const lf = try reader.takeByte();
        if (lf != '\n') {
            return RequestErrors.MalformedFieldLine;
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

fn parseBody(allocator: std.mem.Allocator, reader: *std.Io.Reader, method: Method, content_length: usize) !?[]const u8 {
    return switch (method) {
        .post => try allocator.dupe(u8, try reader.take(content_length)),
        else => null,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    if (@intFromEnum(self.state) > @intFromEnum(State.parsing_request_line)) {
        self.request_line.deinit(allocator);
        self.headers.deinit(allocator);
        if (self.body) |body| {
            allocator.free(body);
        }
    }
}

pub fn format(self: *const Self, writer: *std.Io.Writer) !void {
    try writer.print("Request {{\n  request_line: {f},\n  headers: {f}", .{ self.request_line, self.headers });
    if (self.body) |body| {
        try writer.print("\n  body: {s}", .{body});
    }
    try writer.print("\n}}", .{});
}

fn testRequestLine(actual: RequestLine, expected: RequestLine) !void {
    try std.testing.expectEqual(expected.method, actual.method);
    try std.testing.expectEqualStrings(expected.path, actual.path);
    try std.testing.expectEqualStrings(expected.version, actual.version);
}

const TestHeader = struct {
    key: []const u8,
    val: []const u8,
};

fn testHeaders(actual: Headers, expected: []const TestHeader) !void {
    const allocator = std.testing.allocator;
    for (expected) |e| {
        const val = try actual.get(allocator, e.key);

        try std.testing.expect(val != null);

        if (val) |v| {
            try std.testing.expectEqualStrings(e.val, v);
        }
    }
}

fn testBody(actual: ?[]const u8, expected: ?[]const u8) !void {
    if (expected) |e| {
        try std.testing.expect(actual != null);
        if (actual) |a| {
            try std.testing.expectEqualStrings(e, a);
        }
    }
}

test "request line" {
    const allocator = std.testing.allocator;

    const raws = [_][]const u8{
        "GET /where?q=now HTTP/1.1\r\n",
        "\r\nGET /where?q=now HTTP/1.1\r\n",
        "GET http://www.example.org/pub/WWW/TheProject.html HTTP/1.1\r\n",
        "CONNECT www.example.com:80 HTTP/1.1\r\n",
        "OPTIONS * HTTP/1.1\r\n",
    };

    const expected = [_]RequestLine{
        .{ .method = .get, .path = "/where?q=now", .version = "HTTP/1.1" },
        .{ .method = .get, .path = "/where?q=now", .version = "HTTP/1.1" },
        .{ .method = .get, .path = "http://www.example.org/pub/WWW/TheProject.html", .version = "HTTP/1.1" },
        .{ .method = .connect, .path = "www.example.com:80", .version = "HTTP/1.1" },
        .{ .method = .options, .path = "*", .version = "HTTP/1.1" },
    };

    for (raws, 0..) |raw, i| {
        var reader: std.Io.Reader = .fixed(raw);

        var actual = try parseRequestLine(allocator, &reader);
        defer actual.deinit(allocator);
        try testRequestLine(actual, expected[i]);
    }
}

test "invalid request line" {
    const allocator = std.testing.allocator;

    const raws = [_][]const u8{
        "",
        "GET/where?q=now HTTP/1.1\r\n",
        "\r\n",
        "GET HTTP/1.1\r\n",
        "GET * 1.1\r\n",
    };

    const expected = [_]RequestErrors{
        RequestErrors.MalformedRequestLine,
        RequestErrors.MethodNotSupported,
        RequestErrors.MalformedRequestLine,
        RequestErrors.NoHttpVersionInRequestLine,
        RequestErrors.MalformedVersionNumber,
    };

    for (raws, 0..) |raw, i| {
        var reader: std.Io.Reader = .fixed(raw);

        const e = expected[i];

        const actual = parseRequestLine(allocator, &reader);
        try std.testing.expectError(e, actual);
    }
}

test "headers" {
    const allocator = std.testing.allocator;

    const raws = [_][]const u8{
        "Content-Length: 123\r\n\r\n",
        "Content-Type:     \t\t\t application/json \t\t\t      \r\n\r\n",
    };

    const expected = [_][]const TestHeader{
        &[_]TestHeader{.{ .key = "content-length", .val = "123" }},
        &[_]TestHeader{.{ .key = "content-type", .val = "application/json" }},
    };

    for (raws, 0..) |raw, i| {
        var reader: std.Io.Reader = .fixed(raw);

        var actual = try parseHeaders(allocator, &reader);
        defer actual.deinit(allocator);

        try testHeaders(actual, expected[i]);
    }
}

test "request with body" {
    const allocator = std.testing.allocator;

    const req = "POST / HTTP/1.1\r\nContent-Length: 19\r\nContent-Type: application/json\r\n\r\n{\n\t\"name\": \"john\"\n}";
    var reader: std.Io.Reader = .fixed(req);

    var request = Self.init();
    defer request.deinit(allocator);

    try request.parse(allocator, &reader);

    const expected_request_line = RequestLine{
        .method = Method.post,
        .path = "/",
        .version = "HTTP/1.1",
    };
    try testRequestLine(request.request_line, expected_request_line);

    const expected_headers = [_]TestHeader{
        .{ .key = "Content-Length", .val = "19" },
        .{ .key = "Content-Type", .val = "application/json" },
    };
    try testHeaders(request.headers, &expected_headers);

    try testBody(request.body, "{\n\t\"name\": \"john\"\n}");
}

const std = @import("std");
const Headers = @import("headers.zig");
const utils = @import("utils.zig");

const Self = @This();

pub const StatusCode = enum(u16) {
    ok = 200,
    created = 201,
    bad_request = 400,
    not_found = 404,
};

status_code: StatusCode,
http_version: []const u8,
reason_phrase: ?[]const u8 = null,
headers: Headers,
body: ?[]const u8 = null,

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.headers.deinit(allocator);
}

pub fn serialize(self: *const Self, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    try self.writeStatusLine(writer);
    try self.writeHeaders(allocator, writer);
    try self.writeBody(writer);
}

fn writeStatusLine(self: *const Self, w: *std.Io.Writer) !void {
    _ = try w.write(self.http_version);
    try w.writeByte(' ');
    try w.print("{d} ", .{@intFromEnum(self.status_code)});

    if (self.reason_phrase) |reason| {
        try w.print("{s}", .{reason});
    }
    _ = try w.write("\r\n");
}

fn writeHeaders(self: *const Self, allocator: std.mem.Allocator, w: *std.Io.Writer) !void {
    var header_iter = self.headers.headers.iterator();
    while (header_iter.next()) |entry| {
        const key = try utils.capitalizeByHyphen(allocator, entry.key_ptr.*);
        defer allocator.free(key);

        try w.print("{s}: ", .{key});
        try w.print("{s}\r\n", .{entry.value_ptr.*});
    }
    _ = try w.write("\r\n");
}

fn writeBody(self: *const Self, w: *std.Io.Writer) !void {
    if (self.body) |b| {
        _ = try w.write(b);
    }
}

test "serialize response" {
    const allocator = std.testing.allocator;

    var response_headers = Headers{};
    try response_headers.put(allocator, "Content-Type", "text/plain; charset=utf-8");
    try response_headers.put(allocator, "Content-Length", "15");
    try response_headers.put(allocator, "Connection", "close");

    var response = Self{
        .status_code = Self.StatusCode.ok,
        .http_version = "HTTP/1.1",
        .headers = response_headers,
        .body = "Hello world!!!",
        .reason_phrase = "OK",
    };
    defer response.deinit(allocator);

    var actual: [1024 * 8]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&actual);
    try response.serialize(allocator, &writer);

    const expected = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 15\r\nConnection: close\r\n\r\nHello world!!!";

    try std.testing.expectEqualStrings(expected, actual[0..writer.end]);
}

const std = @import("std");
const Request = @import("request.zig");
const Response = @import("response.zig");
const Headers = @import("headers.zig");

const Self = @This();

stream: std.Io.net.Stream,
reader: *std.Io.Reader,
writer: *std.Io.Writer,

pub fn handleConnection(self: *Self, allocator: std.mem.Allocator, io: std.Io) !void {
    var request_paser = Request.Parser{ .reader = self.reader };

    const request_line = try request_paser.parseRequestLine(allocator);
    var headers = try request_paser.parseHeaders(allocator);
    const content_length_header = try headers.get(allocator, "Content-Length");
    var body: ?[]const u8 = null;
    if (content_length_header) |val| {
        const content_length = try std.fmt.parseInt(usize, val, 10);
        body = try request_paser.parseBody(allocator, request_line.method, content_length);
    }

    var request = Request{
        .request_line = request_line,
        .headers = headers,
        .body = body,
    };

    std.debug.print("{f}\n", .{request});

    var response_headers = Headers{};
    try response_headers.put(allocator, "Content-Type", "text/plain; charset=utf-8");
    try response_headers.put(allocator, "Content-Length", "14");
    try response_headers.put(allocator, "Connection", "close");

    var response = Response{
        .status_code = Response.StatusCode.ok,
        .http_version = "HTTP/1.1",
        .headers = response_headers,
        .body = "Hello world!!!",
        .reason_phrase = "OK",
    };
    defer response.deinit(allocator);
    try self.send_response(allocator, &response);

    request.deinit(allocator);
    self.close(io);
}

pub fn close(self: *Self, io: std.Io) void {
    self.stream.close(io);
}

pub fn send_response(self: *Self, allocator: std.mem.Allocator, response: *const Response) !void {
    // TODO: refactor buffer allocation
    var buf: [1024 * 8]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try response.serialize(allocator, &w);

    _ = try self.writer.write(buf[0..w.end]);
    try self.writer.flush();
}

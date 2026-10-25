const std = @import("std");
const Request = @import("request/request.zig");
const print = std.debug.print;

stream: std.Io.net.Stream,
reader: *std.Io.Reader,
writer: *std.Io.Writer,

const Self = @This();

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

    print("{f}\n", .{request});

    try self.send_response(
        \\HTTP/1.1 200
        \\Content-Type: text/plain; charset=utf-8
        \\Content-Length:15
        \\Connection: close
        \\
        \\Hello, world!!!
    );

    request.deinit(allocator);
    self.close(io);
}

pub fn close(self: *Self, io: std.Io) void {
    self.stream.close(io);
}

pub fn send_response(self: *Self, response: []const u8) !void {
    _ = try self.writer.write(response);
    try self.writer.flush();
}

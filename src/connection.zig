const std = @import("std");
const Request = @import("request.zig");
const Response = @import("response.zig");
const Headers = @import("headers.zig");

const Self = @This();

stream: std.Io.net.Stream,
reader: *std.Io.Reader,
writer: *std.Io.Writer,

pub fn handleConnection(self: *Self, allocator: std.mem.Allocator, io: std.Io) !void {
    var request = Request.init();
    defer request.deinit(allocator);
    request.parse(allocator, self.reader) catch |err| {
        switch (err) {
            error.MethodNotSupported => {
                try self.responedWithNotImplemented(allocator);
                return;
            },
            else => {
                return err;
            },
        }
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
    try self.sendResponse(allocator, &response);

    self.close(io);
}

pub fn close(self: *Self, io: std.Io) void {
    self.stream.close(io);
}

pub fn sendResponse(self: *Self, allocator: std.mem.Allocator, response: *const Response) !void {
    // TODO: refactor buffer allocation
    var buf: [1024 * 8]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try response.serialize(allocator, &w);

    _ = try self.writer.write(buf[0..w.end]);
    try self.writer.flush();
}

pub fn responedWithNotImplemented(self: *Self, allocator: std.mem.Allocator) !void {
    var response_headers = Headers{};
    try response_headers.put(allocator, "Connection", "close");

    var response = Response{
        .status_code = Response.StatusCode.not_implemented,
        .http_version = "HTTP/1.1",
        .headers = response_headers,
        .reason_phrase = "NOT IMPLEMENTED",
    };
    defer response.deinit(allocator);
    try self.sendResponse(allocator, &response);
}

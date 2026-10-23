const std = @import("std");
const Request = @import("request.zig");
const print = std.debug.print;

stream: std.Io.net.Stream,
reader: *std.Io.Reader,
writer: *std.Io.Writer,

const Self = @This();

pub fn init(stream: std.Io.net.Stream, io: std.Io, read_buffer: []u8, write_buffer: []u8) Self {
    var r = stream.reader(io, read_buffer);
    var w = stream.writer(io, write_buffer);

    return .{
        .stream = stream,
        .reader = &r.interface,
        .writer = &w.interface,
    };
}

pub fn handleConnection(self: *Self, allocator: std.mem.Allocator, io: std.Io) !void {
    print("connection accepted\n", .{});

    const request = try Request.init(allocator, self.reader);
    print("method: {}\n", .{request.request_line.method});
    print("uri: {s}\n", .{request.request_line.uri});
    print("version: {s}\n", .{request.request_line.version});

    var iter = request.headers.iterator();
    while (iter.next()) |entry| {
        print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    if (request.headers.get("Content-Length")) |content_length| {
        print("content length is: {s}\n", .{content_length});
    }

    if (request.body) |body| {
        print("body: {s}\n", .{body});
    }
    _ = try self.writer.write(
        \\HTTP/1.1 200
        \\Content-Type: text/plain; charset=utf-8
        \\Content-Length:15
        \\Connection: close
        \\
        \\Hello, world!!!
    );

    try self.writer.flush();
    self.stream.close(io);
}

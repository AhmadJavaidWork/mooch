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
    print("method: {}\n", .{request.method});

    while (try self.reader.takeDelimiter('\r')) |line| {
        const lf = try self.reader.takeByte();

        if (lf != '\n') {
            return error.MalformedRequest;
        }

        if (line.len == 0) {
            break;
        }

        print("{s}\n", .{line});
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

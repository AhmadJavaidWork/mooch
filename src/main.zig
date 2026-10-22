const std = @import("std");
const Server = @import("server.zig");
const Connection = @import("connection.zig");

const print = std.debug.print;

pub fn main(init: std.process.Init) !void {
    const port = try getPort(init);
    var server = Server{
        .address = .{ .ip4 = .loopback(port) },
        .options = .{ .reuse_address = true },
    };
    try server.start(init.io);
    print("server started on port: {d}\n", .{port});

    while (true) {
        const stream = try server.accept(init.io);
        try handleConnection(init.gpa, init.io, stream);
    }
}

fn handleConnection(allocator: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream) !void {
    var read_buffer: [100]u8 = undefined;
    var write_buffer: [1024 * 4]u8 = undefined;

    var r = stream.reader(io, &read_buffer);
    var w = stream.writer(io, &write_buffer);

    var conn: Connection = Connection{
        .stream = stream,
        .reader = &r.interface,
        .writer = &w.interface,
    };

    try conn.handleConnection(allocator, io);
}

fn getPort(init: std.process.Init) !u16 {
    const port = init.environ_map.get("PORT");
    if (port) |p| {
        return std.fmt.parseInt(u16, p, 10);
    }

    return 8080;
}

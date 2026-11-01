const std = @import("std");
const net = std.Io.net;

const Self = @This();

address: net.IpAddress,
options: net.IpAddress.ListenOptions,
server: ?net.Server = null,

pub fn start(self: *Self, io: std.Io) !void {
    self.server = try net.IpAddress.listen(&self.address, io, self.options);
}

pub fn accept(self: *Self, io: std.Io) !net.Stream {
    return self.server.?.accept(io);
}

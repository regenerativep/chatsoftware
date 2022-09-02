const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;

const p = @import("protocol.zig");

pub const ConnectedClient = struct {
    name: []const u8,
    stream: net.Stream,
    id: ?p.ClientId = null,

    pub fn deinit(self: *ConnectedClient) void {
        self.stream.close();
        self.* = undefined;
    }
};

pub fn clientReceiveLoop(alloc: Allocator, client: *ConnectedClient) !void {
    defer std.log.info("connection closed", .{});
    var stream_buffered = std.io.bufferedReader(client.stream.reader());
    var reader = stream_buffered.reader();

    var client_names = std.AutoHashMap(p.ClientId, []const u8).init(alloc);
    defer {
        var iter = client_names.valueIterator();
        while (iter.next()) |name| alloc.free(name.*);
        client_names.deinit();
    }

    while (true) {
        var packet = try p.CB.readAlloc(alloc, reader);
        defer p.CB.deinit(packet, alloc);

        switch (packet) {
            .accepted => |d| {
                client.id = d.id;
                {
                    const duped_name = try alloc.dupe(u8, client.name);
                    errdefer alloc.free(duped_name);
                    try client_names.put(d.id, duped_name);
                }
                std.log.info("connected with client id {}\n", .{d.id});
            },
            .message => |d| {
                if (client_names.get(d.from)) |message_user_name| {
                    std.log.info("{s}: {s}\n", .{ message_user_name, d.text });
                } else {
                    std.log.info("{}: {s}\n", .{ d.from, d.text });
                }
            },
            .user_connect => |d| {
                const duped_name = try alloc.dupe(u8, d.name.slice());
                errdefer alloc.free(duped_name);
                try client_names.put(d.id, duped_name);
            },
        }
    }
}

pub fn run(alloc: Allocator, address: net.Address, name: []const u8) !void {
    var client = ConnectedClient{
        .stream = try net.tcpConnectToAddress(address),
        .name = name,
    };
    defer client.deinit();

    _ = async clientReceiveLoop(alloc, &client);

    var buffered_stream_writer = std.io.bufferedWriter(client.stream.writer());
    var stream_writer = buffered_stream_writer.writer();
    try p.SB.write(
        p.SB.UserType{ .introduce = .{ .name = p.SerdeName.UserType.fromSlice(name) catch {
            return std.log.err("the name you chose is too long", .{});
        } } },
        stream_writer,
    );
    try buffered_stream_writer.flush();

    // user input
    var stdin = std.io.getStdIn();
    defer stdin.close();
    while (true) {
        var buf: [4096]u8 = undefined;
        const line = try stdin.reader().readUntilDelimiter(&buf, '\n');
        try p.SB.write(p.SB.UserType{ .message = .{ .text = line } }, stream_writer);
        try buffered_stream_writer.flush();
    }
}

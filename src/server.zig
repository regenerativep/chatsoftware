const std = @import("std");
const net = std.net;
const time = std.time;
const Allocator = std.mem.Allocator;

const p = @import("protocol.zig");

pub const Room = struct {
    pub const ClientMap = std.AutoHashMapUnmanaged(p.ClientId, *Client);
    pub const DeadClientQueue = std.atomic.Queue(p.ClientId);

    clients_lock: std.event.RwLock = std.event.RwLock.init(),
    clients: ClientMap = .{},
    dead_clients: DeadClientQueue = DeadClientQueue.init(),

    pub fn cleanupLoop(self: *Room, alloc: Allocator) void {
        while (true) { // TODO: should this be conditional?
            while (self.dead_clients.get()) |node| {
                var lock = self.clients_lock.acquireWrite();
                defer lock.release();
                var pair = self.clients.fetchRemove(node.data);
                if (pair) |inner| alloc.destroy(inner.value);
            }
            time.sleep(10 * time.ns_per_s); // 10 sec
        }
    }

    pub fn deinit(self: *Room, alloc: Allocator) void {
        var lock = self.clients_lock.acquireWrite();
        defer lock.release();
        var iter = self.clients.valueIterator();
        while (iter.next()) |client| {
            alloc.destroy(client.*);
        }
        self.clients.deinit(alloc);
        self.* = undefined;
    }
};

pub const Client = struct {
    data_lock: std.event.Lock = .{},
    name: ?std.BoundedArray(u8, p.MAX_NAME_LEN) = null,
    id: p.ClientId,

    stream: net.Stream,
    handle_incoming: @Frame(handleIncoming),

    reader: std.io.BufferedReader(4096, net.Stream.Reader),

    writer: std.io.BufferedWriter(4096, net.Stream.Writer),
    writer_lock: std.event.Lock = .{},

    // no deinit function because this is handled with the cleanup system and this fn's defer
    pub fn handleIncoming(self: *Client, alloc: Allocator, room: *Room) !void {
        defer {
            {
                var lock = self.data_lock.acquire();
                defer lock.release();
                if (self.name) |*name| {
                    std.log.info("\"{s}\"({}) disconnected", .{ name.slice(), self.id });
                } else {
                    std.log.info("({}) disconnected", .{self.id});
                }
            }
            self.stream.close();

            var node = Room.DeadClientQueue.Node{
                .data = self.id,
                .next = undefined,
                .prev = undefined,
            };
            // it should be okay to rely on the stack here because this frame is async and persists
            room.dead_clients.put(&node);
        }

        while (true) {
            var packet = try p.SB.readAlloc(alloc, self.reader.reader());
            defer p.SB.deinit(packet, alloc);

            switch (packet) {
                .introduce => |d| {
                    std.log.info("\"{s}\" connected", .{d.name.slice()});
                    var already_introduced = false;
                    {
                        var lock = self.data_lock.acquire();
                        defer lock.release();
                        if (self.name != null) already_introduced = true;
                        self.name = d.name;
                    }

                    var clients_lock = room.clients_lock.acquireRead();
                    defer clients_lock.release();

                    // send a list of all of the clients to the newly introduced client
                    var iter = room.clients.valueIterator();
                    {
                        var lock = self.writer_lock.acquire();
                        defer lock.release();

                        try p.CB.write(p.CB.UserType{ .accepted = .{ .id = self.id } }, self.writer.writer());
                        if (!already_introduced) {
                            while (iter.next()) |value| {
                                var data_lock = value.*.data_lock.acquire();
                                defer data_lock.release();

                                if (value.*.name) |name_arr| {
                                    try p.CB.write(p.CB.UserType{ .user_connect = .{
                                        .name = name_arr,
                                        .id = value.*.id,
                                    } }, self.writer.writer());
                                }
                            }
                        }
                        try self.writer.flush();
                    }

                    iter = room.clients.valueIterator();
                    while (iter.next()) |value| {
                        var lock = value.*.writer_lock.acquire();
                        defer lock.release();
                        try p.CB.write(p.CB.UserType{ .user_connect = .{
                            .id = self.id,
                            .name = d.name,
                        } }, value.*.writer.writer());
                        try value.*.writer.flush();
                    }
                },
                .message => |d| {
                    const text = std.mem.trim(u8, d.text, &std.ascii.spaces);
                    if (text.len > 0) {
                        {
                            var data_lock = self.data_lock.acquire();
                            defer data_lock.release();
                            if (self.name) |*name| {
                                std.log.info("\"{s}\": {s}", .{ name.slice(), d.text });
                            }
                        }

                        var clients_lock = room.clients_lock.acquireRead();
                        defer clients_lock.release();

                        var iter = room.clients.valueIterator();
                        while (iter.next()) |value| {
                            var lock = value.*.writer_lock.acquire();
                            defer lock.release();

                            try p.CB.write(p.CB.UserType{ .message = .{
                                .from = self.id,
                                .text = text,
                            } }, value.*.writer.writer());
                            try value.*.writer.flush();
                        }
                    }
                },
            }
        }
    }
};

pub fn run(alloc: Allocator, port: u16) !void {
    var server = net.StreamServer.init(.{ .reuse_address = true });
    defer server.deinit();

    const address = net.Address.initIp4([4]u8{ 0, 0, 0, 0 }, port);
    try server.listen(address);
    std.log.info("listening on address {}", .{address});

    var room = Room{};
    defer room.deinit(alloc);

    var last_id: p.ClientId = 0;

    _ = async room.cleanupLoop(alloc);

    while (true) {
        // connection accept loop
        const conn = try server.accept();
        errdefer conn.stream.close();

        std.log.info("connection from {}", .{conn.address});

        var client = try alloc.create(Client);
        errdefer alloc.destroy(client);

        client.* = .{
            .name = null,
            .id = last_id,
            .stream = conn.stream,
            .writer = undefined,
            .reader = undefined,
            .handle_incoming = undefined,
        };
        client.writer = .{ .unbuffered_writer = client.stream.writer() };
        client.reader = .{ .unbuffered_reader = client.stream.reader() };
        {
            var lock = room.clients_lock.acquireWrite();
            defer lock.release();
            try room.clients.putNoClobber(alloc, client.id, client);
        }
        client.handle_incoming = async client.handleIncoming(alloc, &room);

        last_id += 1;
    }
}

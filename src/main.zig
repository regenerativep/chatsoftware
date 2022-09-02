const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;

const p = @import("protocol.zig");

const client = @import("client.zig");
const server = @import("server.zig");

pub const io_mode = .evented;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    if (!args.skip()) unreachable;

    const action_str = args.next() orelse {
        return std.log.err("Expected an action \"host\" or \"connect\"", .{});
    };
    const action = std.meta.stringToEnum(enum { host, connect }, action_str) orelse {
        return std.log.err("Unknown action \"{s}\". Use \"host\" or \"connect\"", .{action_str});
    };
    switch (action) {
        .host => {
            const port: u16 = if (args.next()) |port_str|
                std.fmt.parseInt(u16, port_str, 10) catch |e| {
                    return std.log.err("failed to parse port: {any}", .{e});
                }
            else blk: {
                const fallback_port = 5524;
                std.log.warn("no port specified, using {}", .{fallback_port});
                break :blk fallback_port;
            };
            try server.run(alloc, port);
        },
        .connect => {
            const name = args.next() orelse return std.log.err("Expected a display name", .{});
            const ip_str = args.next() orelse return std.log.err("Expected an ip address", .{});
            const port: u16 = if (args.next()) |port_str|
                std.fmt.parseInt(u16, port_str, 10) catch |e| {
                    return std.log.err("failed to parse port: {any}", .{e});
                }
            else blk: {
                const fallback_port = 5524;
                std.log.warn("no port specified, using {}", .{fallback_port});
                break :blk fallback_port;
            };
            const address = net.Address.parseIp4(ip_str, port) catch |e| {
                return std.log.err("failed to parse ip address: {any}", .{e});
            };
            try client.run(alloc, address, name);
        },
    }
}

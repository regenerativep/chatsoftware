const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;

const serde = @import("serde");

pub fn LimitedArray(
    comptime PartialLength: type,
    comptime PartialElement: type,
    comptime max_capacity: comptime_int,
) type {
    const Length = serde.bare.Spec(PartialLength, PartialLength);
    const Element = serde.bare.Spec(PartialElement, PartialElement);
    return serde.Prefixed(
        serde.IntRestricted(Length, usize, .{}),
        serde.LimitedArray(Element, max_capacity),
    );
}

pub fn TaggedUnion(
    comptime PartialTag: type,
    comptime PartialUnion: type,
) type {
    const UserType = serde.GetUserType(PartialUnion);
    const SerdeUnion = serde.TaggedUnion(serde.bare, PartialTag, PartialUnion, UserType);
    return SerdeUnion;
}

pub fn PrefixedArray(
    comptime PartialLength: type,
    comptime PartialElement: type,
) type {
    return serde.Prefixed(
        serde.IntRestricted(serde.bare.Spec(PartialLength, PartialLength), usize, .{}),
        serde.DynamicArray(serde.bare.Spec(PartialElement, PartialElement)),
    );
}
pub fn PrefixedArrayMax(
    comptime PartialLength: type,
    comptime PartialElement: type,
    comptime max: comptime_int,
) type {
    return serde.Prefixed(
        serde.IntRestricted(serde.bare.Spec(PartialLength, PartialLength), usize, .{ .max = max }),
        serde.DynamicArray(serde.bare.Spec(PartialElement, PartialElement)),
    );
}

pub const MAX_NAME_LEN = 128;

pub const ClientId = u16;

pub const SerdeName = LimitedArray(u8, u8, MAX_NAME_LEN);
/// clientbound packet specification
pub const CB = TaggedUnion(u8, union(PacketIds) {
    pub const PacketIds = enum(u8) {
        accepted = 0x00,
        message = 0x01,
        user_connect = 0x02,
    };

    accepted: struct {
        id: ClientId,
    },
    message: struct {
        from: ClientId,
        text: PrefixedArray(u16, u8),
    },
    user_connect: struct {
        id: ClientId,
        name: SerdeName,
    },
});

/// serverbound packet specification
pub const SB = TaggedUnion(u8, union(PacketIds) {
    pub const PacketIds = enum(u8) {
        introduce = 0x00,
        message = 0x01,
    };

    introduce: struct {
        name: SerdeName,
    },
    message: struct {
        text: PrefixedArray(u16, u8),
    },
});

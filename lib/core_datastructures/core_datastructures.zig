const std = @import("std");

pub const deque = @import("deque.zig");

test {
    std.testing.refAllDecls(@This());
}

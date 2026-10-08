const std = @import("std");

pub const deque = @import("deque.zig");
pub const matrix = @import("matrix.zig");

test {
    std.testing.refAllDecls(@This());
}

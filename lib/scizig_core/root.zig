const std = @import("std");

pub const deque = @import("deque.zig");
pub const matrix = @import("matrix.zig");
pub const heap = @import("heap.zig");

test {
    std.testing.refAllDecls(@This());
}

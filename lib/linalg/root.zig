const std = @import("std");

pub const operations = @import("operations.zig");
pub const decomposition = @import("decomposition.zig");

test {
    std.testing.refAllDecls(@This());
}

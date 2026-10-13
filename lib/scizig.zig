const std = @import("std");

pub const core = @import("scizig_core/core.zig");

pub const linalg = @import("linalg/linalg.zig");

test {
    std.testing.refAllDecls(@This());
}

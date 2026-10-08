const std = @import("std");

pub const Shape = struct { rows: usize, cols: usize };
pub const Stride = struct { row: usize, col: usize };

/// A two dimentional array
pub fn Matrix(Element: type) type {
    return struct {
        const Matrix = @This();
        /// The data in the matrix
        data: []Element,
        /// The starting position of the matrix in `data`
        start: usize,
        /// The shape of the matrix (rows, columns)
        shape: Shape,
        /// The stride of the matrix
        stride: Stride,

        pub fn init(allocator: std.mem.Allocator, shape: Shape) !Matrix {
            return .{
                .data = try allocator.alloc(Element, shape.rows * shape.cols),
                .start = 0,
            };
        }
    };
}

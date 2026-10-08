const std = @import("std");

const core = @import("scizig_core");
const matrix = core.matrix;
const Matrix = matrix.Matrix;

/// Errors that may occur during the operations
const LinAlgError = error{
    /// Matrices have incompatible shapes for desired operation
    IncompatibleShapes,
    /// Failed to allocate memory for result Matrix
    OutOfMemory,
    /// Tried to access an out of bounds coordinate
    InvalidCoord,
    /// Matrices are not broadcastable into a common shape
    Unbroadcastable,
    /// Shape mismatch for operation
    InvalidShape,
};
/// Matrix multiplication of two matrices
///
/// Must have compatible shapes (mxn nxp resulting in and mxp matrix)
fn matMul(comptime Element: type, allocator: std.mem.Allocator, a: Matrix(Element), b: Matrix(Element)) LinAlgError!Matrix(Element) {
    if (a.shape.cols != b.shape.rows) {
        return LinAlgError.IncompatibleShapes;
    }
    // Create the resulting matrix
    var result = try Matrix(Element).initZeros(
        allocator,
        .{ .rows = a.shape.rows, .cols = b.shape.cols },
    );

    for (0..result.shape.rows) |row| {
        for (0..result.shape.cols) |col| {
            for (0..a.shape.cols) |shared_idx| {
                (try result.at(row, col)).* += (try a.get(row, shared_idx)) * try b.get(shared_idx, col);
            }
        }
    }

    return result;
}

test "Matrix Multiplication" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var a_data = [_]i32{ 1, 0, 1, 2, 1, 1, 0, 1, 1, 1, 1, 2 };
    const a = try Matrix(i32).initFromSlice(&a_data, 0, .{ .rows = 4, .cols = 3 });

    var b_data = [_]i32{ 1, 2, 1, 2, 3, 1, 4, 2, 2 };
    const b = try Matrix(i32).initFromSlice(&b_data, 0, .{ .rows = 3, .cols = 3 });

    var expected_ab_data = [_]i32{ 5, 4, 3, 8, 9, 5, 6, 5, 3, 11, 9, 6 };
    const expected_ab = try Matrix(i32).initFromSlice(&expected_ab_data, 0, .{ .rows = 4, .cols = 3 });

    var ab = try matMul(i32, test_allocator, a, b);
    defer ab.deinit(test_allocator);

    try std.testing.expect(Matrix(i32).equal(ab, expected_ab));
}

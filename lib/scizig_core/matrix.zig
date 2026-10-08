const std = @import("std");

pub const MatrixShape = struct {
    rows: usize,
    cols: usize,

    pub fn broadcast(shape1: MatrixShape, shape2: MatrixShape) MatrixError!MatrixShape {
        if (MatrixShape.equal(shape1, shape2)) {
            return shape1;
        }
        var broadcast_shape = MatrixShape{ .rows = shape1.rows, .cols = shape1.cols };
        if (shape1.rows != shape2.rows) {
            if (shape1.rows == 1 or shape2.rows == 1) {
                broadcast_shape.rows = @max(shape1.rows, shape2.rows);
            } else {
                return MatrixError.Unbroadcastable;
            }
        }
        if (shape1.cols != shape2.cols) {
            if (shape1.cols == 1 or shape2.cols == 1) {
                broadcast_shape.cols = @max(shape1.cols, shape2.cols);
            } else {
                return MatrixError.Unbroadcastable;
            }
        }
        return broadcast_shape;
    }

    pub fn equal(shape1: MatrixShape, shape2: MatrixShape) bool {
        return (shape1.rows == shape2.rows and shape1.cols == shape2.cols);
    }
};
pub const MatrixStride = struct { row: usize, col: usize };
pub const MatrixSlice = struct { start: ?usize, stop: ?usize, step: ?usize };

pub const MatrixError = error{
    InvalidCoord,
    Unbroadcastable,
    InvalidShape,
};

/// A two dimentional array
pub fn Matrix(Element: type) type {
    return struct {
        const Self = @This();
        /// The data in the matrix
        data: []Element,
        /// The starting position of the matrix in `data`
        start: usize,
        /// The shape of the matrix (rows, columns)
        shape: MatrixShape,
        /// The stride of the matrix
        stride: MatrixStride,
        /// Whether the current matrix is a view into another
        is_view: bool,

        // **********************
        // *** Struct Methods ***
        // **********************

        /// Create a matrix of `shape`, does not initialize the memory, only allocates it
        pub fn init(allocator: std.mem.Allocator, shape: MatrixShape) !Self {
            const data = try allocator.alloc(Element, shape.rows * shape.cols);
            const stride = MatrixStride{ .row = shape.cols, .col = 1 };
            return Self{
                .data = data,
                .start = 0,
                .shape = shape,
                .stride = stride,
                .is_view = false,
            };
        }

        /// Create a matrix of `shape` filled with `value`
        pub fn initWithValue(allocator: std.mem.Allocator, shape: MatrixShape, value: Element) !Self {
            const matrix_size = shape.rows * shape.cols;
            var data = try allocator.alloc(Element, matrix_size);
            for (0..matrix_size) |idx| {
                data[idx] = value;
            }
            return Self{
                .data = data,
                .start = 0,
                .shape = shape,
                .stride = .{ .row = shape.cols, .col = 1 },
                .is_view = false,
            };
        }

        /// Initialize a Matrix with 0s
        pub fn initZeros(allocator: std.mem.Allocator, shape: MatrixShape) !Self {
            return initWithValue(allocator, shape, 0);
        }

        /// Initialize a Matrix with increasing sequence
        pub fn initArange(allocator: std.mem.Allocator, shape: MatrixShape, start: Element) !Self {
            const matrix_size = shape.rows * shape.cols;
            var data = try allocator.alloc(Element, matrix_size);
            var value = start;
            for (0..matrix_size) |idx| {
                data[idx] = value;
                value += 1;
            }
            return Self{
                .data = data,
                .start = 0,
                .shape = shape,
                .stride = .{ .row = shape.cols, .col = 1 },
                .is_view = false,
            };
        }

        /// Initialize a Matrix with 1s on the diagonal, and 0s everywhere else
        pub fn initIdent(allocator: std.mem.Allocator, shape: MatrixShape) !Self {
            var mat = try Self.initZeros(allocator, shape);
            for (0..(@min(mat.shape.rows, mat.shape.cols))) |idx| {
                (try mat.at(idx, idx)).* = 1;
            }
            return mat;
        }

        /// Create a matrix from a slice, with the specified `start` (from start of data), and `shape`
        ///
        /// Uses row-major ordering of the data
        pub fn initFromSlice(data: []Element, start: usize, shape: MatrixShape) !Self {
            if (start + shape.rows * shape.cols > data.len) {
                return MatrixError.InvalidShape;
            }
            return Self{
                .data = data,
                .start = start,
                .shape = shape,
                .stride = .{ .row = shape.cols, .col = 1 },
                .is_view = true,
            };
        }

        /// Check if two matrices are equal
        pub fn equal(a: Self, b: Self) bool {
            if (!MatrixShape.equal(a.shape, b.shape)) {
                return false;
            }
            for (0..a.shape.rows) |row| {
                for (0..a.shape.cols) |col| {
                    const a_val = a.get(row, col) catch {
                        unreachable;
                    };
                    const b_val = b.get(row, col) catch {
                        unreachable;
                    };
                    if (a_val != b_val) {
                        return false;
                    }
                }
            }
            return true;
        }

        /// Check if `actual` is approximately equal to `desired`
        ///
        /// Tests if `actual` is within `atol + rtol*abs(desired)` of `desired`
        pub fn approxEqual(actual: *const Self, desired: *const Self, rtol: Element, atol: Element) bool {
            if (!MatrixShape.equal(actual.shape, desired.shape)) {
                return false;
            }
            for (0..desired.shape.rows) |row| {
                for (0..desired.shape.cols) |col| {
                    const act = actual.get(row, col) catch unreachable;
                    const des = desired.get(row, col) catch unreachable;
                    // Not using abs for the subtraction to stop overflow issues with unsigned ints,
                    // though really this function shouldn't be used much for things that aren't floats
                    if ((if (act > des) act - des else des - act) > atol + rtol * @abs(des)) {
                        return false;
                    }
                }
            }
            return true;
        }

        // ************************
        // *** Instance Methods ***
        // ************************

        /// Return a transposed view of the matrix
        ///
        /// This returns a new object, not updating the original matrix,
        /// which shares the same data as the original
        pub fn transpose(matrix: *Self) Self {
            return Self{
                .data = matrix.data,
                .start = matrix.start,
                .shape = .{ .rows = matrix.shape.cols, .cols = matrix.shape.rows },
                .stride = .{ .row = matrix.stride.col, .col = matrix.stride.row },
                .is_view = true,
            };
        }

        /// Create a copy of the matrix
        pub fn copy(matrix: *Self, allocator: std.mem.Allocator) !Self {
            // Allocate the new data
            var data = try allocator.alloc(Element, matrix.shape.rows * matrix.shape.cols);
            var cur_position: usize = 0;
            // Move the data from the previous matrix (Can't memcopy since the data may not be together due to slicing)
            for (0..matrix.shape.rows) |row| {
                for (0..matrix.shape.cols) |col| {
                    data[cur_position] = try matrix.get(row, col);
                    cur_position += 1;
                }
            }
            return Self{
                .data = data,
                .start = 0,
                .shape = matrix.shape,
                .stride = .{ .row = matrix.shape.cols, .col = 1 },
                .is_view = false,
            };
        }

        /// Return the Element at the specified `row` and `col`
        pub fn get(matrix: *const Self, row: usize, col: usize) !Element {
            if ((row >= matrix.shape.rows) or (col >= matrix.shape.cols)) return MatrixError.InvalidCoord;
            return matrix.data[matrix.start + row * matrix.stride.row + col * matrix.stride.col];
        }

        /// Return a pointer to the Element at the specified `row` and `col`
        pub fn at(matrix: *Self, row: usize, col: usize) !*Element {
            if ((row >= matrix.shape.rows) or (col >= matrix.shape.cols)) return MatrixError.InvalidCoord;
            return &(matrix.data[matrix.start + row * matrix.stride.row + col * matrix.stride.col]);
        }

        /// Return a view into `matrix`
        pub fn slice(matrix: *Self, row_slice: MatrixSlice, col_slice: MatrixSlice) Self {
            // Extract data from slices, handling the nulls
            const row_start = row_slice.start orelse 0;
            const row_step = row_slice.stop orelse 1;
            const row_stop = row_slice.start orelse matrix.shape.cols;
            const col_start = col_slice.start orelse 0;
            const col_step = col_slice.stop orelse 1;
            const col_stop = col_slice.start orelse matrix.shape.cols;

            // Determine the values for the new matrix
            const new_start = matrix.start + matrix.stride.row * row_start + matrix.stride.col * col_start;
            const new_shape = MatrixShape{
                .rows = (row_stop - row_start) / row_step,
                .cols = (col_stop - col_start) / col_step,
            };
            const new_stride = MatrixStride{
                .row = matrix.stride.row * row_step,
                .col = matrix.stride.col * col_step,
            };

            return Self{
                .data = matrix.data,
                .start = new_start,
                .shape = new_shape,
                .stride = new_stride,
                .is_view = true,
            };
        }

        /// Free the memory associated with the matrix
        pub fn deinit(matrix: *Self, allocator: std.mem.Allocator) void {
            // Only free if not a view
            if (!matrix.is_view) {
                allocator.free(matrix.data);
            }
            matrix.* = undefined;
        }

        /// Get the size (in number of elements) of the Matrix
        pub fn size(matrix: *const Self) usize {
            return matrix.shape.rows * matrix.shape.cols;
        }

        /// Print the matrix to `writer`
        pub fn format(matrix: *const Self, writer: *std.Io.Writer) !void {
            try writer.writeAll("[");
            for (0..matrix.shape.rows) |row| {
                if (row > 0) {
                    try writer.writeAll(" ");
                }
                try writer.writeAll("[");
                for (0..matrix.shape.cols) |col| {
                    try writer.print("{any}", .{matrix.get(row, col)});
                    if (col < matrix.shape.cols - 1) {
                        try writer.writeAll(",");
                    }
                }
                try writer.writeAll("]");
                if (row < matrix.shape.rows - 1) {
                    try writer.writeAll(",");
                    try writer.writeAll("\n");
                }
            }
            try writer.writeAll("]");
        }

        /// Apply a binary function elementwise to two Matrices
        ///
        /// The matrices must be of the same shape, or be broadcastable into the same shape.
        pub fn binary(allocator: std.mem.Allocator, binary_fn: fn (Element, Element) Element, mat1: *const Self, mat2: *const Self) !Self {
            const broadcast_shape = try MatrixShape.broadcast(mat1.shape, mat2.shape);
            const mat1_view = try mat1.broadcastview(broadcast_shape);
            const mat2_view = try mat2.broadcastview(broadcast_shape);

            var result_mat = try Self.init(allocator, broadcast_shape);

            for (0..broadcast_shape.rows) |row| {
                for (0..broadcast_shape.cols) |col| {
                    (try result_mat.at(row, col)).* = binary_fn(try mat1_view.get(row, col), try mat2_view.get(row, col));
                }
            }
            return result_mat;
        }

        // PRIVATE METHODS

        /// Broadcast the matrix into a shape
        ///
        /// This sets the stride for row/col which had size 1, and differed from
        /// the broadcase_shape, to 0. If the broadcast_shape can't be achieved
        /// with this approach, `MatrixError.Unbroadcastable` is returned instead
        fn broadcastview(matrix: *const Self, broadcast_shape: MatrixShape) !Self {
            var broadcast_stride = MatrixStride{ .row = matrix.stride.row, .col = matrix.stride.col };
            if (matrix.shape.rows != broadcast_shape.rows) {
                if (matrix.shape.rows != 1) {
                    return MatrixError.Unbroadcastable;
                }
                broadcast_stride.row = 0;
            }
            if (matrix.shape.cols != broadcast_shape.cols) {
                if (matrix.shape.cols != 1) {
                    return MatrixError.Unbroadcastable;
                }
                broadcast_stride.col = 0;
            }
            return Self{
                .data = matrix.data,
                .start = matrix.start,
                .shape = broadcast_shape,
                .stride = broadcast_stride,
                .is_view = true,
            };
        }
    };
}

test "Create Matrix Alloc" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var matrix: Matrix(u16) = try Matrix(u16).init(test_allocator, .{
        .rows = 3,
        .cols = 4,
    });
    defer matrix.deinit(test_allocator);

    try std.testing.expectEqual(matrix.size(), 12);
}

test "Create Filled Matrix" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var matrix: Matrix(u16) = try Matrix(u16).initWithValue(test_allocator, .{
        .rows = 3,
        .cols = 4,
    }, 0);
    defer matrix.deinit(test_allocator);

    try std.testing.expectEqual(matrix.size(), 12);

    for (0..3) |row| {
        for (0..4) |col| {
            try std.testing.expectEqual(try matrix.get(row, col), 0);
        }
    }
}

test "Create Zeroed Matrix" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var matrix: Matrix(u16) = try Matrix(u16).initZeros(test_allocator, .{
        .rows = 3,
        .cols = 4,
    });
    defer matrix.deinit(test_allocator);

    try std.testing.expectEqual(matrix.size(), 12);

    for (0..3) |row| {
        for (0..4) |col| {
            try std.testing.expectEqual(try matrix.get(row, col), 0);
        }
    }
}
test "Create Identity Matrix" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var matrix: Matrix(u16) = try Matrix(u16).initIdent(test_allocator, .{
        .rows = 3,
        .cols = 4,
    });
    defer matrix.deinit(test_allocator);

    try std.testing.expectEqual(matrix.size(), 12);

    for (0..3) |row| {
        for (0..4) |col| {
            if (row != col) {
                try std.testing.expectEqual(try matrix.get(row, col), 0);
            } else {
                try std.testing.expectEqual(try matrix.get(row, col), 1);
            }
        }
    }
}

test "Create Sequential Matrix" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var matrix: Matrix(u16) = try Matrix(u16).initArange(test_allocator, .{
        .rows = 3,
        .cols = 4,
    }, 1);
    defer matrix.deinit(test_allocator);

    try std.testing.expectEqual(matrix.size(), 12);

    for (0..3) |row| {
        for (0..4) |col| {
            try std.testing.expectEqual(try matrix.get(row, col), 4 * row + col + 1);
        }
    }
}

test "Changing Elements" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var matrix: Matrix(u16) = try Matrix(u16).initWithValue(test_allocator, .{
        .rows = 3,
        .cols = 4,
    }, 0);
    defer matrix.deinit(test_allocator);

    try std.testing.expectEqual(matrix.size(), 12);

    for (0..3) |row| {
        for (0..4) |col| {
            (try matrix.at(row, col)).* = 1;
        }
    }

    for (0..3) |row| {
        for (0..4) |col| {
            try std.testing.expectEqual(try matrix.get(row, col), 1);
        }
    }

    (try matrix.at(0, 0)).* = 20;
    try std.testing.expectEqual(matrix.data[0], 20);

    (try matrix.at(0, 3)).* = 15;
    try std.testing.expectEqual(matrix.data[3], 15);

    (try matrix.at(1, 0)).* = 7;
    try std.testing.expectEqual(matrix.data[4], 7);

    (try matrix.at(2, 1)).* = 3;
    try std.testing.expectEqual(matrix.data[9], 3);
}

test "Bounds Checks" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var matrix: Matrix(u16) = try Matrix(u16).initWithValue(test_allocator, .{
        .rows = 3,
        .cols = 4,
    }, 0);
    defer matrix.deinit(test_allocator);

    try std.testing.expectEqual(matrix.size(), 12);

    try std.testing.expectError(MatrixError.InvalidCoord, matrix.get(0, 4));
    try std.testing.expectError(MatrixError.InvalidCoord, matrix.get(3, 0));

    try std.testing.expectError(MatrixError.InvalidCoord, matrix.at(0, 4));
    try std.testing.expectError(MatrixError.InvalidCoord, matrix.at(3, 0));
}

test "Copy Matrix" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var matrix: Matrix(u16) = try Matrix(u16).initWithValue(test_allocator, .{
        .rows = 3,
        .cols = 4,
    }, 0);
    defer matrix.deinit(test_allocator);

    var matrix_copy = try matrix.copy(test_allocator);
    defer matrix_copy.deinit(test_allocator);
    // Updating a copy shouldn't change the original
    (try matrix_copy.at(0, 0)).* = 1;
    try std.testing.expectEqual(try matrix.get(0, 0), 0);
    try std.testing.expectEqual(try matrix_copy.get(0, 0), 1);

    var matrix_view = matrix.slice(
        .{ .start = null, .stop = null, .step = null },
        .{ .start = null, .stop = null, .step = null },
    );
    // Updating matrix view should change the original
    (try matrix_view.at(1, 2)).* = 5;
    try std.testing.expectEqual(try matrix_view.get(1, 2), 5);
    try std.testing.expectEqual(try matrix.get(1, 2), 5);
}

test "Binary Function" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var matrix1: Matrix(u16) = try Matrix(u16).initWithValue(test_allocator, .{
        .rows = 3,
        .cols = 4,
    }, 1);
    defer matrix1.deinit(test_allocator);

    var matrix2: Matrix(u16) = try Matrix(u16).initWithValue(test_allocator, .{
        .rows = 1,
        .cols = 4,
    }, 0);
    defer matrix2.deinit(test_allocator);
    for (0..4) |idx| {
        (try matrix2.at(0, idx)).* = @truncate(idx + 1);
    }

    const mult_struct = struct {
        fn mult(a: u16, b: u16) u16 {
            return a * b;
        }
    };

    var res_matrix = try Matrix(u16).binary(test_allocator, mult_struct.mult, &matrix1, &matrix2);
    defer res_matrix.deinit(test_allocator);

    try std.testing.expectEqual(res_matrix.size(), 12);

    for (0..3) |row| {
        for (0..4) |col| {
            try std.testing.expectEqual(try res_matrix.get(row, col), col + 1);
        }
    }
}

test "Format Matrix" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var matrix: Matrix(u16) = try Matrix(u16).initWithValue(test_allocator, .{
        .rows = 3,
        .cols = 4,
    }, 0);
    defer matrix.deinit(test_allocator);

    const expectedFmt =
        \\[[0,0,0,0],
        \\ [0,0,0,0],
        \\ [0,0,0,0]]
    ;

    try std.testing.expectFmt(expectedFmt, "{f}", .{matrix});
}

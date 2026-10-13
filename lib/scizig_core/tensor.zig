const std = @import("std");

/// Indicate whether gradients should be tracked
pub var track_gradients: bool = true;

/// A slice along a single dimension
pub const Slice = struct {
    start: usize,
    step: usize,
    stop: usize,
};

/// A union representing possible binary operations on Tensors
fn BinaryOp(Element: type) type {
    return union(enum) {
        const Self = @This();

        /// Create a Tensor using the operation
        pub fn perform(self: Self, allocator: std.mem.Allocator, left: *Tensor(Element), right: *Tensor(Element)) Tensor(Element) {
            switch (self) {
                inline else => |case| return case.perform(allocator, left, right),
            }
        }
        /// Perform backpropogation for the binary operation
        pub fn backward(self: Self, current: *Tensor(Element), left: *Tensor(Element), right: *Tensor(Element)) void {
            switch (self) {
                inline else => |case| return case.backward(current, left, right),
            }
        }
    };
}

/// A union representing possible unary operations on Tensors
fn UnaryOp(Element: type) type {
    return union(enum) {
        const Self = @This();

        /// Create a Tensor using the operation
        pub fn perform(self: Self, allocator: std.mem.Allocator, parent: *Tensor(Element)) Tensor(Element) {
            switch (self) {
                inline else => |case| return case.perform(allocator, parent),
            }
        }

        /// Perform backpropogation for the unary operation
        pub fn backward(self: Self, current: *Tensor(Element), parent: *Tensor(Element)) void {
            switch (self) {
                inline else => |case| return case.backward(current, parent),
            }
        }
    };
}

/// A structure holding the binary operation, and the parents of the Tensor
fn Binary(Element: type) type {
    return struct {
        const Self = @This();
        /// The Binary operation which created the Tensor
        operation: BinaryOp(Element),
        /// The left operand of the operation which created the Tensor
        left_parent: *Tensor(Element),
        /// The right operand of the operation which created the Tensor
        right_parent: *Tensor(Element),

        /// Perform the Binary operation to create a new Tensor
        pub fn perform(bianry: Self, allocator: std.mem.Allocator) Tensor(Element) {
            bianry.operation.perform(allocator, bianry.left, bianry.right);
        }

        /// Perform backpropogation from the Tensor to its parents
        pub fn backward(binary: Self, current: *Tensor(Element)) void {
            binary.operation.backward(current, binary.left_parent, binary.right_parent);
        }
    };
}

/// A structure holding the unary operation, and the parent of the Tensor
fn Unary(Element: type) type {
    return struct {
        const Self = @This();

        /// The Unary operation which created the Tensor
        operation: UnaryOp(Element),
        /// The Tensor the operation was applied to
        parent: *Tensor(Element),

        /// Perform the Unary operation to create a new Tensor
        pub fn perform(unary: Self, allocator: std.mem.Allocator) Tensor(Element) {
            return unary.operation.perform(allocator, unary.parent);
        }

        /// Perform backpropogation from the Tensor to its parent
        pub fn backward(self: Self, current: *Tensor(Element)) void {
            self.operation.backward(current, self.parent);
        }
    };
}

/// Union representing possible operations performed to create a Tensor
fn Operation(Element: type) type {
    return union(enum) {
        const Self = @This();

        /// A binary operation with two operands
        binary: Binary(Element),
        /// A unary operation with a single operand
        unary: Unary(Element),
        /// The Tensor was not created by an operation (i.e. it comes from the
        /// Tensor creation methods)
        root,

        /// Perform the operation to create a new Tensor
        pub fn perform(self: Self, allocator: std.mem.Allocator) Tensor(Element) {
            return self.perform(allocator);
        }

        /// Perform backpropogation from the Tensor to its parent/parents
        pub fn backward(self: Self, tensor: *Tensor(Element)) void {
            switch (self) {
                inline else => |op| op.backward(tensor),
            }
        }
    };
}

/// An n-dimensional array of data, which can optionally track its gradient
/// for automatic differentiation
pub fn Tensor(Element: type) type {
    return struct {
        const Self = @This();

        /// The underlying elements of the Tensor
        data: []Element,
        /// The current gradient value, may be null if gradients are
        /// not being tracked
        grad: ?[]Element,
        /// The number of elements in data that must be traversed to inrease
        /// the index of the ith dimension by 1
        stride: []usize,
        /// The number of elements in each dimension
        shape: []usize,
        /// The operation that created the Tensor,
        /// null if gradients are not tracked
        operation: ?Operation(Element),
        /// Whether the Tensor owns the underlying data array
        is_view: bool,
        /// Mark whether a Tensor has been visited during backpropogation
        mark: bool,

        /// Initialize an empty Tensor
        pub fn init(allocator: std.mem.Allocator, shape: []const usize) !Self {
            var size: usize = 1;
            var dim_stride: usize = 1;

            var stride = try allocator.alloc(usize, shape.len);
            const tensor_shape = try allocator.dupe(usize, shape);

            var idx: usize = shape.len;
            while (idx > 0) {
                idx -= 1;
                stride[idx] = dim_stride;
                size *= shape[idx];
                dim_stride *= shape[idx];
            }

            const data = try allocator.alloc(Element, size);
            const grad = if (track_gradients) try allocator.alloc(Element, size) else null;
            const operation: ?Operation(Element) = if (track_gradients) Operation(Element).root else null;

            // If grad exists, ensure it is zeroed
            if (grad) |g| {
                for (0..g.len) |i| {
                    g[i] = 0;
                }
            }

            return Self{
                .data = data,
                .grad = grad,
                .shape = tensor_shape,
                .stride = stride,
                .is_view = false,
                .operation = operation,
                .mark = false,
            };
        }

        /// Initialize a Tensor with a specified value
        pub fn initWithValue(allocator: std.mem.Allocator, shape: []const usize, value: Element) !Self {
            var tensor = try Self.init(allocator, shape);
            for (0..tensor.data.len) |idx| {
                tensor.data[idx] = value;
            }
            return tensor;
        }

        /// Deinitialize the data a Tensor owns
        pub fn deinit(tensor: *Self, allocator: std.mem.Allocator) void {
            // Regardless of whether tensor is a view,
            // the shape and stride should be freed
            allocator.free(tensor.shape);
            allocator.free(tensor.stride);
            // If a Tensor is not a view free data,
            // and potentially grad
            if (!tensor.is_view) {
                allocator.free(tensor.data);
                if (tensor.grad) |grad| {
                    allocator.free(grad);
                }
            }
            // Invalidate pointer
            tensor.* = undefined;
        }

        /// Get a pointer to the element at position `where`
        pub fn at(tensor: *Self, where: []const usize) *Element {
            var position: usize = 0;
            for (where, tensor.stride) |coord, stride| {
                position += (coord * stride);
            }
            return &(tensor.data[position]);
        }

        /// Get the element at position `where`
        pub fn get(tensor: *Self, where: []const usize) Element {
            var position: usize = 0;
            for (where, tensor.stride) |coord, stride| {
                position += (coord * stride);
            }
            return tensor.data[position];
        }

        /// Perform backpropogation from the Tensor to its parent/parents
        pub fn backward(tensor: *Self) void {
            tensor.operation.backward(tensor);
        }
    };
}

test "Create Tensor Alloc" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var tensor = try Tensor(f32).init(test_allocator, &.{ 2, 3, 4 });
    defer tensor.deinit(test_allocator);

    // Check that the stride is as expected
    try std.testing.expectEqualSlices(usize, &.{ 12, 4, 1 }, tensor.stride);
    // Check that the shape is as expected
    try std.testing.expectEqualSlices(usize, &.{ 2, 3, 4 }, tensor.shape);
}

test "Change Tensor Value" {
    const tolerance = 1e-10;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var tensor = try Tensor(f32).initWithValue(test_allocator, &.{ 2, 3, 4 }, 0);
    defer tensor.deinit(test_allocator);

    tensor.at(&.{ 0, 0, 0 }).* = 10;
    tensor.at(&.{ 0, 0, 1 }).* = 100;
    tensor.at(&.{ 0, 1, 0 }).* = 75;
    tensor.at(&.{ 1, 0, 0 }).* = 55;
    tensor.at(&.{ 1, 2, 3 }).* = 15;

    try std.testing.expectApproxEqAbs(10, tensor.data[0], tolerance);
    try std.testing.expectApproxEqAbs(15, tensor.data[tensor.data.len - 1], tolerance);
    try std.testing.expectApproxEqAbs(100, tensor.data[1], tolerance);
    try std.testing.expectApproxEqAbs(75, tensor.data[4], tolerance);
    try std.testing.expectApproxEqAbs(55, tensor.data[12], tolerance);

    var tensor_2d = try Tensor(f32).initWithValue(test_allocator, &.{ 3, 4 }, 0);
    defer tensor_2d.deinit(test_allocator);

    tensor_2d.at(&.{ 0, 0 }).* = 9;
    tensor_2d.at(&.{ 0, 1 }).* = 7;
    tensor_2d.at(&.{ 1, 0 }).* = 5;

    try std.testing.expectApproxEqAbs(9, tensor_2d.data[0], tolerance);
    try std.testing.expectApproxEqAbs(7, tensor_2d.data[1], tolerance);
    try std.testing.expectApproxEqAbs(5, tensor_2d.data[4], tolerance);
}

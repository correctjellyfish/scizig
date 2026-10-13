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
        root: void,

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

        /// Perform backpropogation from the Tensor to its parent/parents
        pub fn backward(tensor: *Self) void {
            tensor.operation.backward(tensor);
        }
    };
}

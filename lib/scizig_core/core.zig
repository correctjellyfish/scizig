const std = @import("std");
// Core Datastructures
// Deque
pub const Deque = @import("deque.zig").Deque;

// Heaps
const heap = @import("heap.zig");
pub const Heap = heap.Heap;
pub const MaxHeap = heap.MaxHeap;
pub const MinHeap = heap.MinHeap;
pub const PriorityQueue = heap.PriorityQueue;
pub const MaxPriorityQueue = heap.MaxPriorityQueue;
pub const MinPriorityQueue = heap.MinPriorityQueue;

// Matrix
const matrix = @import("matrix.zig");
pub const Matrix = matrix.Matrix;
pub const MatrixSlice = matrix.MatrixSlice;
pub const MatrixError = matrix.MatrixError;

// Tensor
pub const tensor = @import("tensor.zig");
pub const Tensor = tensor.Tensor;
pub const TensorSlice = tensor.Slice;

test {
    std.testing.refAllDecls(@This());
}

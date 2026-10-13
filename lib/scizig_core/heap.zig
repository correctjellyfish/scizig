const std = @import("std");

/// A heap data structure built on an array.
///
/// The heap contains items of type `Item`, and compares them
/// using the `compare` function (which should return true if the
/// first item should be the parent of the second in the heap). Compare
/// could be `>` for a max heap, and `<` for a min heap.
pub fn Heap(Item: type, compare: fn (Item, Item) bool) type {
    return struct {
        const Self = @This();
        /// Current size of the heap
        size: usize,
        /// The current capacity of the underlying array
        capacity: usize,
        /// Underlying data slice
        data: []Item,

        /// Sort a slice
        ///
        /// The heap moves the root nodes to the end
        /// until there are no more nodes, so a MaxHeap will
        /// sort items ascending, and a MinHeap will sort items descending
        pub fn sort(data: []Item) void {
            var sort_heap = Self.heapify(data);
            var root: Item = undefined;
            while (sort_heap.size > 0) {
                root = sort_heap.extract();
                sort_heap.data[sort_heap.size] = root;
            }
        }

        /// Create an empty heap
        pub fn init(allocator: std.mem.Allocator) !Self {
            return initWithCapacity(allocator, 1);
        }

        /// Initialize heap with specified capacity
        pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: usize) !Self {
            const data = try allocator.alloc(Item, capacity);
            return Self{ .size = 0, .capacity = capacity, .data = data };
        }

        /// De-initialize a heap (free data)
        pub fn deinit(heap: *Self, allocator: std.mem.Allocator) void {
            // Free memory
            allocator.free(heap.data);
            heap.* = undefined;
        }

        /// Create a heap from a slice
        pub fn heapify(data: []Item) Self {
            var new_heap = Self{
                .size = data.len,
                .capacity = data.len,
                .data = data,
            };
            var start = Self.parent(new_heap.size - 1);
            while (start > 0) : (start -= 1) {
                new_heap.sink(start);
            }
            return new_heap;
        }

        /// Insert an item into the heap
        pub fn insert(heap: *Self, allocator: std.mem.Allocator, it: Item) !void {
            // Check if we need to allocate additional memory
            if (heap.size >= heap.capacity) {
                // Double capacity to amortize
                heap.capacity *= 2;
                heap.data = try allocator.realloc(heap.data, heap.capacity);
            }
            // Insert the new element, and swim it up till
            // heap property is established
            heap.size += 1;
            heap.data[heap.size - 1] = it;
            heap.swim(heap.size - 1);
        }

        /// Remove (and return) the top element of the heap
        pub fn extract(heap: *Self) Item {
            // Get the root element
            const root = heap.data[0];

            // Move the last element to the start
            heap.data[0] = heap.data[heap.size - 1];
            // Size is reduced
            heap.size -= 1;
            // Reestablish heap property
            heap.sink(0);

            return root;
        }

        /// Make the heap property hold again after an item
        /// has potentially had its value change
        ///
        /// Used mainly for allowing updates in a priority
        /// queue
        pub fn update(heap: *Self, index: usize) void {
            // Check if need to swim
            if (heap.comp(Self.parent(index), index)) {
                heap.swim(index);
            } else {
                heap.sink(index);
            }
        }

        // ########################
        // ### Helper Functions ###
        // ########################

        /// Move an item down the heap to its proper place
        fn sink(heap: *Self, root: usize) void {
            // If root violates the heap property, move it down the heap
            var r = root;
            while (Self.childLeft(r) < heap.size) {
                var child = Self.childLeft(r);

                // First check which child would be exchanged
                if (child + 1 < heap.data.len and heap.comp(child + 1, child)) {
                    child += 1;
                }

                // Then check if r should actually exchange
                if (heap.comp(r, child)) {
                    // r is 'larger' (or smaller) than both children, stop sinking
                    return;
                }
                // Swap r and the 'largest' child
                heap.swap(r, child);
                r = child;
            }
        }

        /// Move an item up the heap to its proper place
        fn swim(heap: *Self, child: usize) void {
            var i = child;
            while (i > 0 and heap.comp(i, Self.parent(i))) {
                heap.swap(Self.parent(i), i);
                i = Self.parent(i);
            }
        }

        /// Compare items at position `i` and `j`
        fn comp(heap: *Self, i: usize, j: usize) bool {
            return compare(heap.data[i], heap.data[j]);
        }

        /// Swap items at position `i` and `j`
        fn swap(heap: *Self, i: usize, j: usize) void {
            const tmp = heap.data[i];
            heap.data[i] = heap.data[j];
            heap.data[j] = tmp;
        }

        // Some functions to make the code clearer
        inline fn childLeft(i: usize) usize {
            return 2 * i + 1;
        }

        inline fn childRight(i: usize) usize {
            return 2 * i + 2;
        }

        inline fn parent(i: usize) usize {
            return (i - 1) / 2;
        }
    };
}

/// A Max Heap, where nodes are always greater
/// than their children
pub fn MaxHeap(Item: type) type {
    const m = struct {
        fn max(a: Item, b: Item) bool {
            return a > b;
        }
    };
    return Heap(Item, m.max);
}
/// A Min Heap, where nodes are always less
/// than their children
pub fn MinHeap(Item: type) type {
    const m = struct {
        fn min(a: Item, b: Item) bool {
            return a > b;
        }
    };
    return Heap(Item, m.min);
}

pub fn PriorityQueue(Item: type, Priority: type, compare: fn (Priority, Priority) bool) type {
    const Element = struct {
        item: Item,
        priority: Priority,
    };

    const PriorityCompare = struct {
        fn priority_compare(a: Element, b: Element) bool {
            return compare(a.priority, b.priority);
        }
    };

    const PriorityHeap = Heap(Element, PriorityCompare.priority_compare);

    return struct {
        const Self = @This();
        heap: PriorityHeap,

        /// Initialize an empty priority queue
        pub fn init(allocator: std.mem.Allocator) !Self {
            const heap = try PriorityHeap.init(allocator);
            return Self{ .heap = heap };
        }

        /// Initialize queue with specified capacity
        pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: usize) !Self {
            const heap = try PriorityHeap.initWithCapacity(allocator, capacity);
            return Self{ .heap = heap };
        }

        /// De-initialize an empty priority queue
        pub fn deinit(pqueue: *Self, allocator: std.mem.Allocator) !void {
            pqueue.heap.deinit(allocator);
            pqueue.* = undefined;
        }

        /// Insert an `item` with a `priority` into the queue
        pub fn insert(pqueue: *Self, allocator: std.mem.Allocator, item: Item, priority: Priority) !void {
            pqueue.heap.insert(allocator, Element{ .item = item, .priority = priority });
        }

        /// Return the front item of the queue
        pub fn pop(pqueue: *Self) Item {
            return pqueue.heap.extract().item;
        }

        /// Update the priority for an item
        pub fn updatePriority(pqueue: *Self, item: Item, new_priority: Priority) void {
            var index = 0;
            while (index < pqueue.heap.size) : (index += 1) {
                if (pqueue.heap.data[index] == item) {
                    pqueue.heap.data[index].priority = new_priority;
                    break;
                }
            }
            pqueue.heap.update(index);
        }
    };
}

/// A priority queue which keeps the maximum item
/// at the front of the queue
pub fn MaxPriorityQueue(Item: type, Priority: type) type {
    const Max = struct {
        fn max(a: Priority, b: Priority) bool {
            return a > b;
        }
    };

    return PriorityQueue(Item, Priority, Max.max);
}
/// A priority queue which keeps the minimum item
/// at the front of the queue
pub fn MinPriorityQueue(Item: type, Priority: type) type {
    const Min = struct {
        fn min(a: Priority, b: Priority) bool {
            return a < b;
        }
    };

    return PriorityQueue(Item, Priority, Min.min);
}

test "Create Empty Heap" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var heap: MaxHeap(u32) = try MaxHeap(u32).init(test_allocator);
    defer heap.deinit(test_allocator);
}

test "Max Heap Property" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var heap: MaxHeap(u32) = try MaxHeap(u32).init(test_allocator);
    defer heap.deinit(test_allocator);

    try heap.insert(test_allocator, 5);
    try heap.insert(test_allocator, 9);
    try heap.insert(test_allocator, 2);
    try heap.insert(test_allocator, 15);
    try heap.insert(test_allocator, 1);
    try heap.insert(test_allocator, 3);

    try std.testing.expectEqual(heap.extract(), 15);
    try std.testing.expectEqual(heap.extract(), 9);
    try std.testing.expectEqual(heap.extract(), 5);
    try std.testing.expectEqual(heap.extract(), 3);
    try std.testing.expectEqual(heap.extract(), 2);
    try std.testing.expectEqual(heap.extract(), 1);
}

test "Sort" {
    var to_sort = [_]u32{ 9, 2, 6, 1, 7, 3, 1 };
    MaxHeap(u32).sort(&to_sort);

    try std.testing.expectEqualSlices(u32, &to_sort, &[_]u32{ 1, 1, 2, 3, 6, 7, 9 });
}

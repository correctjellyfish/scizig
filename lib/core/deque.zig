const std = @import("std");

/// Node in the Deque
pub fn DequeNode(T: type) type {
    return struct {
        const Self = @This();
        data: T,
        next: ?*Self,
        prev: ?*Self,

        pub fn format(self: *const Self, writer: *std.Io.Writer) !void {
            if (self.*.prev) |_| {
                try writer.print("<-", .{});
            }
            try writer.print("[{any}]", .{self.data});
            if (self.*.next) |_| {
                try writer.print("->", .{});
            }
        }
    };
}

/// A double-ended queue implemented as a double linked list
pub fn Deque(T: type) type {
    const Node = DequeNode(T);

    return struct {
        const Self = @This();
        /// The current head of the queue
        head: ?*Node,
        /// The current tail of the queue
        tail: ?*Node,
        /// Current element during iteration
        current: ?*Node,
        /// The allocator used to allocate items
        allocator: std.mem.Allocator,

        /// Create an empty Deque which will use the allocator
        /// to store the items
        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .head = null,
                .tail = null,
                .allocator = allocator,
                .current = null,
            };
        }

        /// Free the items from the queue,
        /// can skip if using an arena allocator and
        /// just call deinit on the allocator
        pub fn deinit(self: *Self) void {
            var current_item: ?*Node = self.*.head;
            var next_item: ?*Node = null;
            while (current_item) |cur_val| {
                next_item = cur_val.*.next;
                self.*.allocator.destroy(current_item.?);
                current_item = next_item;
            }
            self.* = undefined;
        }

        /// Add an item to the end of the Deque
        pub fn push_tail(self: *Self, item: T) !void {
            const new_tail = try self.allocator.create(Node);
            new_tail.* = Node{
                .data = item,
                .next = null,
                .prev = null,
            };
            if (self.*.tail) |prev_tail| {
                prev_tail.*.next = new_tail;
                new_tail.*.prev = prev_tail;
                self.*.tail = new_tail;
            } else {
                self.*.head = new_tail;
                self.*.tail = new_tail;
            }
        }

        /// Add an item to the head of the Deque
        pub fn push_head(self: *Self, item: T) !void {
            const new_head = try self.allocator.create(Node);
            new_head.* = Node{
                .data = item,
                .next = null,
                .prev = null,
            };
            if (self.*.head) |prev_head| {
                prev_head.*.prev = new_head;
                new_head.*.next = prev_head;
                self.*.head = new_head;
            } else {
                self.*.head = new_head;
                self.*.tail = new_head;
            }
        }

        /// Pop the item from the tail of the queue
        pub fn pop_tail(self: *Self) ?T {
            if (self.*.tail) |tail| {
                // Get the data so it can be returned
                const item: T = tail.*.data;
                const new_tail = tail.prev;
                if (new_tail) |nt| {
                    nt.next = null;
                }
                self.*.tail = new_tail;
                // Check if the tail has met the head
                // And free if necessary
                if (self.*.head) |head| {
                    if (tail == head) {
                        self.*.head = null;
                        self.*.allocator.destroy(head);
                    } else {
                        // Free the old tail
                        self.*.allocator.destroy(tail);
                    }
                }
                return item;
            }
            return null;
        }

        /// Pop the item from the head of the queue
        pub fn pop_head(self: *Self) ?T {
            if (self.*.head) |head| {
                // Get the data so it can be returned
                const item: T = head.*.data;
                const new_head = head.next;
                if (new_head) |nh| {
                    nh.prev = null;
                }
                self.*.head = new_head;
                // Check if the head has met the head
                // And free if necessary
                if (self.*.tail) |tail| {
                    if (head == tail) {
                        self.*.tail = null;
                        self.*.allocator.destroy(tail);
                    } else {
                        // Free the old head
                        self.*.allocator.destroy(head);
                    }
                }
                return item;
            }
            return null;
        }

        fn seek_head(self: *Self) void {
            self.current = self.head;
        }

        fn next(self: *Self) ?*Node {
            const current = self.current;
            if (current) |c| {
                self.*.current = c.next;
                return c;
            }
            return current;
        }

        pub fn format(self: *const Self, writer: *std.Io.Writer) !void {
            var current_node = self.*.head;
            while (current_node) |cn| {
                try writer.print("{f}", .{cn.*});
                current_node = cn.*.next;
            }
        }
    };
}

test "Create Deque" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var deque: Deque(u32) = try Deque(u32).init(test_allocator);
    deque.deinit();
}

test "Push/Pop Tail" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var deque: Deque(u32) = try Deque(u32).init(test_allocator);
    defer deque.deinit();
    // Push
    try deque.push_tail(10);
    try deque.push_tail(20);
    try deque.push_tail(30);

    // Pop
    try std.testing.expectEqual(30, deque.pop_tail().?);
    try std.testing.expectEqual(20, deque.pop_tail().?);
    try std.testing.expectEqual(10, deque.pop_tail().?);
}

test "Push/Pop Head" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const test_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    var deque: Deque(u32) = try Deque(u32).init(test_allocator);
    defer deque.deinit();
    // Push
    try deque.push_head(10);
    try deque.push_head(20);
    try deque.push_head(30);

    // Pop
    try std.testing.expectEqual(30, deque.pop_head().?);
    try std.testing.expectEqual(20, deque.pop_head().?);
    try std.testing.expectEqual(10, deque.pop_head().?);
}

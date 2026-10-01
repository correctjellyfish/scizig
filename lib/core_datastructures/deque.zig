fn Deque(T: type) type {
    return struct {
        const Node = struct {
            data: T,
            next: ?Node,
            prev: ?Node,
        };
    };
}

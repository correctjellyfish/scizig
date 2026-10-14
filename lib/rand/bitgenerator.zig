/// An interface defining the RNG
pub fn BitGenerator(T: type) type {
    return struct {
        const Self = @This();
        /// Pointer to the struct implementing the interface
        ptr: *anyopaque,
        // Insert functions here
        /// Get the next number from the RNG
        next: *const fn (ptr: *anyopaque) T,
        /// Set the seed of the RNG
        setSeed: *const fn (ptr: *anyopaque) void,

        /// Create the RNG interface
        fn init(ptr: anytype) Self {
            const InterfaceType = @TypeOf(ptr);
            const ptr_info = @typeInfo(InterfaceType);

            const gen = struct {
                pub fn next(pointer: *anyopaque) T {
                    const rng: T = @ptrCast(@alignCast(pointer));
                    return ptr_info.pointer.child.next(rng);
                }
                pub fn setSeed(pointer: *anyopaque) void {
                    const rng: T = @ptrCast(@alignCast(pointer));
                    return ptr_info.pointer.child.setSeed(rng);
                }
            };

            return .{
                .ptr = ptr,
                // Insert functions here
                .next = gen.next,
                .setSeed = gen.setSeed,
            };
        }
    };
}

pub fn rotate_left(comptime T: type, x: T, k: usize) T {
    const size = switch (@typeInfo(T)) {
        .Int => |info| info.bits,
        else => @compileError("Rotate left not implemented for non-integers"),
    };
    return (x << k) | (x >> (size - k));
}

// Example
// const Writer = struct {
//   // These two fields are the same as before
//   ptr: *anyopaque,
//   writeAllFn: *const fn (ptr: *anyopaque, data: []const u8) anyerror!void,
//
//   // This is new
//   fn init(ptr: anytype) Writer {
//     const T = @TypeOf(ptr);
//     const ptr_info = @typeInfo(T);
//
//     const gen = struct {
//       pub fn writeAll(pointer: *anyopaque, data: []const u8) anyerror!void {
//         const self: T = @ptrCast(@alignCast(pointer));
//         return ptr_info.@"pointer".child.writeAll(self, data);
//       }
//     };
//
//
//     return .{
//       .ptr = ptr,
//       .writeAllFn = gen.writeAll,
//     };
//   }
//
//   // This is the same as before
//   pub fn writeAll(self: Writer, data: []const u8) !void {
//     return self.writeAllFn(self.ptr, data);
//   }
// };

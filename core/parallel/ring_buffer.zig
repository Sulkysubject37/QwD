const std = @import("std");

/// A simple, thread-safe, bounded multiple-producer multiple-consumer ring buffer.
/// For Phase R, since we have 1 producer and N consumers, this is sufficient.
pub fn RingBuffer(comptime T: type) type {
    return struct {
        buffer: []T,
        head: std.atomic.Value(usize),
        tail: std.atomic.Value(usize),
        capacity: usize,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !*@This() {
            // Need power of 2 for fast modulo
            const actual_capacity = std.math.ceilPowerOfTwo(usize, capacity) catch return error.CapacityTooLarge;
            
            var self = try allocator.create(@This());
            self.buffer = try allocator.alloc(T, actual_capacity);
            self.head = std.atomic.Value(usize).init(0);
            self.tail = std.atomic.Value(usize).init(0);
            self.capacity = actual_capacity;
            self.allocator = allocator;
            return self;
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.buffer);
            self.allocator.destroy(self);
        }

        // Single producer enqueue
        pub fn push(self: *@This(), item: T) bool {
            const h = self.head.load(.acquire);
            const t = self.tail.load(.acquire);
            if (h -% t == self.capacity) return false; // Full
            
            self.buffer[h & (self.capacity - 1)] = item;
            self.head.store(h +% 1, .release);
            return true;
        }

        // Multiple consumer dequeue
        pub fn pop(self: *@This()) ?T {
            while (true) {
                const t = self.tail.load(.acquire);
                const h = self.head.load(.acquire);
                if (h == t) return null; // Empty

                const item = self.buffer[t & (self.capacity - 1)];
                
                // Try to claim the item
                if (self.tail.cmpxchgWeak(t, t +% 1, .release, .acquire) == null) {
                    return item;
                }
            }
        }
    };
}

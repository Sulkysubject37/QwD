const std = @import("std");
const blocking_sync = @import("blocking_sync");

/// A thread-safe, genuinely blocking, bounded ring buffer for Job dispatch.
pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        
        buffer: []T,
        head: usize = 0,
        tail: usize = 0,
        capacity: usize,
        allocator: std.mem.Allocator,
        is_shutdown: bool = false,
        
        // NEW: Condition Variable Sync
        mutex: blocking_sync.Mutex,
        cond_empty: blocking_sync.Condition, // Wait for space
        cond_full: blocking_sync.Condition,  // Wait for data

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !*Self {
            const actual_capacity = try std.math.ceilPowerOfTwo(usize, capacity);
            const self = try allocator.create(Self);
            self.* = .{
                .buffer = try allocator.alloc(T, actual_capacity),
                .capacity = actual_capacity,
                .allocator = allocator,
                .mutex = blocking_sync.Mutex.init(),
                .cond_empty = blocking_sync.Condition.init(),
                .cond_full = blocking_sync.Condition.init(),
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
            self.mutex.deinit();
            self.cond_empty.deinit();
            self.cond_full.deinit();
            self.allocator.destroy(self);
        }

        pub fn shutdown(self: *Self) void {
            self.mutex.lock();
            self.is_shutdown = true;
            self.mutex.unlock();
            self.cond_full.broadcast();
            self.cond_empty.broadcast();
        }

        pub fn tryPush(self: *Self, item: T) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.is_shutdown) return false;
            if (self.head -% self.tail == self.capacity) return false;

            self.buffer[self.head & (self.capacity - 1)] = item;
            self.head += 1;
            self.cond_full.signal();
            return true;
        }

        pub fn tryPop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.head == self.tail) return null;

            const item = self.buffer[self.tail & (self.capacity - 1)];
            self.tail += 1;
            self.cond_empty.signal();
            return item;
        }

        pub fn push(self: *Self, item: T) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.head -% self.tail == self.capacity) {
                if (self.is_shutdown) return false;
                self.cond_empty.wait(&self.mutex);
            }

            self.buffer[self.head & (self.capacity - 1)] = item;
            self.head += 1;
            self.cond_full.signal();
            return true;
        }

        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.head == self.tail) {
                if (self.is_shutdown) return null;
                self.cond_full.wait(&self.mutex);
            }

            const item = self.buffer[self.tail & (self.capacity - 1)];
            self.tail += 1;
            self.cond_empty.signal();
            return item;
        }
    };
}

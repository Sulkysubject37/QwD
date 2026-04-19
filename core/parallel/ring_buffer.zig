const std = @import("std");

/// A thread-safe, blocking, bounded ring buffer for Job dispatch with race-free shutdown.
pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        
        buffer: []T,
        head: std.atomic.Value(usize),
        tail: std.atomic.Value(usize),
        capacity: usize,
        allocator: std.mem.Allocator,
        is_shutdown: std.atomic.Value(bool),
        
        // Semaphores for blocking (std.Io.Semaphore in 0.16.0-dev)
        empty_sem: std.Io.Semaphore,
        full_sem: std.Io.Semaphore,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !*Self {
            const actual_capacity = try std.math.ceilPowerOfTwo(usize, capacity);
            
            const self = try allocator.create(Self);
            self.* = .{
                .buffer = try allocator.alloc(T, actual_capacity),
                .head = std.atomic.Value(usize).init(0),
                .tail = std.atomic.Value(usize).init(0),
                .capacity = actual_capacity,
                .allocator = allocator,
                .is_shutdown = std.atomic.Value(bool).init(false),
                .empty_sem = .{ .permits = 0 },
                .full_sem = .{ .permits = actual_capacity },
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
            self.allocator.destroy(self);
        }

        pub fn shutdown(self: *Self, io: std.Io, num_workers: usize) void {
            self.is_shutdown.store(true, .release);
            // Wake up all workers
            for (0..num_workers) |_| {
                self.empty_sem.post(io);
            }
        }

        pub fn count(self: *const Self) usize {
            const h = self.head.load(.acquire);
            const t = self.tail.load(.acquire);
            return h -% t;
        }

        pub fn write(self: *Self, items: []const T) usize {
            var n: usize = 0;
            while (n < items.len) {
                const h = self.head.load(.acquire);
                const t = self.tail.load(.acquire);
                if (h -% t == self.capacity) break;
                self.buffer[h & (self.capacity - 1)] = items[n];
                self.head.store(h +% 1, .release);
                n += 1;
            }
            return n;
        }

        pub fn read(self: *Self, dest: []T) usize {
            var n: usize = 0;
            while (n < dest.len) {
                const t = self.tail.load(.acquire);
                const h = self.head.load(.acquire);
                if (h == t) break;
                dest[n] = self.buffer[t & (self.capacity - 1)];
                self.tail.store(t +% 1, .release);
                n += 1;
            }
            return n;
        }

        pub fn push(self: *Self, io: std.Io, item: T) bool {
            if (self.is_shutdown.load(.acquire)) return false;
            self.full_sem.waitUncancelable(io);
            
            const h = self.head.load(.monotonic);
            self.buffer[h & (self.capacity - 1)] = item;
            self.head.store(h +% 1, .release);
            
            self.empty_sem.post(io);
            return true;
        }

        pub fn pop(self: *Self, io: std.Io) ?T {
            self.empty_sem.waitUncancelable(io);
            
            // Race-free slot claim loop
            while (true) {
                const t = self.tail.load(.acquire);
                const h = self.head.load(.acquire);
                
                // If buffer is empty and shutdown is active, this was a shutdown permit.
                if (h == t and self.is_shutdown.load(.acquire)) return null;
                
                // If buffer is empty but not shutdown, another thread took the item we were alerted for.
                // This shouldn't happen with correct semaphore counts, but we must be robust.
                if (h == t) {
                    std.Thread.yield() catch {};
                    continue;
                }

                // Claim the slot
                if (self.tail.cmpxchgWeak(t, t +% 1, .release, .acquire)) |_| {
                    std.Thread.yield() catch {};
                    continue;
                }
                
                const item = self.buffer[t & (self.capacity - 1)];
                self.full_sem.post(io);
                return item;
            }
        }
    };
}

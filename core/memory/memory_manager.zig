const std = @import("std");

pub const MemoryManager = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(child_allocator: std.mem.Allocator) MemoryManager {
        return MemoryManager{
            .arena = std.heap.ArenaAllocator.init(child_allocator),
        };
    }

    pub fn deinit(self: *MemoryManager) void {
        self.arena.deinit();
    }

    pub fn allocator(self: *MemoryManager) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn createBuffer(self: *MemoryManager, size: usize) ![]u8 {
        return self.arena.allocator().alloc(u8, size);
    }

    /// Preallocate a standard hash map, bypassing dynamic resizing overhead during streaming
    pub fn preallocateStringHashMap(self: *MemoryManager, comptime V: type, capacity: u32) !std.StringHashMap(V) {
        var map = std.StringHashMap(V).init(self.allocator());
        try map.ensureTotalCapacity(capacity);
        return map;
    }
};

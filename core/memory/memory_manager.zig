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
    
    // Provide additional utilities for bounded pools or buffer reuse
    pub fn createBuffer(self: *MemoryManager, size: usize) ![]u8 {
        return self.arena.allocator().alloc(u8, size);
    }
};

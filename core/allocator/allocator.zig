const std = @import("std");

/// A wrapper around Zig allocators to centralize memory management.
pub const QwDAllocator = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(child_allocator: std.mem.Allocator) QwDAllocator {
        return QwDAllocator{
            .arena = std.heap.ArenaAllocator.init(child_allocator),
        };
    }

    pub fn deinit(self: *QwDAllocator) void {
        self.arena.deinit();
    }

    pub fn allocator(self: *QwDAllocator) std.mem.Allocator {
        return self.arena.allocator();
    }
};

/// Helper to create a new ArenaAllocator wrapper.
pub fn createArena(child_allocator: std.mem.Allocator) QwDAllocator {
    return QwDAllocator.init(child_allocator);
}

/// Helper to destroy an ArenaAllocator.
pub fn destroyArena(arena: *QwDAllocator) void {
    arena.deinit();
}

test "QwDAllocator test" {
    
    var qwd_alloc = createArena(allocator);
    defer destroyArena(&qwd_alloc);

    const arena_allocator = qwd_alloc.allocator();
    const ptr = try arena_allocator.alloc(u8, 10);
    try std.testing.expect(ptr.len == 10);
}

const std = @import("std");

pub const GlobalAllocator = struct {
    parent_allocator: std.mem.Allocator,
    max_bytes: usize,
    allocated_bytes: std.atomic.Value(usize),

    pub fn init(parent: std.mem.Allocator, max_bytes: usize) GlobalAllocator {
        return .{
            .parent_allocator = parent,
            .max_bytes = max_bytes,
            .allocated_bytes = std.atomic.Value(usize).init(0),
        };
    }

    pub fn allocator(self: *GlobalAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *GlobalAllocator = @ptrCast(@alignCast(ctx));
        
        const current = self.allocated_bytes.load(.acquire);
        if (current + len > self.max_bytes) return null;

        if (self.parent_allocator.rawAlloc(len, ptr_align, ret_addr)) |ptr| {
            _ = self.allocated_bytes.fetchAdd(len, .release);
            return ptr;
        }
        return null;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *GlobalAllocator = @ptrCast(@alignCast(ctx));
        if (new_len > buf.len) {
            const diff = new_len - buf.len;
            const current = self.allocated_bytes.load(.acquire);
            if (current + diff > self.max_bytes) return false;
            
            if (self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr)) {
                _ = self.allocated_bytes.fetchAdd(diff, .release);
                return true;
            }
        } else {
            const diff = buf.len - new_len;
            if (self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr)) {
                _ = self.allocated_bytes.fetchSub(diff, .release);
                return true;
            }
        }
        return false;
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *GlobalAllocator = @ptrCast(@alignCast(ctx));
        
        if (new_len > buf.len) {
            const diff = new_len - buf.len;
            const current = self.allocated_bytes.load(.acquire);
            if (current + diff > self.max_bytes) return null;
        }

        if (self.parent_allocator.rawRemap(buf, buf_align, new_len, ret_addr)) |ptr| {
            if (new_len > buf.len) {
                _ = self.allocated_bytes.fetchAdd(new_len - buf.len, .release);
            } else {
                _ = self.allocated_bytes.fetchSub(buf.len - new_len, .release);
            }
            return ptr;
        }
        return null;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *GlobalAllocator = @ptrCast(@alignCast(ctx));
        const bytes = buf.len;
        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
        _ = self.allocated_bytes.fetchSub(bytes, .release);
    }
};

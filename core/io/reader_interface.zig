const std = @import("std");

/// Agnostic Reader Interface for Ubiquitous Genomics
pub const Reader = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        read: *const fn (ctx: *anyopaque, dest: []u8) anyerror!usize,
        deinit: *const fn (ctx: *anyopaque) void,
    };

    pub fn read(self: Reader, dest: []u8) !usize {
        return self.vtable.read(self.ptr, dest);
    }

    pub fn readAtLeast(self: Reader, dest: []u8, min: usize) !usize {
        var read_count: usize = 0;
        while (read_count < min) {
            const amt = try self.read(dest[read_count..]);
            if (amt == 0) return read_count;
            read_count += amt;
        }
        return read_count;
    }

    pub fn deinit(self: Reader) void {
        self.vtable.deinit(self.ptr);
    }

    pub const IoReaderContext = struct {
        file: std.Io.File,
        io: std.Io,
    };

    /// Sync wrapper for std.Io.File
    pub fn fromIoFile(ctx: *const IoReaderContext) Reader {
        const Gen = struct {
            fn read(ptr: *anyopaque, dest: []u8) !usize {
                const self: *const IoReaderContext = @ptrCast(@alignCast(ptr));
                const bufs = [_][]u8{dest};
                return self.file.readStreaming(self.io, &bufs);
            }
            fn deinit(_: *anyopaque) void {}
        };
        return .{
            .ptr = @constCast(ctx),
            .vtable = &.{
                .read = Gen.read,
                .deinit = Gen.deinit,
            },
        };
    }
    
    /// Sync wrapper for standard std.fs.File
    pub fn fromFile(file: *const std.fs.File) Reader {
        const Gen = struct {
            fn read(ptr: *anyopaque, dest: []u8) !usize {
                const f: *const std.fs.File = @ptrCast(@alignCast(ptr));
                return f.read(dest);
            }
            fn deinit(_: *anyopaque) void {}
        };
        return .{
            .ptr = @constCast(file),
            .vtable = &.{
                .read = Gen.read,
                .deinit = Gen.deinit,
            },
        };
    }
    
    pub const MemoryReaderContext = struct {
        buffer: []const u8,
        pos: usize,
    };

    /// Sync wrapper for memory buffer
    pub fn fromMemory(ctx: *MemoryReaderContext) Reader {
        const Gen = struct {
            fn read(ptr: *anyopaque, dest: []u8) !usize {
                var self: *MemoryReaderContext = @ptrCast(@alignCast(ptr));
                if (self.pos >= self.buffer.len) return 0;
                const amt = @min(dest.len, self.buffer.len - self.pos);
                @memcpy(dest[0..amt], self.buffer[self.pos .. self.pos + amt]);
                self.pos += amt;
                return amt;
            }
            fn deinit(_: *anyopaque) void {}
        };
        return .{
            .ptr = ctx,
            .vtable = &.{
                .read = Gen.read,
                .deinit = Gen.deinit,
            },
        };
    }
};

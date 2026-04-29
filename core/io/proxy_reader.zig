const std = @import("std");
const ordered_slots = @import("ordered_slots");
const reader_interface = @import("reader_interface");

pub const ProxyReader = struct {
    slots: *ordered_slots.SlotManager,
    current_slot_pos: usize = 0,
    io: std.Io,
    eof: bool = false,

    pub fn init(slots: *ordered_slots.SlotManager, io: std.Io) ProxyReader {
        return .{
            .slots = slots,
            .io = io,
        };
    }

    pub fn read(self: *ProxyReader, dest: []u8) !usize {
        if (self.eof) return 0;
        
        while (true) {
            const slot = self.slots.acquireSlotForRead() orelse {
                self.eof = true;
                return 0;
            };

            const data = slot.decompressed_data[0..slot.decompressed_len];
            const available = data.len - self.current_slot_pos;
            
            if (available == 0) {
                // Done with this slot
                self.slots.commitRead();
                self.current_slot_pos = 0;
                continue;
            }

            const to_copy = @min(available, dest.len);
            @memcpy(dest[0..to_copy], data[self.current_slot_pos .. self.current_slot_pos + to_copy]);
            self.current_slot_pos += to_copy;
            return to_copy;
        }
    }

    pub fn reader(self: *ProxyReader) reader_interface.Reader {
        const Gen = struct {
            fn read(ptr: *anyopaque, dest: []u8) !usize {
                const s: *ProxyReader = @ptrCast(@alignCast(ptr));
                return s.read(dest);
            }
            fn deinit(_: *anyopaque) void {}
        };
        return .{
            .ptr = self,
            .vtable = &.{
                .read = Gen.read,
                .deinit = Gen.deinit,
            },
        };
    }
};

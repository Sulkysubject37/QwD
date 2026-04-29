const std = @import("std");
const blocking_sync = @import("blocking_sync");

pub const SlotStatus = enum(u32) {
    empty = 0,
    compressed = 1,
    decompressing = 2,
    ready = 3,
};

pub const Slot = struct {
    compressed_data: ?[]u8 = null,
    decompressed_data: []u8,
    decompressed_len: usize = 0,
    status: std.atomic.Value(u32) = std.atomic.Value(u32).init(@intFromEnum(SlotStatus.empty)),
    
    pub fn init(allocator: std.mem.Allocator, decomp_size: usize) !Slot {
        return Slot{
            .decompressed_data = try allocator.alloc(u8, decomp_size),
        };
    }

    pub fn deinit(self: *Slot, allocator: std.mem.Allocator) void {
        allocator.free(self.decompressed_data);
        if (self.compressed_data) |d| allocator.free(d);
    }
};

pub const SlotManager = struct {
    slots: []Slot,
    head: usize = 0,
    tail: usize = 0,
    capacity: usize,
    allocator: std.mem.Allocator,
    is_feeder_done: bool = false,

    // NEW: Condition Variable Sync
    mutex: blocking_sync.Mutex,
    cond_feeder: blocking_sync.Condition, // Wait for empty slots
    cond_worker: blocking_sync.Condition, // Wait for compressed slots
    cond_reader: blocking_sync.Condition, // Wait for ready slot at 'head'

    pub fn init(allocator: std.mem.Allocator, capacity: usize, decomp_size: usize) !*SlotManager {
        const self = try allocator.create(SlotManager);
        const slots = try allocator.alloc(Slot, capacity);
        for (slots) |*s| {
            s.* = try Slot.init(allocator, decomp_size);
        }
        self.* = .{
            .slots = slots,
            .capacity = capacity,
            .allocator = allocator,
            .mutex = blocking_sync.Mutex.init(),
            .cond_feeder = blocking_sync.Condition.init(),
            .cond_worker = blocking_sync.Condition.init(),
            .cond_reader = blocking_sync.Condition.init(),
        };
        return self;
    }

    pub fn deinit(self: *SlotManager) void {
        for (self.slots) |*s| s.deinit(self.allocator);
        self.allocator.free(self.slots);
        self.mutex.deinit();
        self.cond_feeder.deinit();
        self.cond_worker.deinit();
        self.cond_reader.deinit();
        self.allocator.destroy(self);
    }

    pub fn acquireSlotForAssign(self: *SlotManager) *Slot {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.tail -% self.head == self.capacity) {
            self.cond_feeder.wait(&self.mutex);
        }
        return &self.slots[self.tail % self.capacity];
    }

    pub fn commitAssign(self: *SlotManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.slots[self.tail % self.capacity].status.store(@intFromEnum(SlotStatus.compressed), .release);
        self.tail += 1;
        self.cond_worker.signal();
    }

    pub fn commitReady(self: *SlotManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.slots[self.tail % self.capacity].status.store(@intFromEnum(SlotStatus.ready), .release);
        self.tail += 1;
        self.cond_reader.broadcast(); // Always broadcast to reader since it's sequential
    }

    pub fn releaseSlotForAssign(self: *SlotManager, slot: *Slot) void {
        _ = self; _ = slot;
        // No-op or just unlock if needed. 
        // Since we didn't increment tail, the slot remains "empty" at the same position.
    }

    pub fn acquireSlotForRead(self: *SlotManager) ?*Slot {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (true) {
            if (self.head == self.tail) {
                if (self.is_feeder_done) return null;
                self.cond_reader.wait(&self.mutex);
                continue;
            }

            const slot = &self.slots[self.head % self.capacity];
            if (slot.status.load(.acquire) == @intFromEnum(SlotStatus.ready)) {
                return slot;
            }
            
            // If the slot at head is not ready yet, we must wait.
            self.cond_reader.wait(&self.mutex);
        }
    }

    pub fn commitRead(self: *SlotManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const slot = &self.slots[self.head % self.capacity];
        if (slot.compressed_data) |d| {
            self.allocator.free(d);
            slot.compressed_data = null;
        }
        slot.decompressed_len = 0;
        slot.status.store(@intFromEnum(SlotStatus.empty), .release);
        
        self.head += 1;
        self.cond_feeder.signal();
    }

    pub fn getSlotForDecompression(self: *SlotManager) ?*Slot {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (true) {
            var i = self.head;
            while (i != self.tail) : (i += 1) {
                const slot = &self.slots[i % self.capacity];
                if (slot.status.load(.acquire) == @intFromEnum(SlotStatus.compressed)) {
                    if (slot.status.cmpxchgStrong(@intFromEnum(SlotStatus.compressed), @intFromEnum(SlotStatus.decompressing), .acquire, .acquire) == null) {
                        return slot;
                    }
                }
            }

            if (self.is_feeder_done) return null;
            self.cond_worker.wait(&self.mutex);
        }
    }

    pub fn signalSlotReady(self: *SlotManager, slot : *Slot) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        slot.status.store(@intFromEnum(SlotStatus.ready), .release);
        self.cond_reader.broadcast();
    }
    
    pub fn signalFeederDone(self: *SlotManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.is_feeder_done = true;
        self.cond_worker.broadcast();
        self.cond_reader.broadcast();
    }
};

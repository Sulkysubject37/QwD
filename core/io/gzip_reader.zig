const std = @import("std");
const mode_mod = @import("mode");
const RingBuffer = @import("ring_buffer").RingBuffer;

pub const GzipReader = struct {
    inner_reader: std.io.AnyReader,
    
    io_buf: []u8,
    io_stream: std.io.FixedBufferStream([]u8),
    current_worker_buf: []u8, 
    
    decomp_pos: usize = 0,
    total_decomp_len: usize = 0,
    eof: bool = false,
    gzip_mode: mode_mod.GzipMode,
    allocator: std.mem.Allocator,
    
    // Stable streaming decompressor
    decompressor: ?std.compress.gzip.Decompressor(std.io.AnyReader) = null,
    deflate_wrapper: @import("deflate_wrapper").DeflateWrapper = .{},
    proxy_ptr: *ProxyContext = undefined,

    // Async Prefetch State
    thread: ?std.Thread = null,
    queue: ?*RingBuffer(PrefetchBlock) = null,
    current_block: ?PrefetchBlock = null,
    background_eof: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    background_error: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    
    mutex: std.Thread.Mutex = .{},

    const PrefetchBlock = struct {
        data: []u8,
        len: usize,
    };

    const ProxyContext = struct {
        parent: *GzipReader,
        pub fn read(ctx: *const anyopaque, b: []u8) anyerror!usize {
            const self_p: *const ProxyContext = @ptrFromInt(@intFromPtr(ctx));
            const p = self_p.parent;
            
            const buffered_rem = p.io_stream.buffer.len - p.io_stream.pos;
            if (buffered_rem > 0) {
                const n = @min(b.len, buffered_rem);
                @memcpy(b[0..n], p.io_buf[p.io_stream.pos .. p.io_stream.pos + n]);
                p.io_stream.pos += n;
                return n;
            }
            
            return p.inner_reader.read(b);
        }
    };

    pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader, gzip_mode: mode_mod.GzipMode) !GzipReader {
        const io_buf = try allocator.alloc(u8, 1024 * 1024); 
        const worker_buf = try allocator.alloc(u8, 256 * 1024);
        
        var self = GzipReader{
            .inner_reader = reader,
            .io_buf = io_buf,
            .io_stream = std.io.fixedBufferStream(io_buf[0..0]),
            .current_worker_buf = worker_buf,
            .gzip_mode = gzip_mode,
            .allocator = allocator,
        };
        
        self.proxy_ptr = try allocator.create(ProxyContext);
        self.proxy_ptr.parent = undefined; 
        self.queue = try RingBuffer(PrefetchBlock).init(allocator, 32);
        return self;
    }

    pub fn start(self: *GzipReader) !void {
        if (self.thread == null) {
            self.thread = try std.Thread.spawn(.{}, prefetchWorker, .{self});
        }
    }

    pub fn deinit(self: *GzipReader, allocator: std.mem.Allocator) void {
        self.background_eof.store(true, .release);
        if (self.thread) |t| t.join();
        if (self.queue) |q| {
            while (q.pop()) |block| allocator.free(block.data);
            q.deinit();
        }
        if (self.current_block) |blk| allocator.free(blk.data);
        allocator.free(self.current_worker_buf);
        allocator.free(self.io_buf);
        allocator.destroy(self.proxy_ptr);
    }

    fn prefetchWorker(self: *GzipReader) void {
        while (!self.background_eof.load(.acquire)) {
            var n: usize = 0;
            self.fillInternal(&n) catch |err| {
                if (err == error.EndOfStream) {
                    self.background_eof.store(true, .release);
                    break;
                }
                self.background_error.store(true, .release);
                break;
            };
            if (n > 0) {
                const stable_data = self.allocator.alloc(u8, n) catch {
                    self.background_error.store(true, .release);
                    break;
                };
                @memcpy(stable_data, self.current_worker_buf[0..n]);
                const pb = PrefetchBlock{ .data = stable_data, .len = n };
                while (!self.queue.?.push(pb)) {
                    if (self.background_eof.load(.acquire)) {
                        self.allocator.free(stable_data);
                        return;
                    }
                    std.Thread.yield() catch {};
                }
            } else if (self.eof) {
                self.background_eof.store(true, .release);
                break;
            }
        }
    }

    fn ensureData(self: *GzipReader, n: usize) !void {
        const remaining = self.io_stream.buffer.len - self.io_stream.pos;
        if (remaining >= n) return;
        if (remaining > 0) {
            std.mem.copyForwards(u8, self.io_buf[0..remaining], self.io_buf[self.io_stream.pos..self.io_stream.buffer.len]);
        }
        const read_len = try self.inner_reader.read(self.io_buf[remaining..]);
        if (read_len == 0 and remaining == 0) return error.EndOfStream;
        self.io_stream.buffer = self.io_buf[0..remaining + read_len];
        self.io_stream.pos = 0;
    }

    fn fillInternal(self: *GzipReader, out_len: *usize) !void {
        while (true) {
            if (self.decompressor) |*d| {
                const n = d.reader().read(self.current_worker_buf) catch |err| {
                    if (err == error.EndOfStream) {
                        self.decompressor = null;
                        continue;
                    }
                    return err;
                };
                if (n > 0) { out_len.* = n; return; }
                self.decompressor = null;
            }
            
            self.ensureData(10) catch |err| {
                if (err == error.EndOfStream) { self.eof = true; return; }
                return err;
            };
            
            const buf = self.io_buf[self.io_stream.pos..];
            if (buf[0] != 0x1F or buf[1] != 0x8B) { self.eof = true; return; }
            
            // Check if we can use deflate_wrapper for this block
            // Gzip member starts here.
            // For now, we'll stick to std.compress.gzip for robustness in streaming
            // but wrapped in the prefetch worker.
            const any_pr = std.io.AnyReader{ .context = self.proxy_ptr, .readFn = ProxyContext.read };
            self.decompressor = std.compress.gzip.decompressor(any_pr);
        }
    }

    pub fn read(self: *GzipReader, dest: []u8) !usize {
        if (dest.len == 0) return 0;
        
        // Ensure thread is started if we are using the streaming model
        if (self.thread == null and !self.eof) {
            try self.start();
        }

        if (self.current_block) |*blk| {
            if (self.decomp_pos < blk.len) {
                const can_read = @min(dest.len, blk.len - self.decomp_pos);
                @memcpy(dest[0..can_read], blk.data[self.decomp_pos .. self.decomp_pos + can_read]);
                self.decomp_pos += can_read;
                return can_read;
            } else {
                self.allocator.free(blk.data);
                self.current_block = null;
            }
        }
        
        while (self.current_block == null) {
            if (self.background_error.load(.acquire)) return error.BackgroundDecompressionFailed;
            if (self.queue.?.pop()) |blk| {
                self.current_block = blk;
                self.decomp_pos = 0;
                return self.read(dest);
            } else {
                if (self.background_eof.load(.acquire)) {
                    if (self.queue.?.pop()) |blk| {
                        self.current_block = blk;
                        self.decomp_pos = 0;
                        return self.read(dest);
                    }
                    return 0;
                }
                std.Thread.yield() catch {};
            }
        }
        return 0;
    }

    pub fn anyReader(self: *GzipReader) std.io.AnyReader {
        return .{ .context = self, .readFn = readAny };
    }

    fn readAny(context: *const anyopaque, dest: []u8) anyerror!usize {
        const self: *GzipReader = @ptrFromInt(@intFromPtr(context));
        return self.read(dest);
    }
};

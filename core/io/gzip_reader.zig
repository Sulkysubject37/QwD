const std = @import("std");
const deflate = @import("deflate_wrapper");
const mode_mod = @import("mode");
const custom_deflate = @import("custom_deflate.zig");
const RingBuffer = @import("ring_buffer").RingBuffer;

pub const GzipReader = struct {
    inner_reader: std.io.AnyReader,
    decompressor: deflate.Decompressor,
    qwd_engine: custom_deflate.DeflateEngine,
    
    io_buf: []u8,
    io_stream: std.io.FixedBufferStream([]u8),
    
    // This buffer is used by the prefetch thread to decompress into
    current_worker_buf: []u8, 
    
    decomp_pos: usize = 0,
    eof: bool = false,
    gzip_mode: mode_mod.GzipMode,
    allocator: std.mem.Allocator,
    
    fallback_decompressor: ?std.compress.gzip.Decompressor(std.io.AnyReader) = null,
    proxy_ptr: *ProxyContext = undefined,

    // Async Prefetch State
    thread: ?std.Thread = null,
    queue: ?*RingBuffer(PrefetchBlock) = null,
    current_block: ?PrefetchBlock = null,
    background_eof: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    background_error: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    const PrefetchBlock = struct {
        data: []u8,
        len: usize,
    };

    const ProxyContext = struct {
        parent: *GzipReader,
        pub fn read(ctx: *const anyopaque, b: []u8) anyerror!usize {
            const self_p: *const ProxyContext = @ptrFromInt(@intFromPtr(ctx));
            const p = self_p.parent;
            const rem = p.io_stream.buffer.len - p.io_stream.pos;
            if (rem > 0) {
                const n = @min(b.len, rem);
                @memcpy(b[0..n], p.io_buf[p.io_stream.pos .. p.io_stream.pos + n]);
                p.io_stream.pos += n;
                return n;
            }
            return p.inner_reader.read(b);
        }
    };

    pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader, gzip_mode: mode_mod.GzipMode) !GzipReader {
        const io_buf = try allocator.alloc(u8, 1024 * 1024); 
        const worker_buf = try allocator.alloc(u8, 1024 * 1024);
        
        var self = GzipReader{
            .inner_reader = reader,
            .decompressor = try deflate.Decompressor.init(),
            .qwd_engine = custom_deflate.DeflateEngine.init(reader),
            .io_buf = io_buf,
            .io_stream = std.io.fixedBufferStream(io_buf[0..0]),
            .current_worker_buf = worker_buf,
            .gzip_mode = gzip_mode,
            .allocator = allocator,
        };
        
        self.proxy_ptr = try allocator.create(ProxyContext);
        self.proxy_ptr.* = ProxyContext{ .parent = undefined };
        
        self.queue = try RingBuffer(PrefetchBlock).init(allocator, 16);
        
        return self;
    }

    pub fn start(self: *GzipReader) !void {
        self.thread = try std.Thread.spawn(.{}, prefetchWorker, .{self});
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

        self.decompressor.deinit();
        allocator.free(self.io_buf);
        allocator.destroy(self.proxy_ptr);
    }

    fn prefetchWorker(self: *GzipReader) void {
        self.proxy_ptr.parent = self;
        
        while (!self.background_eof.load(.acquire)) {
            var decomp_len: usize = 0;
            
            // Decompress into the dedicated worker buffer
            self.fillInternal(&decomp_len) catch {
                self.background_error.store(true, .release);
                break;
            };
            
            if (decomp_len > 0) {
                // To pass to the queue, we MUST copy the data to a new stable buffer
                // so the worker can reuse current_worker_buf immediately.
                const stable_data = self.allocator.alloc(u8, decomp_len) catch {
                    self.background_error.store(true, .release);
                    break;
                };
                @memcpy(stable_data, self.current_worker_buf[0..decomp_len]);
                
                const pb = PrefetchBlock{ .data = stable_data, .len = decomp_len };
                while (!self.queue.?.push(pb)) {
                    if (self.background_eof.load(.acquire)) {
                        self.allocator.free(stable_data);
                        return;
                    }
                    std.Thread.yield() catch {};
                }
            }
            
            if (self.eof) {
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
        self.io_stream.buffer = self.io_buf[0..remaining + read_len];
        self.io_stream.pos = 0;
    }

    // INTERNAL: Decoupled from state management, just fills a buffer
    fn fillInternal(self: *GzipReader, out_len: *usize) !void {
        if (self.fallback_decompressor) |*fd| {
            const n = try fd.reader().read(self.current_worker_buf);
            if (n > 0) {
                out_len.* = n;
                return;
            }
            self.fallback_decompressor = null;
        }

        self.ensureData(18) catch |err| {
            if (err == error.EndOfStream) { self.eof = true; return; }
            return err;
        };
        const peek_buf = self.io_buf[self.io_stream.pos..self.io_stream.buffer.len];
        if (peek_buf.len == 0) { self.eof = true; return; }
        if (peek_buf.len < 10) { self.eof = true; return; }
        if (peek_buf[0] != 0x1F or peek_buf[1] != 0x8B) { self.eof = true; return; }

        const flags = peek_buf[3];
        var is_bgzf = false;
        var block_size: u16 = 0;
        
        if (flags & 0x04 != 0 and peek_buf.len >= 18) {
            if (peek_buf[12] == 'B' and peek_buf[13] == 'C') {
                block_size = std.mem.readInt(u16, peek_buf[16..18], .little);
                is_bgzf = true;
            }
        }

        const effective_mode = if (self.gzip_mode == .AUTO) (if (is_bgzf) mode_mod.GzipMode.LIBDEFLATE else mode_mod.GzipMode.CHUNKED) else self.gzip_mode;

        if ((effective_mode == .LIBDEFLATE or effective_mode == .NATIVE_QWD) and is_bgzf) {
            self.io_stream.pos += 18;
            const data_len = (block_size + 1) - 18 - 8;
            try self.ensureData(data_len + 8);
            const comp_data = self.io_buf[self.io_stream.pos .. self.io_stream.pos + data_len];
            out_len.* = try self.decompressor.decompress_raw(comp_data, self.current_worker_buf);
            self.io_stream.pos += data_len + 8;
        } else {
            const any_pr = std.io.AnyReader{ .context = self.proxy_ptr, .readFn = ProxyContext.read };
            self.fallback_decompressor = std.compress.gzip.decompressor(any_pr);
            out_len.* = try self.fallback_decompressor.?.reader().read(self.current_worker_buf);
        }
    }

    pub fn read(self: *GzipReader, dest: []u8) !usize {
        if (dest.len == 0) return 0;
        if (self.background_error.load(.acquire)) return error.BackgroundDecompressionFailed;

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
            if (self.queue.?.pop()) |blk| {
                self.current_block = blk;
                self.decomp_pos = 0;
                return self.read(dest);
            } else {
                if (self.background_eof.load(.acquire)) return 0;
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

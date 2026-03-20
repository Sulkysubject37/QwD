const std = @import("std");
const block_reader = @import("block_reader");

pub const ChunkBuilder = struct {
    br: *block_reader.BlockReader,
    chunk_size: usize,

    pub fn init(br: *block_reader.BlockReader, chunk_size: usize) ChunkBuilder {
        return .{
            .br = br,
            .chunk_size = chunk_size,
        };
    }

    pub fn nextChunk(self: *ChunkBuilder) !?[]u8 {
        if (self.br.pos >= self.br.end) {
            if (self.br.is_mmap) {
                return null;
            } else {
                const read_len = try self.br.fill();
                if (read_len == 0) return null;
            }
        }

        var end_idx = self.br.pos + self.chunk_size;
        
        if (self.br.is_mmap) {
            if (end_idx >= self.br.end) {
                const chunk = self.br.buffer[self.br.pos .. self.br.end];
                self.br.pos = self.br.end;
                return chunk;
            }

            // Find the NEXT record boundary near the target chunk_size
            // Search forward first
            var search_idx = end_idx;
            const search_limit = if (search_idx + 1024 * 1024 > self.br.end) self.br.end else search_idx + 1024 * 1024;
            
            while (search_idx < search_limit) : (search_idx += 1) {
                if (search_idx > 0 and self.br.buffer[search_idx - 1] == '\n' and self.br.buffer[search_idx] == '@') {
                    const chunk = self.br.buffer[self.br.pos .. search_idx];
                    self.br.pos = search_idx;
                    return chunk;
                }
            }
            
            // If forward search failed (rare for FASTQ), search backward
            search_idx = end_idx;
            while (search_idx > self.br.pos + 1) : (search_idx -= 1) {
                if (self.br.buffer[search_idx - 1] == '\n' and self.br.buffer[search_idx] == '@') {
                    const chunk = self.br.buffer[self.br.pos .. search_idx];
                    self.br.pos = search_idx;
                    return chunk;
                }
            }
            
            // Still nothing? Just return the rest
            const chunk = self.br.buffer[self.br.pos .. self.br.end];
            self.br.pos = self.br.end;
            return chunk;
        } else {
            // For streaming (not mmap), we would just return whatever is in the buffer up to a boundary
            // Since phase Q ultimate focuses on mmap performance, we can just do a simple boundary check
            // on the current buffer.
            if (end_idx >= self.br.end) {
                end_idx = self.br.end;
            }
            
            while (end_idx > self.br.pos + 1) : (end_idx -= 1) {
                if (self.br.buffer[end_idx - 1] == '\n' and self.br.buffer[end_idx] == '@') {
                    break;
                }
            }
            
            if (end_idx == self.br.pos + 1) {
                // Buffer too small to find a boundary, or single massive record
                end_idx = self.br.end;
            }
            
            const chunk = self.br.buffer[self.br.pos .. end_idx];
            self.br.pos = end_idx;
            return chunk;
        }
    }
};

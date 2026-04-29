import gzip
import struct

def make_bgzf_block(data):
    # This is a very simplified BGZF block generator
    # A real BGZF block has an extra field "BC" with the block size
    compressed = gzip.compress(data, compresslevel=1)
    
    # We need to insert the BC extra field into the header
    # Gzip header: ID1 ID2 CM FLG MTIME XFL OS
    # BGZF header adds: XLEN (2 bytes) + SI1 SI2 SLEN (2 bytes) + BSIZE (2 bytes)
    
    # Standard Gzip header is 10 bytes
    header = list(compressed[:10])
    header[3] = 4 # FLG_FEXTRA
    
    # Extra field "BC" with length 2
    extra = b'BC\x02\x00'
    
    # Block size = len(compressed) + len(extra) + 2 (XLEN)
    # But wait, BGZF BSIZE is total block size - 1
    bsize = len(compressed) + 6
    extra += struct.pack('<H', bsize - 1)
    
    # New header: original 10 + XLEN(2) + EXTRA(6)
    new_header = bytes(header) + struct.pack('<H', 6) + extra
    
    # Full block: new_header + compressed_data (minus original header)
    return new_header + compressed[10:]

# Generate 1000 reads
reads = ""
for i in range(1000):
    reads += f"@READ_{i}\nATGCATGCATGCATGC\n+\nIIIIIIIIIIIIIIII\n"

# Split into two blocks to test boundary handling
half = len(reads) // 2
block1 = make_bgzf_block(reads[:half].encode())
block2 = make_bgzf_block(reads[half:].encode())

# Final empty block (BGZF EOF marker)
eof_block = b"\x1f\x8b\x08\x04\x00\x00\x00\x00\x00\xff\x06\x00BC\x02\x00\x1b\x00\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00"

with open("test_small.bgzf.gz", "wb") as f:
    f.write(block1)
    f.write(block2)
    f.write(eof_block)

print("Generated test_small.bgzf.gz (1000 reads, 2 blocks)")

import ctypes
import json
import os
import platform

# Find and load the shared library
lib_name = "qwd"
if platform.system() == "Windows":
    lib_file = f"{lib_name}.dll"
elif platform.system() == "Darwin":
    lib_file = f"lib{lib_name}.dylib"
else:
    lib_file = f"lib{lib_name}.so"

# We expect the library to be in the same directory or in zig-out/lib
possible_paths = [
    os.path.join(os.path.dirname(__file__), lib_file),
    os.path.join(os.getcwd(), "zig-out", "lib", lib_file),
    os.path.join(os.getcwd(), lib_file),
]

_lib = None
for path in possible_paths:
    if os.path.exists(path):
        _lib = ctypes.CDLL(path)
        break

if _lib is None:
    # Fallback to system search
    try:
        _lib = ctypes.CDLL(lib_file)
    except OSError:
        pass

if _lib:
    _lib.qwd_fastq_qc.restype = ctypes.c_void_p
    _lib.qwd_fastq_qc.argtypes = [ctypes.c_char_p]
    
    _lib.qwd_bam_stats.restype = ctypes.c_void_p
    _lib.qwd_bam_stats.argtypes = [ctypes.c_char_p]
    
    _lib.qwd_pipeline.restype = ctypes.c_void_p
    _lib.qwd_pipeline.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    
    _lib.qwd_free_string.argtypes = [ctypes.c_void_p]

def qc(fastq_path):
    if not _lib: raise RuntimeError("QwD shared library not found")
    res_ptr = _lib.qwd_fastq_qc(fastq_path.encode('utf-8'))
    res_str = ctypes.string_at(res_ptr).decode('utf-8')
    data = json.loads(res_str)
    _lib.qwd_free_string(res_ptr)
    return data

def bamstats(bam_path):
    if not _lib: raise RuntimeError("QwD shared library not found")
    res_ptr = _lib.qwd_bam_stats(bam_path.encode('utf-8'))
    res_str = ctypes.string_at(res_ptr).decode('utf-8')
    data = json.loads(res_str)
    _lib.qwd_free_string(res_ptr)
    return data

def pipeline(config_json_path, input_path):
    if not _lib: raise RuntimeError("QwD shared library not found")
    with open(config_json_path, 'r') as f:
        config_str = f.read()
    res_ptr = _lib.qwd_pipeline(config_str.encode('utf-8'), input_path.encode('utf-8'))
    res_str = ctypes.string_at(res_ptr).decode('utf-8')
    data = json.loads(res_str)
    _lib.qwd_free_string(res_ptr)
    return data

const std = @import("std");

pub const Mode = enum {
    EXACT,
    APPROX,
};

pub const GzipMode = enum {
    AUTO,
    LIBDEFLATE,
    CHUNKED,
    COMPAT,
    NATIVE_QWD, // Our pure-Zig engine
};

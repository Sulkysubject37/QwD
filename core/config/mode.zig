const std = @import("std");

pub const Mode = enum {
    EXACT,
    APPROX,
};

pub const GzipMode = enum {
    AUTO,
    NATIVE,
    LIBDEFLATE,
    CHUNKED,
    COMPAT,
};

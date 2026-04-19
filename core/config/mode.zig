const std = @import("std");

pub const Mode = enum {
    exact,
    fast,
};

pub const GzipMode = enum {
    auto,
    native,
    libdeflate,
};

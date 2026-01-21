//! wat2wasm - WebAssembly Text to Binary compiler
//!
//! Compiles WAT (WebAssembly Text Format) to WASM binary format.
//! Designed with explicit memory regions for eventual self-hosting.

const std = @import("std");

pub const leb128 = @import("leb128.zig");
pub const wasm = @import("wasm.zig");
pub const token = @import("token.zig");
pub const lexer = @import("lexer.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("wat2wasm - work in progress\n", .{});
}

// Include all tests from submodules
test {
    _ = leb128;
    _ = wasm;
    _ = token;
    _ = lexer;
}

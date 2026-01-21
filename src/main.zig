//! wat2wasm - WebAssembly Text to Binary compiler
//!
//! Compiles WAT (WebAssembly Text Format) to WASM binary format.
//! Designed with explicit memory regions for eventual self-hosting.

const std = @import("std");

pub const leb128 = @import("leb128.zig");
pub const wasm = @import("wasm.zig");
pub const token = @import("token.zig");
pub const lexer = @import("lexer.zig");
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const encoder = @import("encoder.zig");

pub fn main() !void {
    const args = std.process.argsAlloc(std.heap.page_allocator) catch {
        return error.OutOfMemory;
    };
    defer std.process.argsFree(std.heap.page_allocator, args);

    // Parse arguments
    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-o") and i + 1 < args.len) {
            output_path = args[i + 1];
            i += 1;
        } else if (args[i][0] != '-') {
            input_path = args[i];
        }
    }

    if (input_path == null) {
        try writeStderr("Usage: wat2wasm <input.wat> -o <output.wasm>\n");
        return error.InvalidArguments;
    }

    if (output_path == null) {
        try writeStderr("Error: -o <output> required\n");
        return error.InvalidArguments;
    }

    // Use fixed-size buffers
    var source_buf: [64 * 1024]u8 = undefined; // 64KB source
    var token_buf: [4096]token.Token = undefined;
    var node_buf: [4096]ast.Node = undefined;
    var output_buf: [64 * 1024]u8 = undefined; // 64KB output

    // Read input file
    const source = readFile(input_path.?, &source_buf) catch {
        try writeStderr("Error reading input file\n");
        return error.ReadError;
    };

    // Lex
    var lex = lexer.Lexer.init(source);
    const token_count = lex.tokenize(&token_buf) orelse {
        try writeStderr("Error: too many tokens\n");
        return error.TooManyTokens;
    };
    _ = token_count;

    // Parse
    var parse = parser.Parser.init(&token_buf, source);
    const node_count = switch (parse.parse(&node_buf)) {
        .ok => |count| count,
        .err => {
            try writeStderr("Parse error\n");
            return error.ParseError;
        },
    };

    // Encode
    var enc = encoder.Encoder.init(&node_buf, node_count);
    const output_len = switch (enc.encode(&output_buf)) {
        .ok => |len| len,
        .err => {
            try writeStderr("Encode error\n");
            return error.EncodeError;
        },
    };

    // Write output
    writeFile(output_path.?, output_buf[0..output_len]) catch {
        try writeStderr("Error writing output file\n");
        return error.WriteError;
    };
}

fn readFile(path: []const u8, buf: []u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const len = try file.readAll(buf);
    return buf[0..len];
}

fn writeFile(path: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(data);
}

fn writeStderr(msg: []const u8) !void {
    const handle: std.posix.fd_t = 2; // STDERR_FILENO
    _ = std.posix.write(handle, msg) catch return error.WriteError;
}

// Include all tests from submodules
test {
    _ = leb128;
    _ = wasm;
    _ = token;
    _ = lexer;
    _ = ast;
    _ = parser;
    _ = encoder;
}

//! WASM binary encoder.
//!
//! Encodes an AST into WebAssembly binary format.
//! No allocation - all output goes into the provided slice.

const Node = @import("ast.zig").Node;
const ast = @import("ast.zig");
const wasm = @import("wasm.zig");
const leb128 = @import("leb128.zig");

pub const Encoder = struct {
    nodes: []const Node,
    node_count: u32,

    pub fn init(nodes: []const Node, node_count: u32) Encoder {
        return .{
            .nodes = nodes,
            .node_count = node_count,
        };
    }

    pub const Result = union(enum) {
        ok: u32, // number of bytes written
        err: Error,
    };

    pub const Error = struct {
        tag: Tag,
        node_idx: u32,

        pub const Tag = enum {
            buffer_overflow,
            invalid_ast,
        };
    };

    /// Encode the AST into WASM binary.
    /// Returns the number of bytes written, or an error.
    pub fn encode(self: *Encoder, output: []u8) Result {
        // Need at least a module node
        if (self.node_count == 0 or self.nodes[0].tag != .module) {
            return .{ .err = .{ .tag = .invalid_ast, .node_idx = 0 } };
        }

        var pos: u32 = 0;

        // Write magic number: \0asm
        if (pos + 4 > output.len) {
            return .{ .err = .{ .tag = .buffer_overflow, .node_idx = 0 } };
        }
        output[pos..][0..4].* = wasm.magic;
        pos += 4;

        // Write version: 1
        if (pos + 4 > output.len) {
            return .{ .err = .{ .tag = .buffer_overflow, .node_idx = 0 } };
        }
        output[pos..][0..4].* = wasm.version;
        pos += 4;

        // Count functions
        const func_count = self.countFunctions();

        if (func_count > 0) {
            // Type section: define function signatures
            // For now, all functions have signature () -> ()
            pos = self.encodeTypeSection(output, pos, func_count) orelse {
                return .{ .err = .{ .tag = .buffer_overflow, .node_idx = 0 } };
            };

            // Function section: map functions to types
            pos = self.encodeFunctionSection(output, pos, func_count) orelse {
                return .{ .err = .{ .tag = .buffer_overflow, .node_idx = 0 } };
            };

            // Code section: function bodies
            pos = self.encodeCodeSection(output, pos, func_count) orelse {
                return .{ .err = .{ .tag = .buffer_overflow, .node_idx = 0 } };
            };
        }

        return .{ .ok = pos };
    }

    fn countFunctions(self: *Encoder) u32 {
        var count: u32 = 0;
        var iter = ast.children(self.nodes, &self.nodes[0]);
        while (iter.next()) |node| {
            if (node.tag == .func) count += 1;
        }
        return count;
    }

    /// Encode type section. For now, all functions are () -> ()
    fn encodeTypeSection(self: *Encoder, output: []u8, start_pos: u32, func_count: u32) ?u32 {
        _ = self;
        var pos = start_pos;

        // Section content (build in temp area, then write with size prefix)
        // For () -> () signature: 0x60 0x00 0x00

        // Content: count (LEB128) + count * signature
        // Each signature: 0x60 (func type) + 0x00 (0 params) + 0x00 (0 results)
        var content_buf: [64]u8 = undefined;
        var content_pos: usize = 0;

        // Number of types
        content_pos += leb128.encodeUnsigned(func_count, content_buf[content_pos..]) orelse return null;

        // Each type signature
        var i: u32 = 0;
        while (i < func_count) : (i += 1) {
            if (content_pos + 3 > content_buf.len) return null;
            content_buf[content_pos] = wasm.func_type; // 0x60
            content_buf[content_pos + 1] = 0x00; // 0 params
            content_buf[content_pos + 2] = 0x00; // 0 results
            content_pos += 3;
        }

        // Write section: id + size + content
        if (pos + 1 > output.len) return null;
        output[pos] = @intFromEnum(wasm.Section.type);
        pos += 1;

        // Section size
        const size_len = leb128.encodeUnsigned(content_pos, output[pos..]) orelse return null;
        pos += @intCast(size_len);

        // Section content
        if (pos + content_pos > output.len) return null;
        @memcpy(output[pos..][0..content_pos], content_buf[0..content_pos]);
        pos += @intCast(content_pos);

        return pos;
    }

    /// Encode function section: maps each function to its type index
    fn encodeFunctionSection(self: *Encoder, output: []u8, start_pos: u32, func_count: u32) ?u32 {
        _ = self;
        var pos = start_pos;

        var content_buf: [64]u8 = undefined;
        var content_pos: usize = 0;

        // Number of functions
        content_pos += leb128.encodeUnsigned(func_count, content_buf[content_pos..]) orelse return null;

        // Each function references type index (all type 0 for now)
        var i: u32 = 0;
        while (i < func_count) : (i += 1) {
            content_pos += leb128.encodeUnsigned(i, content_buf[content_pos..]) orelse return null;
        }

        // Write section
        if (pos + 1 > output.len) return null;
        output[pos] = @intFromEnum(wasm.Section.function);
        pos += 1;

        const size_len = leb128.encodeUnsigned(content_pos, output[pos..]) orelse return null;
        pos += @intCast(size_len);

        if (pos + content_pos > output.len) return null;
        @memcpy(output[pos..][0..content_pos], content_buf[0..content_pos]);
        pos += @intCast(content_pos);

        return pos;
    }

    /// Encode code section: function bodies
    fn encodeCodeSection(self: *Encoder, output: []u8, start_pos: u32, func_count: u32) ?u32 {
        _ = self;
        var pos = start_pos;

        var content_buf: [256]u8 = undefined;
        var content_pos: usize = 0;

        // Number of function bodies
        content_pos += leb128.encodeUnsigned(func_count, content_buf[content_pos..]) orelse return null;

        // Each function body: size + locals_count + code
        // Empty function: size=2, locals_count=0, code=end(0x0B)
        var i: u32 = 0;
        while (i < func_count) : (i += 1) {
            // Body size (2 bytes: 1 for local count + 1 for end)
            content_pos += leb128.encodeUnsigned(2, content_buf[content_pos..]) orelse return null;
            // Local declarations count = 0
            content_pos += leb128.encodeUnsigned(0, content_buf[content_pos..]) orelse return null;
            // Instructions: just 'end'
            if (content_pos >= content_buf.len) return null;
            content_buf[content_pos] = @intFromEnum(wasm.Op.end);
            content_pos += 1;
        }

        // Write section
        if (pos + 1 > output.len) return null;
        output[pos] = @intFromEnum(wasm.Section.code);
        pos += 1;

        const size_len = leb128.encodeUnsigned(content_pos, output[pos..]) orelse return null;
        pos += @intCast(size_len);

        if (pos + content_pos > output.len) return null;
        @memcpy(output[pos..][0..content_pos], content_buf[0..content_pos]);
        pos += @intCast(content_pos);

        return pos;
    }
};

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const testing = std.testing;
const Token = @import("token.zig").Token;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

test "encode empty module" {
    const source = "(module)";

    // Lex
    var tokens: [10]Token = undefined;
    var lexer = Lexer.init(source);
    _ = lexer.tokenize(&tokens).?;

    // Parse
    var nodes: [10]Node = undefined;
    var parser = Parser.init(&tokens, source);
    const parse_result = parser.parse(&nodes);
    const node_count = switch (parse_result) {
        .ok => |count| count,
        .err => return error.TestUnexpectedResult,
    };

    // Encode
    var output: [100]u8 = undefined;
    var encoder = Encoder.init(&nodes, node_count);
    const encode_result = encoder.encode(&output);

    switch (encode_result) {
        .ok => |len| {
            // Empty module is 8 bytes: magic (4) + version (4)
            try testing.expectEqual(@as(u32, 8), len);

            // Check magic: \0asm
            try testing.expectEqualSlices(u8, &wasm.magic, output[0..4]);

            // Check version: 1
            try testing.expectEqualSlices(u8, &wasm.version, output[4..8]);
        },
        .err => |err| {
            std.debug.print("Encode error: {any} at node {d}\n", .{ err.tag, err.node_idx });
            return error.TestUnexpectedResult;
        },
    }
}

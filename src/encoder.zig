//! WASM binary encoder.
//!
//! Encodes an AST into WebAssembly binary format.
//! No allocation - all output goes into the provided slice.

const Node = @import("ast.zig").Node;
const wasm = @import("wasm.zig");

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

        // TODO: encode sections based on module children
        // For now, empty module has no sections

        return .{ .ok = pos };
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

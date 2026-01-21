//! WAT (WebAssembly Text Format) parser.
//!
//! Parses tokens into a flat AST stored in a caller-provided buffer.
//! No allocation - all output goes into the provided slice.

const Token = @import("token.zig").Token;
const Node = @import("ast.zig").Node;

pub const Parser = struct {
    tokens: []const Token,
    source: []const u8,
    pos: u32,

    pub fn init(tokens: []const Token, source: []const u8) Parser {
        return .{
            .tokens = tokens,
            .source = source,
            .pos = 0,
        };
    }

    pub const Result = union(enum) {
        ok: u32, // number of nodes written
        err: Error,
    };

    pub const Error = struct {
        tag: Tag,
        token_idx: u32,

        pub const Tag = enum {
            unexpected_token,
            expected_lparen,
            expected_rparen,
            expected_keyword,
            expected_module,
            buffer_overflow,
        };
    };

    /// Parse the token stream into an AST.
    /// Returns the number of nodes written, or an error.
    pub fn parse(self: *Parser, nodes: []Node) Result {
        return self.parseModule(nodes);
    }

    /// Parse a module: (module ...)
    fn parseModule(self: *Parser, nodes: []Node) Result {
        // Expect '('
        if (!self.check(.lparen)) {
            return .{ .err = .{ .tag = .expected_lparen, .token_idx = self.pos } };
        }
        self.pos += 1;

        // Expect 'module' keyword
        if (!self.checkKeyword("module")) {
            return .{ .err = .{ .tag = .expected_module, .token_idx = self.pos } };
        }
        const module_token = self.pos;
        self.pos += 1;

        // Create module node
        if (nodes.len == 0) {
            return .{ .err = .{ .tag = .buffer_overflow, .token_idx = self.pos } };
        }
        nodes[0] = .{
            .tag = .module,
            .first_child = Node.none,
            .next_sibling = Node.none,
            .token_idx = module_token,
        };

        // For now, skip to closing paren (no children yet)
        // TODO: parse module fields (func, memory, etc.)
        
        // Expect ')'
        if (!self.check(.rparen)) {
            return .{ .err = .{ .tag = .expected_rparen, .token_idx = self.pos } };
        }
        self.pos += 1;

        return .{ .ok = 1 };
    }

    /// Check if current token has the given tag
    fn check(self: *Parser, tag: Token.Tag) bool {
        if (self.pos >= self.tokens.len) return false;
        return self.tokens[self.pos].tag == tag;
    }

    /// Check if current token is a keyword with the given text
    fn checkKeyword(self: *Parser, keyword: []const u8) bool {
        if (self.pos >= self.tokens.len) return false;
        const tok = self.tokens[self.pos];
        if (tok.tag != .keyword) return false;
        return std.mem.eql(u8, tok.text(self.source), keyword);
    }
};

const std = @import("std");

// ============================================================================
// Tests
// ============================================================================

const testing = @import("std").testing;
const Lexer = @import("lexer.zig").Lexer;

test "parse empty module" {
    const source = "(module)";

    // Lex
    var tokens: [10]Token = undefined;
    var lexer = Lexer.init(source);
    const token_count = lexer.tokenize(&tokens).?;
    _ = token_count;

    // Parse
    var nodes: [10]Node = undefined;
    var parser = Parser.init(&tokens, source);
    const result = parser.parse(&nodes);

    // Should succeed with 1 node (the module)
    switch (result) {
        .ok => |count| {
            try testing.expectEqual(@as(u32, 1), count);
            try testing.expectEqual(Node.Tag.module, nodes[0].tag);
        },
        .err => |err| {
            std.debug.print("Parse error: {any} at token {d}\n", .{ err.tag, err.token_idx });
            return error.TestUnexpectedResult;
        },
    }
}

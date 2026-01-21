//! Token definitions for WAT lexer.
//!
//! Tokens store offsets into the source buffer rather than copying strings.
//! This avoids allocation and keeps memory usage bounded.

pub const Token = struct {
    tag: Tag,
    /// Byte offset into source where this token starts
    start: u32,
    /// Byte length of this token
    len: u16,

    pub const Tag = enum {
        // Structural
        lparen,
        rparen,

        // Atoms
        keyword, // module, func, param, result, i32, etc.
        identifier, // $name
        integer, // 42, 0xFF, -1
        float, // 3.14, 1e10
        string, // "hello"

        // Special
        eof,
        invalid,
    };

    /// Get the source text for this token
    pub fn text(self: Token, source: []const u8) []const u8 {
        return source[self.start..][0..self.len];
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = @import("std").testing;

test "Token.text extracts correct slice" {
    const source = "(module $test)";
    const tok = Token{
        .tag = .keyword,
        .start = 1,
        .len = 6,
    };
    try testing.expectEqualStrings("module", tok.text(source));
}

test "Token size is compact" {
    // Ensure our token struct is reasonably sized
    try testing.expect(@sizeOf(Token) <= 12);
}

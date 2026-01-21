//! WAT (WebAssembly Text Format) lexer.
//!
//! Tokenizes WAT source into a caller-provided token buffer.
//! No allocation - all output goes into the provided slice.
//!
//! ## Known Limitations (TODO)
//! - `nan`, `inf`, `nan:0x...` float literals not yet recognized as floats
//! - Unicode escapes in strings (`\u{...}`) not validated
//! - Underscores in hex numbers (`0xDEAD_BEEF`) not supported

const Token = @import("token.zig").Token;

pub const Lexer = struct {
    source: []const u8,
    pos: u32,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .pos = 0,
        };
    }

    /// Tokenize the entire source into the provided buffer.
    /// Returns the number of tokens written, or null if buffer is too small.
    pub fn tokenize(self: *Lexer, tokens: []Token) ?usize {
        var count: usize = 0;

        while (true) {
            if (count >= tokens.len) return null;

            const tok = self.next();
            tokens[count] = tok;
            count += 1;

            if (tok.tag == .eof) break;
        }

        return count;
    }

    /// Get the next token
    pub fn next(self: *Lexer) Token {
        self.skipWhitespaceAndComments();

        if (self.pos >= self.source.len) {
            return .{
                .tag = .eof,
                .start = @intCast(self.source.len),
                .len = 0,
            };
        }

        const start = self.pos;
        const c = self.source[self.pos];

        // Single-character tokens
        if (c == '(') {
            self.pos += 1;
            return .{ .tag = .lparen, .start = start, .len = 1 };
        }
        if (c == ')') {
            self.pos += 1;
            return .{ .tag = .rparen, .start = start, .len = 1 };
        }

        // String literal
        if (c == '"') {
            return self.readString(start);
        }

        // Identifier ($name)
        if (c == '$') {
            return self.readIdentifier(start);
        }

        // Number (starts with digit, or +/- followed by digit)
        if (isDigit(c) or ((c == '+' or c == '-') and self.peekNext() != null and isDigit(self.peekNext().?))) {
            return self.readNumber(start);
        }

        // Keyword or other atom
        if (isIdChar(c)) {
            return self.readKeyword(start);
        }

        // Invalid character
        self.pos += 1;
        return .{ .tag = .invalid, .start = start, .len = 1 };
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];

            // Whitespace
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
                continue;
            }

            // Line comment: ;; ...
            if (c == ';' and self.peekNext() == ';') {
                self.pos += 2;
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
                continue;
            }

            // Block comment: (; ... ;)
            if (c == '(' and self.peekNext() == ';') {
                self.pos += 2;
                var depth: u32 = 1;
                while (depth > 0 and self.pos + 1 < self.source.len) {
                    if (self.source[self.pos] == ';' and self.source[self.pos + 1] == ')') {
                        depth -= 1;
                        self.pos += 2;
                    } else if (self.source[self.pos] == '(' and self.source[self.pos + 1] == ';') {
                        depth += 1;
                        self.pos += 2;
                    } else {
                        self.pos += 1;
                    }
                }
                continue;
            }

            break;
        }
    }

    fn readString(self: *Lexer, start: u32) Token {
        self.pos += 1; // skip opening quote

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '"') {
                self.pos += 1;
                return .{
                    .tag = .string,
                    .start = start,
                    .len = @intCast(self.pos - start),
                };
            }
            if (c == '\\' and self.pos + 1 < self.source.len) {
                self.pos += 2; // skip escape sequence
            } else {
                self.pos += 1;
            }
        }

        // Unterminated string
        return .{
            .tag = .invalid,
            .start = start,
            .len = @intCast(self.pos - start),
        };
    }

    fn readIdentifier(self: *Lexer, start: u32) Token {
        self.pos += 1; // skip $
        while (self.pos < self.source.len and isIdChar(self.source[self.pos])) {
            self.pos += 1;
        }
        return .{
            .tag = .identifier,
            .start = start,
            .len = @intCast(self.pos - start),
        };
    }

    fn readNumber(self: *Lexer, start: u32) Token {
        // Skip sign if present
        if (self.source[self.pos] == '+' or self.source[self.pos] == '-') {
            self.pos += 1;
        }

        var is_float = false;

        // Check for hex prefix
        if (self.pos + 1 < self.source.len and
            self.source[self.pos] == '0' and
            (self.source[self.pos + 1] == 'x' or self.source[self.pos + 1] == 'X'))
        {
            self.pos += 2;
            while (self.pos < self.source.len and isHexDigit(self.source[self.pos])) {
                self.pos += 1;
            }
        } else {
            // Decimal
            while (self.pos < self.source.len and (isDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
                self.pos += 1;
            }

            // Decimal point
            if (self.pos < self.source.len and self.source[self.pos] == '.') {
                is_float = true;
                self.pos += 1;
                while (self.pos < self.source.len and (isDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
                    self.pos += 1;
                }
            }

            // Exponent
            if (self.pos < self.source.len and (self.source[self.pos] == 'e' or self.source[self.pos] == 'E')) {
                is_float = true;
                self.pos += 1;
                if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                    self.pos += 1;
                }
                while (self.pos < self.source.len and isDigit(self.source[self.pos])) {
                    self.pos += 1;
                }
            }
        }

        return .{
            .tag = if (is_float) .float else .integer,
            .start = start,
            .len = @intCast(self.pos - start),
        };
    }

    fn readKeyword(self: *Lexer, start: u32) Token {
        while (self.pos < self.source.len and isIdChar(self.source[self.pos])) {
            self.pos += 1;
        }
        return .{
            .tag = .keyword,
            .start = start,
            .len = @intCast(self.pos - start),
        };
    }

    fn peekNext(self: *Lexer) ?u8 {
        if (self.pos + 1 < self.source.len) {
            return self.source[self.pos + 1];
        }
        return null;
    }
};

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isHexDigit(c: u8) bool {
    return isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F') or c == '_';
}

fn isIdChar(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '/', ':', '<', '=', '>', '?', '@', '\\', '^', '_', '`', '|', '~' => true,
        else => false,
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = @import("std").testing;

test "lex empty module" {
    const source = "(module)";
    var lexer = Lexer.init(source);
    var tokens: [10]Token = undefined;

    const count = lexer.tokenize(&tokens).?;
    try testing.expectEqual(@as(usize, 4), count);
    try testing.expectEqual(Token.Tag.lparen, tokens[0].tag);
    try testing.expectEqual(Token.Tag.keyword, tokens[1].tag);
    try testing.expectEqualStrings("module", tokens[1].text(source));
    try testing.expectEqual(Token.Tag.rparen, tokens[2].tag);
    try testing.expectEqual(Token.Tag.eof, tokens[3].tag);
}

test "lex with whitespace" {
    const source = "  ( module  )  ";
    var lexer = Lexer.init(source);
    var tokens: [10]Token = undefined;

    const count = lexer.tokenize(&tokens).?;
    try testing.expectEqual(@as(usize, 4), count);
}

test "lex line comment" {
    const source = 
        \\;; this is a comment
        \\(module)
    ;
    var lexer = Lexer.init(source);
    var tokens: [10]Token = undefined;

    const count = lexer.tokenize(&tokens).?;
    try testing.expectEqual(@as(usize, 4), count);
    try testing.expectEqual(Token.Tag.lparen, tokens[0].tag);
}

test "lex block comment" {
    const source = "(; comment ;)(module)";
    var lexer = Lexer.init(source);
    var tokens: [10]Token = undefined;

    const count = lexer.tokenize(&tokens).?;
    try testing.expectEqual(@as(usize, 4), count);
}

test "lex identifier" {
    const source = "$my_func";
    var lexer = Lexer.init(source);
    var tokens: [10]Token = undefined;

    const count = lexer.tokenize(&tokens).?;
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expectEqual(Token.Tag.identifier, tokens[0].tag);
    try testing.expectEqualStrings("$my_func", tokens[0].text(source));
}

test "lex integer" {
    const source = "42 -1 0xFF";
    var lexer = Lexer.init(source);
    var tokens: [10]Token = undefined;

    const count = lexer.tokenize(&tokens).?;
    try testing.expectEqual(@as(usize, 4), count);
    try testing.expectEqual(Token.Tag.integer, tokens[0].tag);
    try testing.expectEqualStrings("42", tokens[0].text(source));
    try testing.expectEqual(Token.Tag.integer, tokens[1].tag);
    try testing.expectEqualStrings("-1", tokens[1].text(source));
    try testing.expectEqual(Token.Tag.integer, tokens[2].tag);
    try testing.expectEqualStrings("0xFF", tokens[2].text(source));
}

test "lex float" {
    const source = "3.14 1e10 2.5e-3";
    var lexer = Lexer.init(source);
    var tokens: [10]Token = undefined;

    const count = lexer.tokenize(&tokens).?;
    try testing.expectEqual(@as(usize, 4), count);
    try testing.expectEqual(Token.Tag.float, tokens[0].tag);
    try testing.expectEqual(Token.Tag.float, tokens[1].tag);
    try testing.expectEqual(Token.Tag.float, tokens[2].tag);
}

test "lex string" {
    const source = 
        \\"hello world"
    ;
    var lexer = Lexer.init(source);
    var tokens: [10]Token = undefined;

    const count = lexer.tokenize(&tokens).?;
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expectEqual(Token.Tag.string, tokens[0].tag);
    try testing.expectEqualStrings("\"hello world\"", tokens[0].text(source));
}

test "lex string with escape" {
    const source = 
        \\"hello\nworld"
    ;
    var lexer = Lexer.init(source);
    var tokens: [10]Token = undefined;

    const count = lexer.tokenize(&tokens).?;
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expectEqual(Token.Tag.string, tokens[0].tag);
}

test "buffer too small returns null" {
    const source = "(module)";
    var lexer = Lexer.init(source);
    var tokens: [2]Token = undefined;

    try testing.expectEqual(@as(?usize, null), lexer.tokenize(&tokens));
}

test "lex function with params" {
    const source = "(func (param i32 i32) (result i32))";
    var lexer = Lexer.init(source);
    var tokens: [20]Token = undefined;

    const count = lexer.tokenize(&tokens).?;
    // ( func ( param i32 i32 ) ( result i32 ) ) eof = 13 tokens
    try testing.expectEqual(@as(usize, 13), count);

    // Check some key tokens
    try testing.expectEqualStrings("func", tokens[1].text(source));
    try testing.expectEqualStrings("param", tokens[3].text(source));
    try testing.expectEqualStrings("i32", tokens[4].text(source));
    try testing.expectEqualStrings("result", tokens[8].text(source));
}

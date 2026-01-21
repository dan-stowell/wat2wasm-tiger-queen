//! LEB128 (Little Endian Base 128) encoding for WebAssembly.
//! Used for encoding integers in the WASM binary format.
//!
//! No allocation - writes directly to caller-provided buffer.

/// Encode an unsigned integer as ULEB128.
/// Returns the number of bytes written, or null if buffer too small.
pub fn encodeUnsigned(value: u64, buffer: []u8) ?usize {
    var val = value;
    var i: usize = 0;

    while (true) {
        if (i >= buffer.len) return null;

        const byte: u8 = @truncate(val & 0x7F);
        val >>= 7;

        if (val == 0) {
            buffer[i] = byte;
            return i + 1;
        } else {
            buffer[i] = byte | 0x80;
            i += 1;
        }
    }
}

/// Encode a signed integer as SLEB128.
/// Returns the number of bytes written, or null if buffer too small.
pub fn encodeSigned(value: i64, buffer: []u8) ?usize {
    var val = value;
    var i: usize = 0;

    while (true) {
        if (i >= buffer.len) return null;

        const byte: u8 = @truncate(@as(u64, @bitCast(val)) & 0x7F);
        val >>= 7;

        // Check if we're done:
        // - For negative numbers: remaining bits are all 1s and sign bit of byte is 1
        // - For non-negative: remaining bits are all 0s and sign bit of byte is 0
        const sign_bit = (byte & 0x40) != 0;
        const done = (val == 0 and !sign_bit) or (val == -1 and sign_bit);

        if (done) {
            buffer[i] = byte;
            return i + 1;
        } else {
            buffer[i] = byte | 0x80;
            i += 1;
        }
    }
}

/// Maximum bytes needed to encode a u32 in LEB128 (ceil(32/7) = 5)
pub const max_u32_bytes = 5;
/// Maximum bytes needed to encode a u64 in LEB128 (ceil(64/7) = 10)
pub const max_u64_bytes = 10;
/// Maximum bytes needed to encode an i32 in LEB128
pub const max_i32_bytes = 5;
/// Maximum bytes needed to encode an i64 in LEB128
pub const max_i64_bytes = 10;

// ============================================================================
// Tests
// ============================================================================

const testing = @import("std").testing;

test "encodeUnsigned: zero" {
    var buf: [10]u8 = undefined;
    const len = encodeUnsigned(0, &buf).?;
    try testing.expectEqual(@as(usize, 1), len);
    try testing.expectEqual(@as(u8, 0x00), buf[0]);
}

test "encodeUnsigned: single byte values" {
    var buf: [10]u8 = undefined;

    // 1
    try testing.expectEqual(@as(usize, 1), encodeUnsigned(1, &buf).?);
    try testing.expectEqual(@as(u8, 0x01), buf[0]);

    // 127 (max single byte)
    try testing.expectEqual(@as(usize, 1), encodeUnsigned(127, &buf).?);
    try testing.expectEqual(@as(u8, 0x7F), buf[0]);
}

test "encodeUnsigned: multi-byte values" {
    var buf: [10]u8 = undefined;

    // 128 = 0x80 -> 0x80 0x01
    try testing.expectEqual(@as(usize, 2), encodeUnsigned(128, &buf).?);
    try testing.expectEqual(@as(u8, 0x80), buf[0]);
    try testing.expectEqual(@as(u8, 0x01), buf[1]);

    // 624485 = 0x98765 -> 0xE5 0x8E 0x26
    try testing.expectEqual(@as(usize, 3), encodeUnsigned(624485, &buf).?);
    try testing.expectEqual(@as(u8, 0xE5), buf[0]);
    try testing.expectEqual(@as(u8, 0x8E), buf[1]);
    try testing.expectEqual(@as(u8, 0x26), buf[2]);
}

test "encodeUnsigned: buffer too small" {
    var buf: [1]u8 = undefined;
    try testing.expectEqual(@as(?usize, null), encodeUnsigned(128, &buf));
}

test "encodeSigned: zero" {
    var buf: [10]u8 = undefined;
    const len = encodeSigned(0, &buf).?;
    try testing.expectEqual(@as(usize, 1), len);
    try testing.expectEqual(@as(u8, 0x00), buf[0]);
}

test "encodeSigned: positive values" {
    var buf: [10]u8 = undefined;

    // 1
    try testing.expectEqual(@as(usize, 1), encodeSigned(1, &buf).?);
    try testing.expectEqual(@as(u8, 0x01), buf[0]);

    // 63 (max positive single byte for signed)
    try testing.expectEqual(@as(usize, 1), encodeSigned(63, &buf).?);
    try testing.expectEqual(@as(u8, 0x3F), buf[0]);

    // 64 needs two bytes (sign bit would be set otherwise)
    try testing.expectEqual(@as(usize, 2), encodeSigned(64, &buf).?);
    try testing.expectEqual(@as(u8, 0xC0), buf[0]);
    try testing.expectEqual(@as(u8, 0x00), buf[1]);
}

test "encodeSigned: negative values" {
    var buf: [10]u8 = undefined;

    // -1
    try testing.expectEqual(@as(usize, 1), encodeSigned(-1, &buf).?);
    try testing.expectEqual(@as(u8, 0x7F), buf[0]);

    // -64 (min negative single byte)
    try testing.expectEqual(@as(usize, 1), encodeSigned(-64, &buf).?);
    try testing.expectEqual(@as(u8, 0x40), buf[0]);

    // -65 needs two bytes
    try testing.expectEqual(@as(usize, 2), encodeSigned(-65, &buf).?);
    try testing.expectEqual(@as(u8, 0xBF), buf[0]);
    try testing.expectEqual(@as(u8, 0x7F), buf[1]);

    // -123456 -> 0xC0 0xBB 0x78
    try testing.expectEqual(@as(usize, 3), encodeSigned(-123456, &buf).?);
    try testing.expectEqual(@as(u8, 0xC0), buf[0]);
    try testing.expectEqual(@as(u8, 0xBB), buf[1]);
    try testing.expectEqual(@as(u8, 0x78), buf[2]);
}

test "encodeSigned: buffer too small" {
    var buf: [1]u8 = undefined;
    try testing.expectEqual(@as(?usize, null), encodeSigned(64, &buf));
}

//! AST (Abstract Syntax Tree) definitions for WAT.
//!
//! The AST is stored as a flat array of nodes using indices instead of pointers.
//! This makes it suitable for bounded memory and eventual WASM self-hosting.

/// A node in the AST. Uses indices to reference children/siblings.
pub const Node = struct {
    tag: Tag,
    /// Index of first child node (0 = none)
    first_child: u32,
    /// Index of next sibling node (0 = none)
    next_sibling: u32,
    /// Token index that this node was derived from
    token_idx: u32,

    pub const Tag = enum {
        /// Root module node
        module,
        /// Function definition: (func ...)
        func,
        /// Type definition: (type ...)
        @"type",
        /// Function type: (func (param ...) (result ...))
        func_type,
        /// Parameter: (param type) or (param $name type)
        param,
        /// Result: (result type)
        result,
        /// Local variable: (local type) or (local $name type)
        local,
        /// Export: (export "name" (func $ref))
        @"export",
        /// Import: (import "mod" "name" ...)
        import,
        /// Memory definition: (memory ...)
        memory,
        /// Global definition: (global ...)
        global,
        /// Data segment: (data ...)
        data,
        /// Table definition: (table ...)
        table,
        /// Element segment: (elem ...)
        elem,
        /// Start function: (start $func)
        start,
        /// Block: (block ...)
        block,
        /// Loop: (loop ...)
        loop,
        /// If: (if ...)
        @"if",
        /// Then branch (implicit in folded form)
        then,
        /// Else branch
        @"else",
        /// An instruction (opcode in data)
        instruction,
        /// A type use: (type $idx)
        type_use,
        /// Export descriptor: (func $ref), (memory idx), etc.
        export_desc,
        /// Import descriptor
        import_desc,
        /// Inline export on func/memory/etc
        inline_export,
        /// A value type (i32, i64, f32, f64)
        val_type,
        /// An integer literal
        integer,
        /// A float literal
        float,
        /// A string literal
        string,
        /// An identifier ($name)
        identifier,
        /// Limits (for memory/table): min or min max
        limits,
    };

    /// Sentinel value meaning "no node"
    pub const none: u32 = 0;
};

/// Iterator for traversing children of a node
pub const ChildIterator = struct {
    nodes: []const Node,
    current: u32,

    pub fn next(self: *ChildIterator) ?*const Node {
        if (self.current == Node.none) return null;
        const node = &self.nodes[self.current];
        self.current = node.next_sibling;
        return node;
    }
};

/// Get an iterator over a node's children
pub fn children(nodes: []const Node, node: *const Node) ChildIterator {
    return .{
        .nodes = nodes,
        .current = node.first_child,
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = @import("std").testing;

test "Node size is compact" {
    // 4 bytes tag + 4 bytes first_child + 4 bytes next_sibling + 4 bytes token_idx = 16
    try testing.expect(@sizeOf(Node) <= 16);
}

test "ChildIterator traverses siblings" {
    var nodes = [_]Node{
        .{ .tag = .module, .first_child = 1, .next_sibling = 0, .token_idx = 0 },
        .{ .tag = .func, .first_child = 0, .next_sibling = 2, .token_idx = 1 },
        .{ .tag = .func, .first_child = 0, .next_sibling = 0, .token_idx = 2 },
    };

    var iter = children(&nodes, &nodes[0]);

    const first = iter.next().?;
    try testing.expectEqual(Node.Tag.func, first.tag);

    const second = iter.next().?;
    try testing.expectEqual(Node.Tag.func, second.tag);

    try testing.expectEqual(@as(?*const Node, null), iter.next());
}

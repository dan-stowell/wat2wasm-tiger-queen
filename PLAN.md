# wat2wasm in Zig — Implementation Plan

## Goal
A `wat2wasm` compiler with explicit memory regions at each stage. No implicit heap allocation. Designed for eventual self-hosting as a WebAssembly module.

## Core Constraint
Each compilation stage:
- Reads from a **defined input region**
- Writes to a **defined output region**
- Uses only **bounded scratch space** (if any)

This maps cleanly to WebAssembly's linear memory model.

---

## Memory Layout (Conceptual)

```
┌─────────────────────────────────────────────────────────────┐
│  Source Buffer (input .wat text)                            │
├─────────────────────────────────────────────────────────────┤
│  Token Buffer (lexer output)                                │
├─────────────────────────────────────────────────────────────┤
│  AST Buffer (parser output)                                 │
├─────────────────────────────────────────────────────────────┤
│  Symbol Table (names → indices)                             │
├─────────────────────────────────────────────────────────────┤
│  Output Buffer (final .wasm binary)                         │
└─────────────────────────────────────────────────────────────┘
```

Each region is a contiguous slice with a known maximum size.

---

## Pipeline Stages

### Stage 1: Lexer
**Input:** Source text (UTF-8 bytes)  
**Output:** Token array

```zig
const Token = struct {
    tag: TokenTag,      // keyword, number, string, lparen, rparen, identifier, etc.
    start: u32,         // byte offset into source
    len: u16,           // byte length
};
```

Tokens reference the source by offset — no string copies.

**Implementation:**
- Single-pass, character-at-a-time
- No lookahead beyond 1 character
- Bounded output: `max_tokens` parameter

### Stage 2: Parser
**Input:** Token array + source text (for string content)  
**Output:** AST in a flat buffer

The AST is stored as a **flat array of nodes** (not a pointer-based tree):

```zig
const AstNode = struct {
    tag: NodeTag,           // module, func, param, instruction, etc.
    data: NodeData,         // union of payload types
    first_child: u32,       // index of first child (or 0 = none)
    next_sibling: u32,      // index of next sibling (or 0 = none)
};
```

This "arena-style AST" is common in production compilers (Zig, Rust) and perfect for our constraints.

**Implementation:**
- Recursive descent parser
- S-expression grammar is simple: `(keyword ...children...)`
- Build nodes in pre-order, patch sibling links on close

### Stage 3: Name Resolution
**Input:** AST buffer  
**Output:** AST buffer (in-place modification) + Symbol Table

Resolves `$name` references to numeric indices:
- Function names → function indices
- Local names → local indices
- Type names → type indices
- Label names → label depth

**Symbol Table:**
```zig
const Symbol = struct {
    name_start: u32,    // offset into source
    name_len: u16,
    index: u32,         // resolved numeric index
    kind: SymbolKind,   // func, local, type, label, etc.
};
```

### Stage 4: Binary Encoder
**Input:** AST buffer + Symbol Table  
**Output:** WASM binary

WASM binary format is straightforward:
1. Magic number: `\0asm`
2. Version: `01 00 00 00`
3. Sections in order (each optional):
   - Type section (1)
   - Import section (2)
   - Function section (3)
   - Table section (4)
   - Memory section (5)
   - Global section (6)
   - Export section (7)
   - Start section (8)
   - Element section (9)
   - Code section (10)
   - Data section (11)

**Key encoding details:**
- Integers use **LEB128** (variable-length encoding)
- Sections have: `id (1 byte) | size (LEB128) | content`
- Instructions are single-byte opcodes, some with immediates

---

## File Structure

```
src/
├── main.zig           # CLI entry point
├── lexer.zig          # Stage 1: tokenization
├── parser.zig         # Stage 2: AST construction
├── resolver.zig       # Stage 3: name resolution
├── encoder.zig        # Stage 4: binary emission
├── ast.zig            # AST node definitions
├── token.zig          # Token definitions
├── wasm.zig           # WASM binary format constants
├── leb128.zig         # LEB128 encoding utilities
└── memory.zig         # Buffer/region management
```

---

## Implementation Order

### Phase 1: Minimal Pipeline (MVP)
Get a trivial module working end-to-end:

```wat
(module)
```
→ produces valid empty WASM binary

1. `leb128.zig` — encode/decode LEB128
2. `wasm.zig` — WASM constants (opcodes, section IDs)
3. `token.zig` — token types
4. `lexer.zig` — tokenize `(module)`
5. `ast.zig` — AST node types
6. `parser.zig` — parse `(module)`
7. `encoder.zig` — emit empty module
8. `main.zig` — wire it together

### Phase 2: Functions with Instructions
Support basic functions:

```wat
(module
  (func (export "add") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.add))
```

1. Extend lexer for keywords, numbers
2. Extend parser for func, param, result, export
3. Add instruction parsing
4. Implement type section encoding
5. Implement function section encoding
6. Implement export section encoding
7. Implement code section encoding

### Phase 3: Full WAT Support
- Memory and data sections
- Globals
- Tables and element sections
- Imports
- Named references (`$name` syntax)
- Block/loop/if control flow
- All MVP instructions

### Phase 4: Self-Hosting Preparation
- Ensure all code avoids stdlib allocators
- Create a "freestanding" build target
- Compile to WASM, test in browser/runtime

---

## Memory Management Strategy

### Option A: Static Buffers (Simplest)
```zig
var token_buffer: [MAX_TOKENS]Token = undefined;
var ast_buffer: [MAX_NODES]AstNode = undefined;
var output_buffer: [MAX_OUTPUT]u8 = undefined;
```

Pros: Zero allocation, predictable  
Cons: Fixed limits, wastes memory for small inputs

### Option B: Caller-Provided Slices (Flexible)
```zig
pub fn lex(source: []const u8, tokens: []Token) LexResult {
    // ...
}
```

Caller decides buffer sizes. Functions return how much was used.

### Option C: Linear Allocator (Most Realistic)
```zig
const LinearAllocator = struct {
    buffer: []u8,
    offset: usize,
    
    pub fn alloc(self: *@This(), comptime T: type, n: usize) ?[]T {
        // bump allocator, no free
    }
};
```

Mimics WebAssembly linear memory. Can reset between stages.

**Recommendation:** Start with **Option B** for flexibility, design for **Option C** compatibility.

---

## Error Handling

Errors are values, not exceptions:

```zig
const LexError = struct {
    location: u32,      // byte offset
    kind: ErrorKind,    // unexpected_char, unterminated_string, etc.
};

const LexResult = union(enum) {
    ok: struct { tokens: []Token, count: u32 },
    err: LexError,
};
```

All stages return result types. No panics in library code.

---

## Testing Strategy

1. **Unit tests per stage** — test lexer, parser, encoder independently
2. **Round-trip tests** — our output validates against `wasm-validate`
3. **Comparison tests** — compare against `wat2wasm` from wabt
4. **Fuzz testing** — generate random valid WAT, ensure we don't crash

---

## Open Questions

1. **How large should default buffers be?**  
   Start with limits suitable for hand-written modules (e.g., 64KB source, 4K tokens, 4K AST nodes).

2. **Support WAT abbreviations?**  
   WAT has shorthand forms. MVP: require explicit form. Later: support abbreviations.

3. **Error messages — how detailed?**  
   MVP: byte offset + error code. Later: line/column, context.

4. **Multi-memory / other proposals?**  
   MVP: WebAssembly 1.0 only. Later: post-MVP features.

---

## Next Step

Start with Phase 1: implement `leb128.zig` and `wasm.zig`, then build the lexer.

Ready to begin?

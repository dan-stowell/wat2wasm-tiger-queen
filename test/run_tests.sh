#!/bin/bash
# End-to-end tests for wat2wasm
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WAT2WASM="$PROJECT_DIR/zig-out/bin/wat2wasm"
TMP_DIR=$(mktemp -d)

trap "rm -rf $TMP_DIR" EXIT

pass=0
fail=0

run_test() {
    local name=$1
    local wat_file=$2
    
    local out_wasm="$TMP_DIR/${name}.wasm"
    
    echo -n "Testing $name... "
    
    if ! "$WAT2WASM" "$wat_file" -o "$out_wasm" 2>/dev/null; then
        echo "FAIL (wat2wasm failed)"
        fail=$((fail + 1))
        return
    fi
    
    if ! wasm-validate "$out_wasm" 2>/dev/null; then
        echo "FAIL (invalid wasm)"
        fail=$((fail + 1))
        return
    fi
    
    echo "OK"
    pass=$((pass + 1))
}

# Build first
echo "Building wat2wasm..."
(cd "$PROJECT_DIR" && zig build)

echo
echo "Running tests..."
echo

run_test "empty" "$SCRIPT_DIR/empty.wat"

echo
echo "Results: $pass passed, $fail failed"

[ $fail -eq 0 ]

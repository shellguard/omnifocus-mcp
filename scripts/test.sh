#!/bin/bash
# test.sh — integration tests for the omnifocus-mcp MCP server
#
# Tests protocol compliance and key behaviours without requiring OmniFocus.
# Each test pipes one or more JSON-RPC messages to the binary and inspects stdout.
#
# Usage:
#   ./scripts/test.sh            # build then test
#   ./scripts/test.sh --no-build # skip build, use existing binary

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
BINARY="$ROOT_DIR/.build/release/omnifocus-mcp"
NO_BUILD=false
PASS=0
FAIL=0

# ── Argument parsing ──────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --no-build) NO_BUILD=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# ── Colours ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

pass() { printf "${GREEN}PASS${NC} %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "${RED}FAIL${NC} %s\n  => %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
skip() { printf "${YELLOW}SKIP${NC} %s\n" "$1"; }
header() { printf "\n${BOLD}%s${NC}\n" "$1"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

# Send one JSON-RPC line to the binary; capture stdout (stderr discarded)
rpc() {
  printf '%s\n' "$1" | OF_BACKEND=jxa "$BINARY" 2>/dev/null
}

# Assert that output contains a substring
assert_contains() {
  local label="$1" output="$2" needle="$3"
  if printf '%s' "$output" | grep -qF -- "$needle"; then
    pass "$label"
  else
    fail "$label" "expected to find: $needle"
    printf '    output: %s\n' "$output"
  fi
}

# Assert that output does NOT contain a substring
assert_not_contains() {
  local label="$1" output="$2" needle="$3"
  if printf '%s' "$output" | grep -qF -- "$needle"; then
    fail "$label" "expected NOT to find: $needle"
    printf '    output: %s\n' "$output"
  else
    pass "$label"
  fi
}

# Extract a value from JSON output using jq (if available) or grep+sed
json_get() {
  local json="$1" key="$2"
  if command -v jq > /dev/null 2>&1; then
    printf '%s' "$json" | jq -r "$key" 2>/dev/null
  else
    # naive grep fallback — good enough for simple string values
    printf '%s' "$json" | grep -oE "\"${key#.}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | sed 's/.*: *"//' | tr -d '"'
  fi
}

# ── Build ─────────────────────────────────────────────────────────────────────
if [ "$NO_BUILD" = false ]; then
  printf "==> Building omnifocus-mcp (release)...\n"
  swift build -c release --quiet
  printf "    done.\n"
fi

if [ ! -x "$BINARY" ]; then
  printf "${RED}ERROR${NC}: binary not found at %s\n" "$BINARY" >&2
  exit 1
fi

# ── Test suite ────────────────────────────────────────────────────────────────

# ─── 1. initialize ────────────────────────────────────────────────────────────
header "1. initialize"

INIT_MSG='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"test","version":"0"}}}'
INIT_OUT=$(rpc "$INIT_MSG")

assert_contains "returns jsonrpc 2.0"         "$INIT_OUT" '"jsonrpc":"2.0"'
assert_contains "returns id 1"                "$INIT_OUT" '"id":1'
assert_contains "has result field"            "$INIT_OUT" '"result"'
assert_contains "protocolVersion 2024-11-05"  "$INIT_OUT" '"protocolVersion":"2024-11-05"'
assert_contains "serverInfo name"             "$INIT_OUT" '"name":"omnifocus-mcp"'
assert_contains "serverInfo version is 0.2.0" "$INIT_OUT" '"version":"0.2.0"'
assert_not_contains "no error field"          "$INIT_OUT" '"error"'

# ─── 2. tools/list ────────────────────────────────────────────────────────────
header "2. tools/list"

LIST_MSG='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
LIST_OUT=$(rpc "$LIST_MSG")

assert_contains "returns result"         "$LIST_OUT" '"result"'
assert_contains "has tools array"        "$LIST_OUT" '"tools"'
assert_not_contains "no error"           "$LIST_OUT" '"error"'

# Count tool entries by counting name occurrences
TOOL_COUNT=$(printf '%s' "$LIST_OUT" | grep -oF '"name":"omnifocus_' | wc -l | tr -d ' ')
if [ "$TOOL_COUNT" -eq 51 ]; then
  pass "exactly 51 tools returned (got $TOOL_COUNT)"
else
  fail "tool count" "expected 51, got $TOOL_COUNT"
fi

# Spot-check a selection of tools are present
for tool in \
  omnifocus_list_tasks omnifocus_create_task omnifocus_update_task \
  omnifocus_complete_task omnifocus_delete_task \
  omnifocus_list_projects omnifocus_create_project \
  omnifocus_list_inbox omnifocus_process_inbox \
  omnifocus_get_task_counts omnifocus_get_project_counts omnifocus_get_forecast \
  omnifocus_create_tasks_batch omnifocus_delete_tasks_batch omnifocus_move_tasks_batch \
  omnifocus_uncomplete_task omnifocus_uncomplete_project \
  omnifocus_set_project_status omnifocus_append_to_note \
  omnifocus_get_folder omnifocus_update_folder omnifocus_delete_folder \
  omnifocus_create_subtask omnifocus_duplicate_task \
  omnifocus_list_notifications omnifocus_add_notification omnifocus_remove_notification \
  omnifocus_set_task_repetition omnifocus_eval_automation; do
  assert_contains "tool present: $tool" "$LIST_OUT" "\"$tool\""
done

# ─── 3. Tool description content ──────────────────────────────────────────────
header "3. Tool descriptions"

assert_contains "eval_automation has security warning" \
  "$LIST_OUT" "WARNING"

assert_contains "delete_folder warns about cascade" \
  "$LIST_OUT" "irreversibly deletes the folder and ALL"

# ─── 4. tools/call — error cases (no OmniFocus needed) ───────────────────────
header "4. tools/call error handling"

# Unknown tool
UNKNOWN_OUT=$(rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"omnifocus_nonexistent","arguments":{}}}')
assert_contains "unknown tool returns error"       "$UNKNOWN_OUT" '"error"'
assert_contains "unknown tool code -32602"         "$UNKNOWN_OUT" '-32602'
assert_not_contains "unknown tool has no result"   "$UNKNOWN_OUT" '"result"'

# Missing tool name in params
MISSING_NAME_OUT=$(rpc '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{}}')
assert_contains "missing tool name returns error"  "$MISSING_NAME_OUT" '"error"'
assert_contains "missing tool name code -32602"    "$MISSING_NAME_OUT" '-32602'

# ─── 5. JSON-RPC error protocol ───────────────────────────────────────────────
header "5. JSON-RPC protocol errors"

# Unknown method
UNKNOWN_METHOD_OUT=$(rpc '{"jsonrpc":"2.0","id":5,"method":"no/such/method","params":{}}')
assert_contains "unknown method returns error" "$UNKNOWN_METHOD_OUT" '"error"'
assert_contains "unknown method code -32601"   "$UNKNOWN_METHOD_OUT" '-32601'

# Parse error (malformed JSON)
PARSE_ERR_OUT=$(printf 'not json at all\n' | OF_BACKEND=jxa "$BINARY" 2>/dev/null)
assert_contains "malformed JSON returns parse error" "$PARSE_ERR_OUT" '-32700'

# Not an object (array is valid JSON but not a JSON-RPC object → -32600)
NOT_OBJ_OUT=$(rpc '[1,2,3]')
assert_contains "non-object returns invalid request" "$NOT_OBJ_OUT" '-32600'

# ─── 6. tools/call response format (MCP spec compliance) ─────────────────────
header "6. tools/call response format"

# notifications/initialized is a no-op, use it to test basic notification flow;
# instead call a tool that will fail with a script error (OmniFocus absent) —
# the response still exercises the content-formatting path.
# We verify the content type field using a tool that always errors gracefully.
CALL_OUT=$(rpc '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"omnifocus_list_tasks","arguments":{}}}' 2>/dev/null || true)

if printf '%s' "$CALL_OUT" | grep -qF '"type":"text"'; then
  pass "tools/call content uses type:text"
elif printf '%s' "$CALL_OUT" | grep -qF '"error"'; then
  # Script failed (OmniFocus not running), but check it didn't use the old type
  assert_not_contains "no legacy type:json in error path" "$CALL_OUT" '"type":"json"'
  skip "tools/call content format (OmniFocus not running — cannot verify text content)"
else
  fail "tools/call content format" "expected type:text or error, got: $CALL_OUT"
fi

# ─── 7. initialized / shutdown notifications (no response expected) ───────────
header "7. Notification messages (no response)"

# These must produce no output
NOTIF_OUT=$(printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  '{"jsonrpc":"2.0","method":"shutdown"}' \
  | OF_BACKEND=jxa "$BINARY" 2>/dev/null)

if [ -z "$NOTIF_OUT" ]; then
  pass "initialized/shutdown produce no response"
else
  fail "initialized/shutdown should produce no response" "got: $NOTIF_OUT"
fi

# ─── 8. OF_APP_PATH injection guard ──────────────────────────────────────────
header "8. OF_APP_PATH injection guard"

INJECT_OUT=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"omnifocus_list_tasks","arguments":{}}}' \
  | OF_BACKEND=automation OF_APP_PATH='/Applications/OmniFocus.app"; do shell script "id"' \
    "$BINARY" 2>/dev/null || true)

assert_contains "unsafe OF_APP_PATH is rejected" "$INJECT_OUT" '"error"'
assert_contains "error mentions unsafe characters" "$INJECT_OUT" "unsafe characters"

# ─── Summary ──────────────────────────────────────────────────────────────────
printf "\n${BOLD}Results: %d passed, %d failed${NC}\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

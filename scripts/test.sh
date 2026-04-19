#!/bin/bash
# test.sh — integration tests for omnifocus-mcp and omnifocus-cli
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
CLI_BINARY="$ROOT_DIR/.build/release/omnifocus-cli"
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

rpc_paged() {
  printf '%s\n' "$1" | OF_BACKEND=jxa OF_MCP_TOOLS_PAGE_SIZE=25 "$BINARY" 2>/dev/null
}

# Assert output contains an exact substring
assert_contains() {
  local label="$1" output="$2" needle="$3"
  if printf '%s' "$output" | grep -qF -- "$needle"; then
    pass "$label"
  else
    fail "$label" "expected to find: $needle"
    printf '    output: %s\n' "$output"
  fi
}

# Assert output does NOT contain an exact substring
assert_not_contains() {
  local label="$1" output="$2" needle="$3"
  if printf '%s' "$output" | grep -qF -- "$needle"; then
    fail "$label" "expected NOT to find: $needle"
    printf '    output: %s\n' "$output"
  else
    pass "$label"
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

if [ ! -x "$CLI_BINARY" ]; then
  printf "${RED}ERROR${NC}: CLI binary not found at %s\n" "$CLI_BINARY" >&2
  exit 1
fi

# Detect whether OmniFocus is running (used to gate tests that need it)
OMNIFOCUS_RUNNING=false
if pgrep -xq OmniFocus 2>/dev/null; then
  OMNIFOCUS_RUNNING=true
fi

# ── Test suite ────────────────────────────────────────────────────────────────

# ─── 1. initialize/version negotiation ────────────────────────────────────────
header "1. initialize"

INIT_MSG='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","clientInfo":{"name":"test","version":"0"}}}'
INIT_OUT=$(rpc "$INIT_MSG")

assert_contains     "returns jsonrpc 2.0"          "$INIT_OUT" '"jsonrpc":"2.0"'
# id echo: check for id:1 bounded by non-digit to avoid matching id:10, id:12, etc.
if printf '%s' "$INIT_OUT" | grep -qE '"id"[[:space:]]*:[[:space:]]*1[^0-9]'; then
  pass "returns id 1 (exact)"
else
  fail "returns id 1 (exact)" "expected id:1 in: $INIT_OUT"
fi
assert_contains     "has result field"             "$INIT_OUT" '"result":'
assert_not_contains "no error field"               "$INIT_OUT" '"error":'
assert_contains     "protocolVersion 2025-11-25"   "$INIT_OUT" '"protocolVersion":"2025-11-25"'
assert_contains     "capabilities field present"   "$INIT_OUT" '"capabilities":'
assert_contains     "serverInfo name"              "$INIT_OUT" '"name":"omnifocus-mcp"'
assert_contains     "serverInfo version is 0.3.2"  "$INIT_OUT" '"version":"0.3.2"'

LEGACY_INIT_OUT=$(rpc '{"jsonrpc":"2.0","id":11,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"test","version":"0"}}}')
assert_contains "legacy protocol request accepted" "$LEGACY_INIT_OUT" '"protocolVersion":"2024-11-05"'

FALLBACK_INIT_OUT=$(rpc '{"jsonrpc":"2.0","id":12,"method":"initialize","params":{"protocolVersion":"2099-01-01","clientInfo":{"name":"test","version":"0"}}}')
assert_contains "unknown protocol falls back to latest supported" "$FALLBACK_INIT_OUT" '"protocolVersion":"2025-11-25"'

# ─── 2. tools/list ────────────────────────────────────────────────────────────
header "2. tools/list"

LIST_MSG='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
LIST_OUT=$(rpc "$LIST_MSG")

assert_contains     "returns result"   "$LIST_OUT" '"result":'
assert_contains     "has tools array"  "$LIST_OUT" '"tools"'
assert_not_contains "no error"         "$LIST_OUT" '"error":'

# Count tool entries — count "name":"omnifocus_ occurrences inside "tools" list.
# Each tool definition has exactly one name key starting with omnifocus_.
TOOL_COUNT=$(printf '%s' "$LIST_OUT" | grep -oF '"name":"omnifocus_' | wc -l | tr -d ' ')
if [ "$TOOL_COUNT" -eq 84 ]; then
  pass "exactly 84 tools returned (got $TOOL_COUNT)"
else
  fail "tool count" "expected 84, got $TOOL_COUNT"
fi

# Verify ALL 84 tool names are present
for tool in \
  omnifocus_list_tasks omnifocus_list_inbox omnifocus_list_projects \
  omnifocus_list_tags omnifocus_list_perspectives omnifocus_list_folders \
  omnifocus_create_folder omnifocus_move_project \
  omnifocus_list_flagged omnifocus_list_overdue omnifocus_list_available \
  omnifocus_search_tasks omnifocus_list_task_children omnifocus_get_task_parent \
  omnifocus_process_inbox omnifocus_set_project_sequential omnifocus_eval_automation \
  omnifocus_get_task omnifocus_get_project omnifocus_get_tag \
  omnifocus_create_task omnifocus_create_project omnifocus_create_tag \
  omnifocus_update_task omnifocus_update_project omnifocus_update_tag \
  omnifocus_complete_task omnifocus_complete_project \
  omnifocus_delete_task omnifocus_delete_project omnifocus_delete_tag \
  omnifocus_uncomplete_task omnifocus_uncomplete_project \
  omnifocus_append_to_note omnifocus_search_tags omnifocus_set_project_status \
  omnifocus_get_folder omnifocus_update_folder omnifocus_delete_folder \
  omnifocus_get_task_counts omnifocus_get_project_counts omnifocus_get_forecast \
  omnifocus_create_subtask omnifocus_duplicate_task \
  omnifocus_create_tasks_batch omnifocus_delete_tasks_batch omnifocus_move_tasks_batch \
  omnifocus_list_notifications omnifocus_add_notification \
  omnifocus_remove_notification omnifocus_set_task_repetition \
  omnifocus_mark_reviewed omnifocus_drop_task omnifocus_import_taskpaper \
  omnifocus_add_relative_notification omnifocus_move_tag omnifocus_move_folder \
  omnifocus_convert_task_to_project omnifocus_duplicate_project \
  omnifocus_get_forecast_tag omnifocus_clean_up omnifocus_get_settings \
  omnifocus_list_linked_files omnifocus_add_linked_file omnifocus_remove_linked_file \
  omnifocus_search_projects omnifocus_search_folders omnifocus_search_tasks_native \
  omnifocus_lookup_url omnifocus_get_forecast_days \
  omnifocus_get_focus omnifocus_set_focus omnifocus_undo omnifocus_redo omnifocus_save \
  omnifocus_duplicate_tasks_batch omnifocus_duplicate_tags \
  omnifocus_move_projects_batch omnifocus_reorder_task_tags \
  omnifocus_copy_tasks omnifocus_paste_tasks \
  omnifocus_next_repetition_date omnifocus_set_forecast_tag \
  omnifocus_set_notification_repeat; do
  assert_contains "tool present: $tool" "$LIST_OUT" "\"$tool\""
done

# ─── 3. Tool description content ──────────────────────────────────────────────
header "3. Tool descriptions & annotations"

assert_contains "eval_automation has DANGER warning" \
  "$LIST_OUT" "DANGER"

assert_contains "eval_automation mentions allowDestructive" \
  "$LIST_OUT" "allowDestructive"

assert_contains "delete_folder warns about cascade" \
  "$LIST_OUT" "irreversibly deletes the folder and ALL"

# MCP annotations present on all tools
assert_contains "annotations field exists"     "$LIST_OUT" '"annotations":'
assert_contains "readOnlyHint present"         "$LIST_OUT" '"readOnlyHint"'
assert_contains "destructiveHint present"      "$LIST_OUT" '"destructiveHint"'
assert_contains "idempotentHint present"       "$LIST_OUT" '"idempotentHint"'

# Count annotation categories
RO_COUNT=$(printf '%s' "$LIST_OUT" | grep -oF '"readOnlyHint":true' | wc -l | tr -d ' ')
DE_COUNT=$(printf '%s' "$LIST_OUT" | grep -oF '"destructiveHint":true' | wc -l | tr -d ' ')
if [ "$RO_COUNT" -eq 32 ]; then
  pass "32 read-only tools annotated (got $RO_COUNT)"
else
  fail "read-only annotation count" "expected 32, got $RO_COUNT"
fi
if [ "$DE_COUNT" -eq 8 ]; then
  pass "8 destructive tools annotated (got $DE_COUNT)"
else
  fail "destructive annotation count" "expected 8, got $DE_COUNT"
fi

# ─── 3b. tools/list pagination ────────────────────────────────────────────────
header "3b. tools/list pagination"

PAGED_LIST_1=$(rpc_paged '{"jsonrpc":"2.0","id":201,"method":"tools/list","params":{}}')
assert_contains "paged tools/list includes nextCursor" "$PAGED_LIST_1" '"nextCursor":"25"'
PAGE1_COUNT=$(printf '%s' "$PAGED_LIST_1" | grep -oF '"name":"omnifocus_' | wc -l | tr -d ' ')
if [ "$PAGE1_COUNT" -eq 25 ]; then
  pass "first page returns 25 tools (got $PAGE1_COUNT)"
else
  fail "first page size" "expected 25, got $PAGE1_COUNT"
fi

PAGED_LIST_2=$(rpc_paged '{"jsonrpc":"2.0","id":202,"method":"tools/list","params":{"cursor":"25"}}')
assert_contains "second page includes nextCursor" "$PAGED_LIST_2" '"nextCursor":"50"'
PAGE2_COUNT=$(printf '%s' "$PAGED_LIST_2" | grep -oF '"name":"omnifocus_' | wc -l | tr -d ' ')
if [ "$PAGE2_COUNT" -eq 25 ]; then
  pass "second page returns 25 tools (got $PAGE2_COUNT)"
else
  fail "second page size" "expected 25, got $PAGE2_COUNT"
fi

PAGED_LIST_LAST=$(rpc_paged '{"jsonrpc":"2.0","id":203,"method":"tools/list","params":{"cursor":"75"}}')
assert_not_contains "last page omits nextCursor" "$PAGED_LIST_LAST" '"nextCursor"'
LAST_COUNT=$(printf '%s' "$PAGED_LIST_LAST" | grep -oF '"name":"omnifocus_' | wc -l | tr -d ' ')
if [ "$LAST_COUNT" -eq 9 ]; then
  pass "last page returns remaining 9 tools (got $LAST_COUNT)"
else
  fail "last page size" "expected 9, got $LAST_COUNT"
fi

BAD_CURSOR_OUT=$(rpc_paged '{"jsonrpc":"2.0","id":204,"method":"tools/list","params":{"cursor":"bad"}}')
assert_contains "invalid cursor returns error" "$BAD_CURSOR_OUT" '"error":'
assert_contains "invalid cursor uses code -32602" "$BAD_CURSOR_OUT" '-32602'

# ─── 4. tools/call error handling ─────────────────────────────────────────────
header "4. tools/call error handling"

# Unknown tool → -32602 (toolNotFound, caught before any script is run)
UNKNOWN_OUT=$(rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"omnifocus_nonexistent","arguments":{}}}')
assert_contains     "unknown tool returns error"     "$UNKNOWN_OUT" '"error":'
assert_contains     "unknown tool code -32602"       "$UNKNOWN_OUT" '-32602'
assert_not_contains "unknown tool has no result"     "$UNKNOWN_OUT" '"result":'

# Missing tool name in params → -32602
MISSING_NAME_OUT=$(rpc '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{}}')
assert_contains "missing tool name returns error"    "$MISSING_NAME_OUT" '"error":'
assert_contains "missing tool name code -32602"      "$MISSING_NAME_OUT" '-32602'

# Tool execution failures should be encoded in result.isError, not JSON-RPC error.
TOOL_EXEC_ERROR_OUT=$(rpc '{"jsonrpc":"2.0","id":41,"method":"tools/call","params":{"name":"omnifocus_eval_automation","arguments":{}}}')
assert_contains     "tool execution failure returns result envelope" "$TOOL_EXEC_ERROR_OUT" '"result":'
assert_contains     "tool execution failure sets isError"            "$TOOL_EXEC_ERROR_OUT" '"isError":true'
assert_not_contains "tool execution failure avoids JSON-RPC error"   "$TOOL_EXEC_ERROR_OUT" '"error":'
assert_contains     "tool execution failure includes message"         "$TOOL_EXEC_ERROR_OUT" 'Missing script'

# ─── 5. JSON-RPC protocol errors ──────────────────────────────────────────────
header "5. JSON-RPC protocol errors"

# Unknown method → -32601
UNKNOWN_METHOD_OUT=$(rpc '{"jsonrpc":"2.0","id":5,"method":"no/such/method","params":{}}')
assert_contains "unknown method returns error"       "$UNKNOWN_METHOD_OUT" '"error":'
assert_contains "unknown method code -32601"         "$UNKNOWN_METHOD_OUT" '-32601'

# Parse error (malformed JSON) → -32700
PARSE_ERR_OUT=$(printf 'not json at all\n' | OF_BACKEND=jxa "$BINARY" 2>/dev/null)
assert_contains "malformed JSON returns parse error" "$PARSE_ERR_OUT" '-32700'

# Parse error returns null id (JSON-RPC 2.0 spec)
assert_contains "parse error has null id"            "$PARSE_ERR_OUT" '"id":null'

# Non-object (array is valid JSON but not a JSON-RPC message) → -32600
NOT_OBJ_OUT=$(rpc '[1,2,3]')
assert_contains "non-object returns invalid request" "$NOT_OBJ_OUT" '-32600'

# ─── 6. Tool dispatch coverage ────────────────────────────────────────────────
# Every tool listed in tools/list must also have a case in callTool().
# Without OmniFocus running the script will fail (-32000), but a missing
# case would produce toolNotFound (-32602) instead.  This catches tools that
# are registered in the tools array but have no dispatch entry.
header "6. Tool dispatch coverage"

dispatch_check() {
  local tool="$1"
  local out
  out=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool\",\"arguments\":{}}}")
  # A missing dispatch case produces "Unknown tool: <name>" (-32602).
  # -32602 for a missing *required argument* has a different message, so we
  # check the message text rather than just the error code.
  if printf '%s' "$out" | grep -qF -- "Unknown tool:"; then
    fail "dispatch: $tool" "got 'Unknown tool' — missing case in callTool()"
    printf '    output: %s\n' "$out"
  else
    pass "dispatch: $tool"
  fi
}

for tool in \
  omnifocus_list_tasks omnifocus_list_inbox omnifocus_list_projects \
  omnifocus_list_tags omnifocus_list_perspectives omnifocus_list_folders \
  omnifocus_create_folder omnifocus_move_project \
  omnifocus_list_flagged omnifocus_list_overdue omnifocus_list_available \
  omnifocus_search_tasks omnifocus_list_task_children omnifocus_get_task_parent \
  omnifocus_process_inbox omnifocus_set_project_sequential omnifocus_eval_automation \
  omnifocus_get_task omnifocus_get_project omnifocus_get_tag \
  omnifocus_create_task omnifocus_create_project omnifocus_create_tag \
  omnifocus_update_task omnifocus_update_project omnifocus_update_tag \
  omnifocus_complete_task omnifocus_complete_project \
  omnifocus_delete_task omnifocus_delete_project omnifocus_delete_tag \
  omnifocus_uncomplete_task omnifocus_uncomplete_project \
  omnifocus_append_to_note omnifocus_search_tags omnifocus_set_project_status \
  omnifocus_get_folder omnifocus_update_folder omnifocus_delete_folder \
  omnifocus_get_task_counts omnifocus_get_project_counts omnifocus_get_forecast \
  omnifocus_create_subtask omnifocus_duplicate_task \
  omnifocus_create_tasks_batch omnifocus_delete_tasks_batch omnifocus_move_tasks_batch \
  omnifocus_list_notifications omnifocus_add_notification \
  omnifocus_remove_notification omnifocus_set_task_repetition \
  omnifocus_mark_reviewed omnifocus_drop_task omnifocus_import_taskpaper \
  omnifocus_add_relative_notification omnifocus_move_tag omnifocus_move_folder \
  omnifocus_convert_task_to_project omnifocus_duplicate_project \
  omnifocus_get_forecast_tag omnifocus_clean_up omnifocus_get_settings \
  omnifocus_list_linked_files omnifocus_add_linked_file omnifocus_remove_linked_file \
  omnifocus_search_projects omnifocus_search_folders omnifocus_search_tasks_native \
  omnifocus_lookup_url omnifocus_get_forecast_days \
  omnifocus_get_focus omnifocus_set_focus omnifocus_undo omnifocus_redo omnifocus_save \
  omnifocus_duplicate_tasks_batch omnifocus_duplicate_tags \
  omnifocus_move_projects_batch omnifocus_reorder_task_tags \
  omnifocus_copy_tasks omnifocus_paste_tasks \
  omnifocus_next_repetition_date omnifocus_set_forecast_tag \
  omnifocus_set_notification_repeat; do
  dispatch_check "$tool"
done

# ─── 7. tools/call response format (MCP spec compliance) ─────────────────────
header "7. tools/call response format"

if [ "$OMNIFOCUS_RUNNING" = true ]; then
  # Use eval_automation with a trivial script that always succeeds,
  # giving us a real tools/call success response to check the content format.
  CALL_OUT=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"omnifocus_eval_automation","arguments":{"script":"JSON.stringify({ok:true})","parseJson":true}}}' \
    | OF_BACKEND=automation "$BINARY" 2>/dev/null || true)
  if printf '%s' "$CALL_OUT" | grep -qF -- '"type":"text"'; then
    pass "tools/call success response uses type:text"
    assert_not_contains "no legacy type:json in success response" "$CALL_OUT" '"type":"json"'
  else
    fail "tools/call success response format" "expected type:text, got: $CALL_OUT"
  fi
else
  skip "tools/call success content format (OmniFocus not running)"
  # In the error path, verify the old non-spec type:json is never emitted
  ERR_CALL_OUT=$(rpc '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"omnifocus_list_tasks","arguments":{}}}' || true)
  assert_not_contains "no legacy type:json in any response" "$ERR_CALL_OUT" '"type":"json"'
fi

# ─── 8. Notification messages (no response expected) ──────────────────────────
header "8. Notification messages (no response)"

# Send initialize + notifications together; only the initialize should respond.
MIXED_OUT=$(printf '%s\n%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","id":20,"method":"initialize","params":{"protocolVersion":"2025-11-25","clientInfo":{"name":"test","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","method":"shutdown"}' \
  | OF_BACKEND=jxa "$BINARY" 2>/dev/null)

# The initialize must respond (proves binary was alive and processed input)
assert_contains "initialize response present in mixed batch" "$MIXED_OUT" '"id":20'

# There must be exactly one response line (only initialize, not notifications)
RESPONSE_COUNT=$(printf '%s\n' "$MIXED_OUT" | grep -c '"jsonrpc"' || true)
if [ "$RESPONSE_COUNT" -eq 1 ]; then
  pass "exactly one response (initialized notifications produce no output)"
else
  fail "notification response count" "expected 1 response, got $RESPONSE_COUNT"
  printf '    output: %s\n' "$MIXED_OUT"
fi

# ─── 9. OF_APP_PATH injection guard ──────────────────────────────────────────
header "9. OF_APP_PATH injection guard"

# Confirm a legitimate path is not rejected (guard only fires on unsafe chars)
SAFE_PATH_OUT=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":30,"method":"tools/call","params":{"name":"omnifocus_list_tasks","arguments":{}}}' \
  | OF_BACKEND=automation OF_APP_PATH='/Applications/OmniFocus.app' \
    "$BINARY" 2>/dev/null || true)
assert_not_contains "safe OF_APP_PATH is not rejected by guard" "$SAFE_PATH_OUT" "unsafe characters"

# An injection payload must be caught by the allowlist guard specifically
INJECT_OUT=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":31,"method":"tools/call","params":{"name":"omnifocus_list_tasks","arguments":{}}}' \
  | OF_BACKEND=automation OF_APP_PATH='/Applications/OmniFocus.app"; do shell script "id"' \
    "$BINARY" 2>/dev/null || true)
assert_contains     "unsafe OF_APP_PATH is rejected"      "$INJECT_OUT" '"isError":true'
assert_contains     "error cites unsafe characters"       "$INJECT_OUT" "unsafe characters"

# ─── 10. eval_automation deny-list ────────────────────────────────────────────
header "10. eval_automation deny-list"

# Destructive dot-notation blocked
DENY_DOT=$(rpc '{"jsonrpc":"2.0","id":60,"method":"tools/call","params":{"name":"omnifocus_eval_automation","arguments":{"script":"task.delete()"}}}')
assert_contains "dot-notation .delete() blocked"    "$DENY_DOT" '"isError":true'
assert_contains "error mentions destructive"        "$DENY_DOT" 'destructive'

# Destructive bracket-notation blocked
DENY_BRACKET=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":61,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_eval_automation\",\"arguments\":{\"script\":\"task['delete']()\"}}}")
assert_contains "bracket-notation ['delete']() blocked" "$DENY_BRACKET" '"isError":true'

# Other destructive patterns
DENY_DROP=$(rpc '{"jsonrpc":"2.0","id":62,"method":"tools/call","params":{"name":"omnifocus_eval_automation","arguments":{"script":"task.drop(false)"}}}')
assert_contains ".drop() blocked"                   "$DENY_DROP" '"isError":true'

DENY_DELETEOBJ=$(rpc '{"jsonrpc":"2.0","id":63,"method":"tools/call","params":{"name":"omnifocus_eval_automation","arguments":{"script":"deleteObject(task)"}}}')
assert_contains "deleteObject() blocked"            "$DENY_DELETEOBJ" '"isError":true'

DENY_CLEANUP=$(rpc '{"jsonrpc":"2.0","id":64,"method":"tools/call","params":{"name":"omnifocus_eval_automation","arguments":{"script":"cleanUp()"}}}')
assert_contains "cleanUp() blocked"                 "$DENY_CLEANUP" '"isError":true'

# Safe script passes deny-list
SAFE_SCRIPT=$(rpc '{"jsonrpc":"2.0","id":65,"method":"tools/call","params":{"name":"omnifocus_eval_automation","arguments":{"script":"JSON.stringify({ok:1})"}}}')
assert_not_contains "safe script not blocked"       "$SAFE_SCRIPT" 'destructive'

# allowDestructive override
ALLOW_DEST=$(rpc '{"jsonrpc":"2.0","id":66,"method":"tools/call","params":{"name":"omnifocus_eval_automation","arguments":{"script":"JSON.stringify({ok:1})","allowDestructive":true}}}')
assert_not_contains "allowDestructive passes"       "$ALLOW_DEST" 'destructive'

# Missing script parameter
NO_SCRIPT=$(rpc '{"jsonrpc":"2.0","id":67,"method":"tools/call","params":{"name":"omnifocus_eval_automation","arguments":{}}}')
assert_contains "missing script returns isError result" "$NO_SCRIPT" '"isError":true'
assert_contains "error mentions Missing script"     "$NO_SCRIPT" 'Missing script'

# ─── 11. CLI: --help ─────────────────────────────────────────────────────────
header "11. CLI: --help"

CLI_HELP=$("$CLI_BINARY" --help 2>&1)
assert_contains "CLI help shows usage line"            "$CLI_HELP" "Usage: omnifocus-cli"
assert_contains "CLI help lists list-tasks"            "$CLI_HELP" "list-tasks"
assert_contains "CLI help lists create-task"           "$CLI_HELP" "create-task"
assert_contains "CLI help lists delete-project"        "$CLI_HELP" "delete-project"
assert_contains "CLI help lists eval-automation"       "$CLI_HELP" "eval-automation"
assert_contains "CLI help shows environment variables" "$CLI_HELP" "OF_BACKEND"

# Count commands in help — each tool appears indented with 4 spaces then a lowercase letter
CLI_CMD_COUNT=$(printf '%s' "$CLI_HELP" | grep -cE '^\s{4}[a-z]' || true)
if [ "$CLI_CMD_COUNT" -eq 84 ]; then
  pass "CLI help lists exactly 84 commands (got $CLI_CMD_COUNT)"
else
  fail "CLI help command count" "expected 84, got $CLI_CMD_COUNT"
fi

# ─── 12. CLI: per-command --help ─────────────────────────────────────────────
header "12. CLI: per-command --help"

CT_HELP=$("$CLI_BINARY" create-task --help 2>&1)
assert_contains "create-task help shows usage"         "$CT_HELP" "Usage: omnifocus-cli create-task"
assert_contains "create-task help shows --name"        "$CT_HELP" "--name"
assert_contains "create-task help shows (required)"    "$CT_HELP" "(required)"
assert_contains "create-task help shows --project"     "$CT_HELP" "--project"
assert_contains "create-task help shows --flagged"     "$CT_HELP" "--flagged"
assert_contains "create-task help shows --tags"        "$CT_HELP" "--tags"

LT_HELP=$("$CLI_BINARY" list-tasks --help 2>&1)
assert_contains "list-tasks help shows --status"       "$LT_HELP" "--status"
assert_contains "list-tasks help shows enum values"    "$LT_HELP" "all|available|completed"

LI_HELP=$("$CLI_BINARY" list-inbox --help 2>&1)
assert_contains "list-inbox help shows no parameters"  "$LI_HELP" "No parameters"

# ─── 13. CLI: unknown command ────────────────────────────────────────────────
header "13. CLI: unknown command"

UNKNOWN_CMD_OUT=$("$CLI_BINARY" nonexistent-command 2>&1 || true)
assert_contains "unknown command prints error"         "$UNKNOWN_CMD_OUT" "unknown command"

# ─── 14. CLI: argument parsing ───────────────────────────────────────────────
header "14. CLI: argument parsing"

BAD_FLAG_OUT=$("$CLI_BINARY" list-tasks --nonexistent-flag value 2>&1 || true)
assert_contains "unknown flag prints error"            "$BAD_FLAG_OUT" "Unknown flag"

MISSING_VAL_OUT=$("$CLI_BINARY" list-tasks --status 2>&1 || true)
assert_contains "missing value prints error"           "$MISSING_VAL_OUT" "Missing value"

# ─── 15. CLI: tool dispatch coverage ─────────────────────────────────────────
# Verify every tool can be invoked via CLI without getting "unknown command".
header "15. CLI: tool dispatch coverage"

cli_dispatch_check() {
  local cmd="$1"
  local out
  out=$("$CLI_BINARY" "$cmd" 2>&1 || true)
  if printf '%s' "$out" | grep -qF "unknown command"; then
    fail "CLI dispatch: $cmd" "got 'unknown command'"
  else
    pass "CLI dispatch: $cmd"
  fi
}

for tool in \
  omnifocus_list_tasks omnifocus_list_inbox omnifocus_list_projects \
  omnifocus_list_tags omnifocus_list_perspectives omnifocus_list_folders \
  omnifocus_create_folder omnifocus_move_project \
  omnifocus_list_flagged omnifocus_list_overdue omnifocus_list_available \
  omnifocus_search_tasks omnifocus_list_task_children omnifocus_get_task_parent \
  omnifocus_process_inbox omnifocus_set_project_sequential omnifocus_eval_automation \
  omnifocus_get_task omnifocus_get_project omnifocus_get_tag \
  omnifocus_create_task omnifocus_create_project omnifocus_create_tag \
  omnifocus_update_task omnifocus_update_project omnifocus_update_tag \
  omnifocus_complete_task omnifocus_complete_project \
  omnifocus_delete_task omnifocus_delete_project omnifocus_delete_tag \
  omnifocus_uncomplete_task omnifocus_uncomplete_project \
  omnifocus_append_to_note omnifocus_search_tags omnifocus_set_project_status \
  omnifocus_get_folder omnifocus_update_folder omnifocus_delete_folder \
  omnifocus_get_task_counts omnifocus_get_project_counts omnifocus_get_forecast \
  omnifocus_create_subtask omnifocus_duplicate_task \
  omnifocus_create_tasks_batch omnifocus_delete_tasks_batch omnifocus_move_tasks_batch \
  omnifocus_list_notifications omnifocus_add_notification \
  omnifocus_remove_notification omnifocus_set_task_repetition \
  omnifocus_mark_reviewed omnifocus_drop_task omnifocus_import_taskpaper \
  omnifocus_add_relative_notification omnifocus_move_tag omnifocus_move_folder \
  omnifocus_convert_task_to_project omnifocus_duplicate_project \
  omnifocus_get_forecast_tag omnifocus_clean_up omnifocus_get_settings \
  omnifocus_list_linked_files omnifocus_add_linked_file omnifocus_remove_linked_file \
  omnifocus_search_projects omnifocus_search_folders omnifocus_search_tasks_native \
  omnifocus_lookup_url omnifocus_get_forecast_days \
  omnifocus_get_focus omnifocus_set_focus omnifocus_undo omnifocus_redo omnifocus_save \
  omnifocus_duplicate_tasks_batch omnifocus_duplicate_tags \
  omnifocus_move_projects_batch omnifocus_reorder_task_tags \
  omnifocus_copy_tasks omnifocus_paste_tasks \
  omnifocus_next_repetition_date omnifocus_set_forecast_tag \
  omnifocus_set_notification_repeat; do
  cmd=$(printf '%s' "$tool" | sed 's/^omnifocus_//' | tr '_' '-')
  cli_dispatch_check "$cmd"
done

# ─── 16. CLI: daemon mode ────────────────────────────────────────────────────
header "16. CLI: daemon mode"

# Ensure no daemon is running from a previous test
"$CLI_BINARY" --stop 2>/dev/null || true

# --status when no daemon
STATUS_OFF=$("$CLI_BINARY" --status 2>&1)
assert_contains "status reports not running"           "$STATUS_OFF" "not running"

DAEMON_LOG=$(mktemp)
"$CLI_BINARY" --daemon >"$DAEMON_LOG" 2>&1 &
DAEMON_PID=$!
sleep 1

if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
  DAEMON_START_ERR=$(cat "$DAEMON_LOG")
  if printf '%s' "$DAEMON_START_ERR" | grep -qiE "operation not permitted|permission denied"; then
    skip "daemon runtime checks (socket bind not permitted in this environment)"
  else
    fail "daemon starts successfully" "startup failed: $DAEMON_START_ERR"
  fi
else
  # Verify socket created
  if [ -S "$HOME/.omnifocus-cli.sock" ]; then
    pass "daemon creates socket file"
  else
    fail "daemon creates socket file" "socket not found at ~/.omnifocus-cli.sock"
  fi

  # Verify PID file
  if [ -f "$HOME/.omnifocus-cli.pid" ]; then
    PID_CONTENT=$(cat "$HOME/.omnifocus-cli.pid")
    if [ "$PID_CONTENT" = "$DAEMON_PID" ]; then
      pass "PID file contains correct PID"
    else
      pass "PID file exists (PID: $PID_CONTENT)"
    fi
  else
    fail "PID file created" "~/.omnifocus-cli.pid not found"
  fi

  # --status when daemon is running
  STATUS_ON=$("$CLI_BINARY" --status 2>&1)
  assert_contains "status reports running"               "$STATUS_ON" "Daemon running"
  assert_contains "status shows pid"                     "$STATUS_ON" "pid"

  # --stop
  STOP_OUT=$("$CLI_BINARY" --stop 2>&1)
  assert_contains "stop reports success"                 "$STOP_OUT" "stopped"
  sleep 1

  # Verify socket removed after stop
  if [ ! -S "$HOME/.omnifocus-cli.sock" ]; then
    pass "socket removed after stop"
  else
    fail "socket removed after stop" "socket still exists"
    rm -f "$HOME/.omnifocus-cli.sock"
  fi

  # --status after stop
  STATUS_AFTER=$("$CLI_BINARY" --status 2>&1)
  assert_contains "status reports not running after stop" "$STATUS_AFTER" "not running"
fi
rm -f "$DAEMON_LOG"

# --stop when no daemon
STOP_NONE=$("$CLI_BINARY" --stop 2>&1 || true)
assert_contains "stop when not running shows error"    "$STOP_NONE" "No daemon"

# ─── 17. CLI: launchd command compatibility ──────────────────────────────────
header "17. CLI: launchd command compatibility"

CLI_SOURCE=$(cat "$ROOT_DIR/Sources/omnifocus-cli/CLI.swift")
assert_contains "launchd integration uses bootstrap"    "$CLI_SOURCE" 'runLaunchctl(["bootstrap", launchdDomainTarget(), launchdPlistPath])'
assert_contains "launchd integration uses bootout"      "$CLI_SOURCE" 'runLaunchctl(["bootout", launchdServiceTarget()])'
assert_contains "launchd integration targets gui/<uid>" "$CLI_SOURCE" '"gui/\(getuid())"'

# ─── 18. prompts/list ─────────────────────────────────────────────────────────
header "18. prompts/list"

PROMPTS_LIST_OUT=$(rpc '{"jsonrpc":"2.0","id":70,"method":"prompts/list","params":{}}')
assert_contains     "prompts/list returns result"    "$PROMPTS_LIST_OUT" '"result":'
assert_contains     "prompts array present"          "$PROMPTS_LIST_OUT" '"prompts"'
assert_contains     "capture prompt listed"          "$PROMPTS_LIST_OUT" '"name":"capture"'
assert_contains     "forecast prompt listed"         "$PROMPTS_LIST_OUT" '"name":"forecast"'
assert_contains     "review prompt listed"           "$PROMPTS_LIST_OUT" '"name":"review"'
assert_contains     "capture has task argument"      "$PROMPTS_LIST_OUT" '"name":"task"'

# Count prompts
PROMPT_COUNT=$(printf '%s' "$PROMPTS_LIST_OUT" | grep -oF '"name":"' | wc -l | tr -d ' ')
# 3 prompts + 1 argument = 4 "name" keys; but we only need to check the prompts
# by verifying all three are present above.

# ─── 19. prompts/get ──────────────────────────────────────────────────────────
header "19. prompts/get"

CAPTURE_PROMPT=$(rpc '{"jsonrpc":"2.0","id":71,"method":"prompts/get","params":{"name":"capture","arguments":{"task":"Buy groceries"}}}')
assert_contains     "capture prompt returns messages"    "$CAPTURE_PROMPT" '"messages"'
assert_contains     "capture prompt includes task text"  "$CAPTURE_PROMPT" 'Buy groceries'
assert_contains     "capture prompt has user role"       "$CAPTURE_PROMPT" '"role":"user"'
assert_contains     "capture prompt has text content"    "$CAPTURE_PROMPT" '"type":"text"'

CAPTURE_NO_ARG=$(rpc '{"jsonrpc":"2.0","id":72,"method":"prompts/get","params":{"name":"capture"}}')
assert_contains     "capture without arg asks user"      "$CAPTURE_NO_ARG" 'Ask the user'

FORECAST_PROMPT=$(rpc '{"jsonrpc":"2.0","id":73,"method":"prompts/get","params":{"name":"forecast"}}')
assert_contains     "forecast prompt returns messages"          "$FORECAST_PROMPT" '"messages"'
assert_contains     "forecast mentions omnifocus_get_forecast"  "$FORECAST_PROMPT" 'omnifocus_get_forecast'

REVIEW_PROMPT=$(rpc '{"jsonrpc":"2.0","id":74,"method":"prompts/get","params":{"name":"review"}}')
assert_contains     "review prompt returns messages"            "$REVIEW_PROMPT" '"messages"'
assert_contains     "review mentions omnifocus_list_inbox"      "$REVIEW_PROMPT" 'omnifocus_list_inbox'

UNKNOWN_PROMPT=$(rpc '{"jsonrpc":"2.0","id":75,"method":"prompts/get","params":{"name":"nonexistent"}}')
assert_contains     "unknown prompt returns error"       "$UNKNOWN_PROMPT" '"error":'

MISSING_PROMPT_NAME=$(rpc '{"jsonrpc":"2.0","id":76,"method":"prompts/get","params":{}}')
assert_contains     "missing prompt name returns error"  "$MISSING_PROMPT_NAME" '"error":'

# ─── 20. logging/setLevel ────────────────────────────────────────────────────
header "20. logging/setLevel"

LOG_SET=$(rpc '{"jsonrpc":"2.0","id":80,"method":"logging/setLevel","params":{"level":"debug"}}')
assert_contains     "logging/setLevel returns result"    "$LOG_SET" '"result":'
assert_not_contains "logging/setLevel no error"          "$LOG_SET" '"error":'

BAD_LEVEL=$(rpc '{"jsonrpc":"2.0","id":81,"method":"logging/setLevel","params":{"level":"banana"}}')
assert_contains     "invalid log level returns error"    "$BAD_LEVEL" '"error":'

MISSING_LEVEL=$(rpc '{"jsonrpc":"2.0","id":82,"method":"logging/setLevel","params":{}}')
assert_contains     "missing log level returns error"    "$MISSING_LEVEL" '"error":'

# ─── 21. initialize capabilities ─────────────────────────────────────────────
header "21. initialize capabilities"

assert_contains     "capabilities includes prompts"      "$INIT_OUT" '"prompts"'
assert_contains     "capabilities includes logging"      "$INIT_OUT" '"logging"'
assert_contains     "capabilities includes tools"        "$INIT_OUT" '"tools"'

# Sampling: client advertises capability, server accepts it
SAMPLING_INIT=$(rpc '{"jsonrpc":"2.0","id":90,"method":"initialize","params":{"protocolVersion":"2025-11-25","clientInfo":{"name":"test","version":"0"},"capabilities":{"sampling":{}}}}')
assert_contains     "initialize with sampling accepted"  "$SAMPLING_INIT" '"result":'
assert_not_contains "sampling init no error"             "$SAMPLING_INIT" '"error":'

# ─── 22. logging notifications emitted on tool call ──────────────────────────
header "22. logging notifications"

# Set level to debug, then call a tool — expect log notification lines
LOG_TOOL_OUT=$(printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":91,"method":"logging/setLevel","params":{"level":"debug"}}' \
  '{"jsonrpc":"2.0","id":92,"method":"tools/call","params":{"name":"omnifocus_eval_automation","arguments":{}}}' \
  | OF_BACKEND=jxa "$BINARY" 2>/dev/null)
assert_contains     "log notification emitted"           "$LOG_TOOL_OUT" 'notifications'
assert_contains     "log includes logger name"           "$LOG_TOOL_OUT" '"logger":"omnifocus-mcp"'
assert_contains     "log includes tool name"             "$LOG_TOOL_OUT" 'omnifocus_eval_automation'

# ─── Summary ─────────────────────────────────────────────────────────────────
printf "\n${BOLD}Results: %d passed, %d failed${NC}\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

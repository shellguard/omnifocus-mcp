#!/bin/bash
# test_live.sh — live integration tests requiring OmniFocus to be running
#
# Tests real CRUD operations, the normalizeStatus fix, content format on
# success responses, and batch operations. Creates and cleans up test data.
#
# Usage:
#   ./scripts/test_live.sh            # build then test
#   ./scripts/test_live.sh --no-build # skip build

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
BINARY="$ROOT_DIR/.build/release/omnifocus-mcp"
NO_BUILD=false
PASS=0
FAIL=0

# IDs of items created during the test run — cleaned up in the EXIT trap
CREATED_TASK_IDS=()
CREATED_PROJECT_IDS=()

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

pass()   { printf "${GREEN}PASS${NC} %s\n" "$1"; PASS=$((PASS+1)); }
fail()   { printf "${RED}FAIL${NC} %s\n  => %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
skip()   { printf "${YELLOW}SKIP${NC} %s\n" "$1"; }
header() { printf "\n${BOLD}%s${NC}\n" "$1"; }

# ── Prerequisites ─────────────────────────────────────────────────────────────
if ! pgrep -xq OmniFocus 2>/dev/null; then
  printf "${RED}ERROR${NC}: OmniFocus is not running. Start it and try again.\n" >&2
  exit 1
fi

if ! command -v jq > /dev/null 2>&1; then
  printf "${RED}ERROR${NC}: jq is required. Install with: brew install jq\n" >&2
  exit 1
fi

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

# ── Helpers ───────────────────────────────────────────────────────────────────

# Send one JSON-RPC request; print full response to stdout
rpc() {
  printf '%s\n' "$1" | OF_BACKEND=automation "$BINARY" 2>/dev/null
}

# Extract .result.content[0].text from a tools/call success response,
# then parse that as JSON and apply a jq filter.
# Usage: result_jq "$out" '.name'
result_jq() {
  local out="$1" filter="$2"
  printf '%s' "$out" | jq -r ".result.content[0].text" | jq -r "$filter" 2>/dev/null
}

# Return the raw text payload (already a JSON string)
result_text() {
  local out="$1"
  printf '%s' "$out" | jq -r ".result.content[0].text" 2>/dev/null
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

assert_not_contains() {
  local label="$1" output="$2" needle="$3"
  if printf '%s' "$output" | grep -qF -- "$needle"; then
    fail "$label" "expected NOT to find: $needle"
    printf '    output: %s\n' "$output"
  else
    pass "$label"
  fi
}

assert_eq() {
  local label="$1" got="$2" expected="$3"
  if [ "$got" = "$expected" ]; then
    pass "$label"
  else
    fail "$label" "expected '$expected', got '$got'"
  fi
}

assert_nonempty() {
  local label="$1" value="$2"
  if [ -n "$value" ] && [ "$value" != "null" ]; then
    pass "$label"
  else
    fail "$label" "expected non-empty/non-null value, got: '$value'"
  fi
}

# Call a tool and delete a task by id (best-effort, used in cleanup)
delete_task_quiet() {
  rpc "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_delete_task\",\"arguments\":{\"id\":\"$1\"}}}" > /dev/null 2>&1 || true
}

delete_project_quiet() {
  rpc "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_delete_project\",\"arguments\":{\"id\":\"$1\"}}}" > /dev/null 2>&1 || true
}

# ── Cleanup trap ──────────────────────────────────────────────────────────────
cleanup() {
  if [ ${#CREATED_TASK_IDS[@]} -gt 0 ] || [ ${#CREATED_PROJECT_IDS[@]} -gt 0 ]; then
    printf "\n==> Cleaning up test data...\n"
    for id in "${CREATED_TASK_IDS[@]+"${CREATED_TASK_IDS[@]}"}"; do
      delete_task_quiet "$id"
    done
    for id in "${CREATED_PROJECT_IDS[@]+"${CREATED_PROJECT_IDS[@]}"}"; do
      delete_project_quiet "$id"
    done
  fi
  printf "\n${BOLD}Results: %d passed, %d failed${NC}\n" "$PASS" "$FAIL"
}
trap cleanup EXIT

# ── Test suite ────────────────────────────────────────────────────────────────

# ─── 1. tools/call response format (success path) ────────────────────────────
header "1. tools/call response format (success)"

FORMAT_OUT=$(rpc '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"omnifocus_eval_automation","arguments":{"script":"JSON.stringify({ok:true})","parseJson":false}}}')

assert_contains     "response has result"           "$FORMAT_OUT" '"result":'
assert_not_contains "response has no error"         "$FORMAT_OUT" '"error":'
assert_contains     "content type is text"          "$FORMAT_OUT" '"type":"text"'
assert_not_contains "no legacy type:json"           "$FORMAT_OUT" '"type":"json"'

TEXT=$(result_text "$FORMAT_OUT")
assert_nonempty "content text field is non-empty"   "$TEXT"

# ─── 2. Task CRUD ─────────────────────────────────────────────────────────────
header "2. Task CRUD"

TASK_NAME="[omnifocus-mcp-test] $(date +%s)"

# Create
CREATE_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_create_task\",\"arguments\":{\"name\":\"$TASK_NAME\",\"note\":\"Created by test_live.sh\",\"flagged\":true}}}")
assert_contains     "create task succeeds"          "$CREATE_OUT" '"result":'
TASK_ID=$(result_jq "$CREATE_OUT" '.id')
assert_nonempty     "create task returns id"        "$TASK_ID"
CREATED_TASK_IDS+=("$TASK_ID")

# Read back
GET_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_get_task\",\"arguments\":{\"id\":\"$TASK_ID\"}}}")
assert_contains     "get task succeeds"             "$GET_OUT" '"result":'
GOT_NAME=$(result_jq "$GET_OUT" '.name')
assert_eq           "get task name round-trips"     "$GOT_NAME" "$TASK_NAME"
GOT_NOTE=$(result_jq "$GET_OUT" '.note')
assert_eq           "get task note round-trips"     "$GOT_NOTE" "Created by test_live.sh"
GOT_FLAG=$(result_jq "$GET_OUT" '.flagged')
assert_eq           "get task flagged round-trips"  "$GOT_FLAG" "true"

# Update
UPDATED_NAME="$TASK_NAME (updated)"
UPD_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_update_task\",\"arguments\":{\"id\":\"$TASK_ID\",\"name\":\"$UPDATED_NAME\",\"flagged\":false}}}")
assert_contains     "update task succeeds"          "$UPD_OUT" '"result":'
UPD_NAME=$(result_jq "$UPD_OUT" '.name')
assert_eq           "update task name reflected"    "$UPD_NAME" "$UPDATED_NAME"
UPD_FLAG=$(result_jq "$UPD_OUT" '.flagged')
assert_eq           "update task flagged reflected" "$UPD_FLAG" "false"

# Complete
COMP_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_complete_task\",\"arguments\":{\"id\":\"$TASK_ID\"}}}")
assert_contains     "complete task succeeds"        "$COMP_OUT" '"result":'
COMP_STATUS=$(result_jq "$COMP_OUT" '.completed')
assert_eq           "complete task shows completed" "$COMP_STATUS" "true"

# Uncomplete
UNCOMP_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_uncomplete_task\",\"arguments\":{\"id\":\"$TASK_ID\"}}}")
assert_contains     "uncomplete task succeeds"      "$UNCOMP_OUT" '"result":'
UNCOMP_STATUS=$(result_jq "$UNCOMP_OUT" '.completed')
assert_eq           "uncomplete task shows false"   "$UNCOMP_STATUS" "false"

# Append to note
NOTE_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_append_to_note\",\"arguments\":{\"id\":\"$TASK_ID\",\"type\":\"task\",\"text\":\"appended\"}}}")
assert_contains     "append to note succeeds"       "$NOTE_OUT" '"result":'
NEW_NOTE=$(result_jq "$NOTE_OUT" '.note')
if printf '%s' "$NEW_NOTE" | grep -q "appended"; then
  pass "note contains appended text"
else
  fail "note contains appended text" "got: $NEW_NOTE"
fi

# Delete
DEL_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_delete_task\",\"arguments\":{\"id\":\"$TASK_ID\"}}}")
assert_contains     "delete task succeeds"          "$DEL_OUT" '"result":'
# Remove from cleanup list since we deleted it manually
CREATED_TASK_IDS=()

# ─── 3. Project status & normalizeStatus fix ──────────────────────────────────
header "3. Project status (normalizeStatus fix)"

PROJ_NAME="[omnifocus-mcp-test-project] $(date +%s)"

# Create project
CPROJ_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_create_project\",\"arguments\":{\"name\":\"$PROJ_NAME\"}}}")
assert_contains     "create project succeeds"       "$CPROJ_OUT" '"result":'
PROJ_ID=$(result_jq "$CPROJ_OUT" '.id')
assert_nonempty     "create project returns id"     "$PROJ_ID"
CREATED_PROJECT_IDS+=("$PROJ_ID")

# Verify initial status is active
PROJ_STATUS=$(result_jq "$CPROJ_OUT" '.status')
assert_eq "new project status is active"            "$PROJ_STATUS" "active"

# Set to on_hold
HOLD_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_set_project_status\",\"arguments\":{\"id\":\"$PROJ_ID\",\"status\":\"on_hold\"}}}")
assert_contains     "set on_hold succeeds"          "$HOLD_OUT" '"result":'
HOLD_STATUS=$(result_jq "$HOLD_OUT" '.status')
assert_eq "set_project_status returns on_hold"      "$HOLD_STATUS" "on_hold"

# Read back via get_project — key test of normalizeStatus fix
GPROJ_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_get_project\",\"arguments\":{\"id\":\"$PROJ_ID\"}}}")
assert_contains     "get project succeeds"          "$GPROJ_OUT" '"result":'
GET_STATUS=$(result_jq "$GPROJ_OUT" '.status')
assert_eq "get_project status is on_hold not dropped" "$GET_STATUS" "on_hold"

# get_project_counts must count this project as on_hold, not dropped
COUNTS_OUT=$(rpc '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"omnifocus_get_project_counts","arguments":{}}}')
assert_contains     "get_project_counts succeeds"   "$COUNTS_OUT" '"result":'
ON_HOLD_COUNT=$(result_jq "$COUNTS_OUT" '.on_hold')
DROPPED_COUNT=$(result_jq "$COUNTS_OUT" '.dropped')
if [ "$ON_HOLD_COUNT" -gt 0 ] 2>/dev/null; then
  pass "get_project_counts on_hold > 0 (got $ON_HOLD_COUNT)"
else
  fail "get_project_counts on_hold count" "expected >0, got '$ON_HOLD_COUNT'"
fi

# Set to dropped
DROP_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_set_project_status\",\"arguments\":{\"id\":\"$PROJ_ID\",\"status\":\"dropped\"}}}")
DROP_STATUS=$(result_jq "$DROP_OUT" '.status')
assert_eq "set_project_status returns dropped"      "$DROP_STATUS" "dropped"
if [ "$DROPPED_COUNT" -ge 0 ] 2>/dev/null; then
  NEW_DROPPED=$(result_jq "$(rpc '{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"omnifocus_get_project_counts","arguments":{}}}')" '.dropped')
  if [ "$NEW_DROPPED" -gt "$DROPPED_COUNT" ] 2>/dev/null; then
    pass "dropped count incremented after status change"
  else
    fail "dropped count incremented" "before=$DROPPED_COUNT after=$NEW_DROPPED"
  fi
fi

# Restore to active before cleanup
rpc "{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_set_project_status\",\"arguments\":{\"id\":\"$PROJ_ID\",\"status\":\"active\"}}}" > /dev/null

# ─── 4. Batch task operations ─────────────────────────────────────────────────
header "4. Batch task operations"

TS=$(date +%s)
BATCH_JSON="{\"tasks\":[{\"name\":\"[mcp-batch-test-1] $TS\"},{\"name\":\"[mcp-batch-test-2] $TS\"},{\"name\":\"[mcp-batch-test-3] $TS\"}]}"
BATCH_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_create_tasks_batch\",\"arguments\":$BATCH_JSON}}")
assert_contains     "create_tasks_batch succeeds"   "$BATCH_OUT" '"result":'
BATCH_IDS=$(result_jq "$BATCH_OUT" '[.[].id] | @csv' 2>/dev/null || result_jq "$BATCH_OUT" '.[0].id')
BATCH_COUNT=$(result_jq "$BATCH_OUT" 'length')
assert_eq           "batch creates 3 tasks"         "$BATCH_COUNT" "3"

# Extract ids for deletion
ID1=$(result_jq "$BATCH_OUT" '.[0].id')
ID2=$(result_jq "$BATCH_OUT" '.[1].id')
ID3=$(result_jq "$BATCH_OUT" '.[2].id')
CREATED_TASK_IDS+=("$ID1" "$ID2" "$ID3")

assert_nonempty "batch id 1 returned" "$ID1"
assert_nonempty "batch id 2 returned" "$ID2"
assert_nonempty "batch id 3 returned" "$ID3"

# Batch delete
DEL_BATCH_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_delete_tasks_batch\",\"arguments\":{\"ids\":[\"$ID1\",\"$ID2\",\"$ID3\"]}}}")
assert_contains     "delete_tasks_batch succeeds"   "$DEL_BATCH_OUT" '"result":'
DEL_COUNT=$(result_jq "$DEL_BATCH_OUT" '.deleted')
assert_eq           "batch deletes 3 tasks"         "$DEL_COUNT" "3"
CREATED_TASK_IDS=()  # cleared — already deleted

# ─── 5. Search and list ───────────────────────────────────────────────────────
header "5. Search and list"

LIST_OUT=$(rpc '{"jsonrpc":"2.0","id":30,"method":"tools/call","params":{"name":"omnifocus_list_tasks","arguments":{"limit":5}}}')
assert_contains     "list_tasks succeeds"           "$LIST_OUT" '"result":'
LIST_TYPE=$(printf '%s' "$LIST_OUT" | jq -r '.result.content[0].type')
assert_eq           "list_tasks content type is text" "$LIST_TYPE" "text"

LIST_INBOX_OUT=$(rpc '{"jsonrpc":"2.0","id":31,"method":"tools/call","params":{"name":"omnifocus_list_inbox","arguments":{}}}')
assert_contains     "list_inbox succeeds"           "$LIST_INBOX_OUT" '"result":'

LIST_PROJ_OUT=$(rpc '{"jsonrpc":"2.0","id":32,"method":"tools/call","params":{"name":"omnifocus_list_projects","arguments":{}}}')
assert_contains     "list_projects succeeds"        "$LIST_PROJ_OUT" '"result":'

# ─── 6. Counts and forecast ───────────────────────────────────────────────────
header "6. Counts and forecast"

TASK_COUNTS_OUT=$(rpc '{"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"omnifocus_get_task_counts","arguments":{}}}')
assert_contains     "get_task_counts succeeds"      "$TASK_COUNTS_OUT" '"result":'
TC_TOTAL=$(result_jq "$TASK_COUNTS_OUT" '.total')
assert_nonempty     "task counts has total"         "$TC_TOTAL"

FORECAST_OUT=$(rpc '{"jsonrpc":"2.0","id":41,"method":"tools/call","params":{"name":"omnifocus_get_forecast","arguments":{}}}')
assert_contains     "get_forecast succeeds"         "$FORECAST_OUT" '"result":'
# Forecast must have the four expected keys
for key in overdue today flagged dueThisWeek; do
  if result_jq "$FORECAST_OUT" "has(\"$key\")" | grep -q "true"; then
    pass "forecast has key: $key"
  else
    fail "forecast has key: $key" "key missing from: $(result_text "$FORECAST_OUT")"
  fi
done

# ─── 7. Subtask creation ──────────────────────────────────────────────────────
header "7. Subtask creation"

PARENT_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":50,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_create_task\",\"arguments\":{\"name\":\"[mcp-parent] $(date +%s)\"}}}")
PARENT_ID=$(result_jq "$PARENT_OUT" '.id')
assert_nonempty "parent task created" "$PARENT_ID"
CREATED_TASK_IDS+=("$PARENT_ID")

CHILD_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":51,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_create_subtask\",\"arguments\":{\"parentId\":\"$PARENT_ID\",\"name\":\"[mcp-child] $(date +%s)\"}}}")
assert_contains "create_subtask succeeds" "$CHILD_OUT" '"result":'
CHILD_ID=$(result_jq "$CHILD_OUT" '.id')
assert_nonempty "child task id returned" "$CHILD_ID"
# Child is nested — will be deleted with parent

# Verify parent is reported correctly
PARENT_VAL=$(result_jq "$CHILD_OUT" '.parentId // .parent // empty' 2>/dev/null || echo "")
# (parent field name varies; just verify get_task_children works)
CHILDREN_OUT=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":52,\"method\":\"tools/call\",\"params\":{\"name\":\"omnifocus_list_task_children\",\"arguments\":{\"id\":\"$PARENT_ID\"}}}")
assert_contains "list_task_children succeeds" "$CHILDREN_OUT" '"result":'
CHILD_COUNT=$(result_jq "$CHILDREN_OUT" 'length')
if [ "$CHILD_COUNT" -gt 0 ] 2>/dev/null; then
  pass "parent has at least 1 child (got $CHILD_COUNT)"
else
  fail "parent has children" "expected >0 children, got: $CHILD_COUNT"
fi

# (subtask is cleaned up with parent via delete_task_quiet)

# ── Summary is printed by the EXIT trap ───────────────────────────────────────

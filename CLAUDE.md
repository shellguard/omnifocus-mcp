# OmniFocus MCP — Claude Code Guide

## Project Overview

A single-file Swift MCP server (`Sources/omnifocus-mcp/omnifocus_mcp.swift`) that exposes OmniFocus as MCP tools. All logic lives in one ~4500-line file. **No external dependencies** — stdlib only.

## Build & Test

```bash
swift build -c release          # build
.build/release/omnifocus-mcp   # run (expects MCP JSON-RPC on stdin)
```

Binary lands at `.build/release/omnifocus-mcp`. Swift 6.2+ required.

## Architecture

The file has four logical sections (in order):

1. **`jxaScript`** (lines ~35–1450) — JS string executed by `osascript -l JavaScript`. Used as fallback when Omni Automation is unavailable.
2. **`omniAutomationScript`** (lines ~1450–3050) — JS string executed by OmniFocus's own JS engine via AppleScript `evaluate javascript`. Preferred backend.
3. **`tools` array** (lines ~3050–3450) — `ToolDefinition` structs (name, description, inputSchema).
4. **`callTool()` / `callAction()`** (lines ~3450+) — Swift dispatch: tool name → action string → backend.

Both JS scripts must stay in sync whenever a new action is added.

## Adding a New Tool — Checklist

1. Add the JS function to **`jxaScript`** (before `var input = readInput();`)
2. Add a `case` to the **`jxaScript` switch** (before `default:`)
3. Add the equivalent JS function to **`omniAutomationScript`** (before `var input = JSON.parse(...)`)
4. Add a `case` to the **`omniAutomationScript` switch** (before `default:`)
5. Add a `ToolDefinition` to the **`tools` array**
6. Add a `case` to **`callTool()`** calling `callAction("action_name", params: arguments)`
7. Run `swift build -c release` to verify

## Key JS Utilities (available in both scripts)

| Utility | Purpose |
|---|---|
| `safeCall(obj, 'prop')` | Safe property/method read, returns `null` on error |
| `safeSet(obj, 'prop', val)` | Safe property write, returns bool |
| `callIfFunction(obj, 'prop', args)` | Call method if it exists (omniAutomation only) |
| `normalizeId(value)` | Strip OmniFocus UUID suffixes |
| `parseDate(value)` | ISO 8601 string → Date |
| `toISO(date)` | Date → ISO 8601 string |
| `taskToJSON(task)` | Serialize task to plain object |
| `projectToJSON(project)` | Serialize project |
| `tagToJSON(tag)` / `folderToJSON(folder)` | Serialize tag/folder |
| `findTaskById(doc, id)` | Look up task by normalized ID |
| `findProjectById/ByName(doc, ...)` | Look up project |
| `findTagById/ByName(doc, ...)` | Look up tag |
| `findFolderById/ByName(doc, ...)` | Look up folder |
| `arrayify(value)` | Normalize array-like to real array |
| `firstValue(obj, ['p1','p2'])` | First non-null of multiple property names |
| `appendNote(obj, text)` | Append to note with newline separator |

**JXA-specific:** uses `getDocument()` → `doc.make(...)`, `task.delete()`.
**OmniAutomation-specific:** uses `getDatabase()`, `callIfFunction()`, `assignTaskToProject()`, `applyTags()`.

## Backend Selection

- Default: Omni Automation (probed at first call)
- Override: `OF_BACKEND=jxa` or `OF_BACKEND=automation`
- App path: `OF_APP_PATH=/Applications/OmniFocus.app`

## Current Tool Count: 51

### Original 31 tools
`list_tasks`, `list_inbox`, `list_projects`, `list_tags`, `list_perspectives`, `list_folders`, `create_folder`, `move_project`, `list_flagged`, `list_overdue`, `list_available`, `search_tasks`, `list_task_children`, `get_task_parent`, `process_inbox`, `set_project_sequential`, `eval_automation`, `get_task`, `get_project`, `get_tag`, `create_task`, `create_project`, `create_tag`, `update_task`, `update_project`, `update_tag`, `complete_task`, `complete_project`, `delete_task`, `delete_project`, `delete_tag`

### Added in feature-gap closure (20 tools)
| Tool | Action | Notes |
|---|---|---|
| `omnifocus_uncomplete_task` | `uncomplete_task` | `markIncomplete()` or `completed = false` |
| `omnifocus_uncomplete_project` | `uncomplete_project` | Restore to active status |
| `omnifocus_append_to_note` | `append_to_note` | Params: `id`, `type` (task/project), `text` |
| `omnifocus_search_tags` | `search_tags` | Case-insensitive substring on tag names |
| `omnifocus_set_project_status` | `set_project_status` | `active` / `on_hold` / `dropped` |
| `omnifocus_get_folder` | `get_folder` | By `id` or `name`; returns projects + subfolders |
| `omnifocus_update_folder` | `update_folder` | Rename folder by `id` |
| `omnifocus_delete_folder` | `delete_folder` | Delete folder by `id` |
| `omnifocus_get_task_counts` | `get_task_counts` | `{total, available, completed, overdue, flagged, inbox}` |
| `omnifocus_get_project_counts` | `get_project_counts` | `{total, active, on_hold, dropped, stalled}` |
| `omnifocus_get_forecast` | `get_forecast` | `{overdue, today, flagged, dueThisWeek}` arrays |
| `omnifocus_create_subtask` | `create_subtask` | Params: `parentId` + standard task fields |
| `omnifocus_duplicate_task` | `duplicate_task` | Copies all properties; optional `name` override |
| `omnifocus_create_tasks_batch` | `create_tasks_batch` | `tasks: [{name, project, ...}]` array |
| `omnifocus_delete_tasks_batch` | `delete_tasks_batch` | `ids: [string]`; deduplicates |
| `omnifocus_move_tasks_batch` | `move_tasks_batch` | `ids`, `project`; moves to named project |
| `omnifocus_list_notifications` | `list_notifications` | Returns task alarms as `{id, kind, fireDate}` |
| `omnifocus_add_notification` | `add_notification` | Absolute-date alarm via `date` (ISO 8601) |
| `omnifocus_remove_notification` | `remove_notification` | Params: `id` (task), `notificationId` |
| `omnifocus_set_task_repetition` | `set_task_repetition` | `rule` (iCal RRULE string), `scheduleType` (due/defer/fixed) |

## Notes

- Notifications API (`alarms`) is version-sensitive; guarded with try/catch in both backends.
- Repetition uses `Task.RepetitionRule` / `Task.RepetitionMethod` in Omni Automation (with string fallback).
- Project status in OmniAutomation uses `Project.Status.Active/OnHold/Dropped` enum (with string fallback).
- `stalled` projects = active projects with zero available next actions.

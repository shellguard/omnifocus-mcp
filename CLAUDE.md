# OmniFocus MCP — Claude Code Guide

## Project Overview

Swift package with a shared core library and two executables:

- `OmniFocusCore` (tool metadata + execution engine + embedded JS resources)
- `omnifocus-mcp` (MCP stdio server)
- `omnifocus-cli` (CLI with optional local daemon mode)

No external Swift dependencies (stdlib/Foundation only).

## Build & Test

```bash
swift build -c release
.build/release/omnifocus-mcp   # MCP server (JSON-RPC on stdin/stdout)
.build/release/omnifocus-cli   # CLI
./scripts/test.sh --no-build   # integration/protocol checks
```

Swift 6.2+ required.

## Architecture

### File Structure

| File | Purpose | Lines |
|---|---|---|
| `Sources/OmniFocusCore/OFEngine.swift` | Tool dispatch, backend selection, script execution | ~260 |
| `Sources/OmniFocusCore/Tools.swift` | `allTools` array — 84 `ToolDefinition` structs with annotations | ~1040 |
| `Sources/OmniFocusCore/ToolDefinition.swift` | `ToolDefinition` struct + annotation constants | ~18 |
| `Sources/OmniFocusCore/MCPError.swift` | Shared MCP/tool error definitions | ~27 |
| `Sources/OmniFocusCore/Resources/shared.js` | Shared JS utility functions used by both backends | ~170 |
| `Sources/OmniFocusCore/Resources/jxa.js` | JXA backend script + action switch | ~2200 |
| `Sources/OmniFocusCore/Resources/omni_automation.js` | Omni Automation backend script + action switch | ~2750 |
| `Sources/omnifocus-mcp/MCPServer.swift` | MCP JSON-RPC transport and protocol handlers | ~160 |
| `Sources/omnifocus-cli/CLI.swift` | CLI command mapping, flag parsing, daemon mode | ~700 |

### JS Backend Composition

Both JS backends share 14 utility functions defined in `JSShared.swift`. These are inlined into each script at Swift string concatenation time:

```
JXA script = JXA preamble + shared utilities + JXA-specific functions + dispatch
OmniAutomation script = OA preamble + shared utilities + OA-specific functions + dispatch
```

Both JS scripts must stay in sync whenever a new action is added.

### Tool Dispatch

`callTool()` dynamically derives the action name from the tool name by stripping the `omnifocus_` prefix (except explicit aliases like `omnifocus_convert_task_to_project` and special handling for `omnifocus_eval_automation`).

This means there is no additional Swift-side action switch to update, but every new tool still needs matching JS implementation + JS `switch (action)` entries in both backends.

### MCP Protocol Behavior

- Supported protocol versions: `2025-11-25`, `2025-06-18`, `2024-11-05`.
- `initialize` negotiates the protocol version: use requested version when supported, otherwise fall back to latest supported.
- Accept both lifecycle notification names: `initialized` and `notifications/initialized`.
- In `tools/call`, tool execution failures are returned in-result with `isError: true`; keep JSON-RPC errors for protocol-level failures (unknown method/tool, malformed request).

### launchd Integration (CLI)

- `omnifocus-cli --install` uses `launchctl bootstrap gui/<uid> <plist>` (with `load` fallback).
- `omnifocus-cli --uninstall` uses `launchctl bootout gui/<uid>/<label>` (with `unload` fallback).
- Socket path handling validates UNIX socket path length before bind/connect to avoid silent truncation failures.

## Adding a New Tool — Checklist

1. If the function uses only shared utilities, add to **`JSShared.swift`** (otherwise add to each backend)
2. Add the JS function to **`JXAScript.swift`**
3. Add a `case` to the **`JXAScript.swift` switch** (before `default:`)
4. Add the equivalent JS function to **`OmniAutomationScript.swift`**
5. Add a `case` to the **`OmniAutomationScript.swift` switch** (before `default:`)
6. Add a `ToolDefinition` to **`Tools.swift`** (dispatch is automatic — no `callTool()` change needed)
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

## Current Tool Count: 84

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
| `omnifocus_set_task_repetition` | `set_task_repetition` | `rule` (iCal RRULE string), `scheduleType`, `anchorDateKey`, `catchUpAutomatically` |

### Added in Pro 4.8.8 enhancement (11 tools)
| Tool | Action | Notes |
|---|---|---|
| `omnifocus_mark_reviewed` | `mark_reviewed` | `project.markReviewed()` or set `lastReviewDate` |
| `omnifocus_drop_task` | `drop_task` | `task.drop(false)` — preserves unlike delete |
| `omnifocus_import_taskpaper` | `import_taskpaper` | OmniAuto: `Task.byParsingTransportText()`, JXA: line-by-line |
| `omnifocus_add_relative_notification` | `add_relative_notification` | `beforeSeconds` offset alarm |
| `omnifocus_move_tag` | `move_tag` | Move tag under parent or to root |
| `omnifocus_move_folder` | `move_folder` | Move folder under parent or to root |
| `omnifocus_convert_task_to_project` | `convert_to_project` | OmniAuto: `convertTasksToProjects()`, JXA: manual copy+delete |
| `omnifocus_duplicate_project` | `duplicate_project` | OmniAuto: `duplicateSections()`, JXA: manual copy |
| `omnifocus_get_forecast_tag` | `get_forecast_tag` | OmniAuto: `Tag.forecastTag`, JXA: null |
| `omnifocus_clean_up` | `clean_up` | OmniAuto: `document.cleanUp()`, JXA: `doc.compact()` |
| `omnifocus_get_settings` | `get_settings` | OmniAuto: `Settings.objectForKey()`, JXA: limited |

### Added in complete API coverage (22 tools)
| Tool | Action | Notes |
|---|---|---|
| `omnifocus_list_linked_files` | `list_linked_files` | Returns `linkedFileURLs` array for a task |
| `omnifocus_add_linked_file` | `add_linked_file` | Params: `id`, `url` |
| `omnifocus_remove_linked_file` | `remove_linked_file` | Params: `id`, `url` |
| `omnifocus_search_projects` | `search_projects` | OmniAuto: `database.projectsMatching()`, JXA: manual |
| `omnifocus_search_folders` | `search_folders` | OmniAuto: `database.foldersMatching()`, JXA: manual |
| `omnifocus_search_tasks_native` | `search_tasks_native` | OmniAuto: `database.tasksMatching()`, JXA: fallback |
| `omnifocus_lookup_url` | `lookup_url` | OmniAuto: `database.objectForURL()`, JXA: limited |
| `omnifocus_get_forecast_days` | `get_forecast_days` | OmniAuto: ForecastDay API, JXA: getForecast fallback |
| `omnifocus_get_focus` | `get_focus` | Returns focused projects/folders |
| `omnifocus_set_focus` | `set_focus` | Params: `ids` (empty to unfocus) |
| `omnifocus_undo` | `undo` | OmniAuto: `document.undo()`, JXA: limited |
| `omnifocus_redo` | `redo` | OmniAuto: `document.redo()`, JXA: limited |
| `omnifocus_save` | `save` | `document.save()` |
| `omnifocus_duplicate_tasks_batch` | `duplicate_tasks_batch` | Params: `ids` array |
| `omnifocus_duplicate_tags` | `duplicate_tags` | OmniAuto: `duplicateTags()`, JXA: manual copy |
| `omnifocus_move_projects_batch` | `move_projects_batch` | OmniAuto: `moveSections()`, JXA: manual |
| `omnifocus_reorder_task_tags` | `reorder_task_tags` | Removes all, re-adds in order |
| `omnifocus_copy_tasks` | `copy_tasks` | OmniAuto: `copyTasksToPasteboard()`, JXA: limited |
| `omnifocus_paste_tasks` | `paste_tasks` | OmniAuto: `pasteTasksFromPasteboard()`, JXA: limited |
| `omnifocus_next_repetition_date` | `next_repetition_date` | `repetitionRule.firstDateAfterDate()` |
| `omnifocus_set_forecast_tag` | `set_forecast_tag` | OmniAuto: set `Tag.forecastTag`, JXA: limited |
| `omnifocus_set_notification_repeat` | `set_notification_repeat` | Set alarm `repeatInterval` |

### Enriched serialization fields (Pro 4.8.8)

**taskToJSON** new fields: `plannedDate`, `effectivePlannedDate`, `effectiveDueDate`, `effectiveDeferDate`, `effectiveFlagged`, `added`, `modified`, `taskStatus`, `sequential`, `completedByChildren`, `hasChildren`, `url` (OmniAuto only), `dropDate`, `effectiveCompletedDate`, `effectiveDropDate`, `shouldUseFloatingTimeZone`, `assignedContainer`

**projectToJSON** new fields: `sequential`, `containsSingletonActions`, `estimatedMinutes`, `lastReviewDate`, `nextReviewDate`, `reviewInterval`, `parentFolder`, `parentFolderId`, `added`, `modified`, `numberOfTasks`, `numberOfAvailableTasks`, `effectiveDueDate`, `effectiveDeferDate`, `effectiveFlagged`, `url` (OmniAuto only), `nextTask`, `defaultSingletonActionHolder`, `shouldUseFloatingTimeZone`, `dropDate`, `effectiveCompletedDate`, `effectiveDropDate`

**tagToJSON** new fields: `status`, `allowsNextAction`, `childrenAreMutuallyExclusive`, `availableTaskCount`

**folderToJSON** new fields: `status`, `parentId`, `parentName`, `projectCount`, `folderCount`

**perspectiveToJSON** new fields: `archivedFilterRules`, `iconColor`

**Notification/alarm serialization** new fields: `repeatInterval`, `isSnoozed`, `usesFloatingTimeZone`, `relativeFireOffset`

### Enriched writable parameters (Pro 4.8.8)

- `create_task` / `update_task` / `create_subtask`: `planned`, `sequential`, `completedByChildren`, `shouldUseFloatingTimeZone`
- `create_project` / `update_project`: `estimatedMinutes`, `sequential`, `containsSingletonActions`, `reviewInterval`, `shouldUseFloatingTimeZone`
- `update_tag`: `allowsNextAction`
- `set_task_repetition`: `anchorDateKey` (due/defer/planned), `catchUpAutomatically`

## Notes

- Notifications API (`alarms`) is version-sensitive; guarded with try/catch in both backends.
- Repetition uses `Task.RepetitionRule` / `Task.RepetitionMethod` in Omni Automation (with string fallback).
- Project status in OmniAutomation uses `Project.Status.Active/OnHold/Dropped` enum (with string fallback).
- `stalled` projects = active projects with zero available next actions.
- Planned dates, effective dates, and `url` require OmniFocus 4.7+; gracefully return `null` on older versions via `safeCall`/`firstValue`.
- `sequential` in JXA projectToJSON uses inverse of `parallel` property; OmniAutomation uses `sequential` directly.

# OmniFocus MCP Server (macOS)

A Swift-based MCP server for OmniFocus 4 using Omni Automation (evaluate javascript) via AppleScript. macOS only.

## Requirements

- macOS with OmniFocus 4 installed
- Swift 6.2 toolchain
- Automation permission to control OmniFocus (System Settings > Privacy & Security > Automation)
- OmniFocus setting: Automation > Accept scripts from external applications

## Build

```bash
swift build -c release
```

The binary will be at `./.build/release/omnifocus-mcp`.

## Package (pkg)

Build an unsigned installer package:

```bash
./scripts/build_pkg.sh
```

Optional environment overrides:

- `PKG_VERSION` (default `0.1.0`)
- `PKG_IDENTIFIER` (default `com.omnifocus-mcp.cli`)
- `PKG_INSTALL_LOCATION` (default `/usr/local/bin`)
- `PKG_SIGN_ID` (set to sign with `pkgbuild`)

The package will be written to `./dist/`.

## Run

This is an MCP server over stdio. Configure your MCP client to launch it as a command.

Example (generic MCP config):

```json
{
  "command": "/Users/ap/omnifocus-mcp/.build/release/omnifocus-mcp",
  "args": [],
  "env": {
    "OF_APP_PATH": "/Applications/OmniFocus.app",
    "OF_BACKEND": "automation"
  }
}
```

## Tools

- `omnifocus_list_tasks` (filters: status, project, tag, search, flagged, limit)
- `omnifocus_list_inbox`
- `omnifocus_list_projects`
- `omnifocus_list_tags`
- `omnifocus_list_perspectives`
- `omnifocus_list_folders`
- `omnifocus_create_folder` (name, note, parent, parentId)
- `omnifocus_move_project` (projectId, folder, folderId, createMissingFolder)
- `omnifocus_list_flagged` (limit)
- `omnifocus_list_overdue` (limit, includeCompleted)
- `omnifocus_list_available` (limit, includeCompleted)
- `omnifocus_search_tasks` (search, status, project, tag, limit)
- `omnifocus_list_task_children` (id)
- `omnifocus_get_task_parent` (id)
- `omnifocus_process_inbox` (project, projectId, tags, due, defer, flagged, estimatedMinutes, noteAppend, limit, createMissingTags, createMissingProject, keepInInbox)
- `omnifocus_set_project_sequential` (id, sequential)
- `omnifocus_eval_automation` (script, parseJson) — runs Omni Automation JS via AppleScript
- `omnifocus_get_task` (id)
- `omnifocus_get_project` (id)
- `omnifocus_get_tag` (id)
- `omnifocus_create_task` (name, note, project, tags, due, defer, flagged, estimatedMinutes, inbox, createMissingTags, createMissingProject)
- `omnifocus_create_project` (name, note, due, defer, flagged)
- `omnifocus_create_tag` (name, active)
- `omnifocus_update_task` (id + optional fields)
- `omnifocus_update_project` (id + optional fields)
- `omnifocus_update_tag` (id + optional fields)
- `omnifocus_complete_task` (id, completionDate)
- `omnifocus_complete_project` (id, completionDate)
- `omnifocus_delete_task` (id)
- `omnifocus_delete_project` (id)
- `omnifocus_delete_tag` (id)

Dates are ISO 8601 strings.

## Notes

- The first run will prompt macOS to allow the server to control OmniFocus.
- OmniFocus must be able to launch in the current user session.
- If you see errors launching OmniFocus, set `OF_APP_PATH` to the installed app path (for example `/Applications/OmniFocus.app`) and make sure the app can be opened normally.
- If Omni Automation is unavailable in your environment, set `OF_BACKEND` to `jxa` to use the AppleScript dictionary via JXA.
- Omni Automation plug-ins can be stored in iCloud at `~/Library/Mobile Documents/iCloud~com~omnigroup~OmniFocus/Documents/Plug-Ins`. We can add a plug-in bridge if you want a first-party entry point inside OmniFocus.

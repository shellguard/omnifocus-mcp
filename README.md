# OmniFocus MCP + CLI (macOS)

Swift-based OmniFocus integration for macOS with two executables:

- `omnifocus-mcp`: MCP server over stdio (JSON-RPC)
- `omnifocus-cli`: human-friendly CLI with optional local daemon mode

The implementation uses Omni Automation where available, with JXA fallback.

## Requirements

- macOS with OmniFocus 4 installed
- Swift 6.2+ toolchain
- Automation permission to control OmniFocus:
  System Settings > Privacy & Security > Automation
- OmniFocus setting enabled:
  Automation > Accept scripts from external applications

## Install

Build and install `omnifocus-mcp` to `/usr/local/bin`:

```bash
./scripts/install.sh
```

Optional flags / env vars:

- `--prefix /path` — install under a different prefix (default `/usr/local`)
- `INSTALL_PREFIX=/path ./scripts/install.sh` — same via env

## Build

```bash
swift build -c release
```

Release binaries:

- `./.build/release/omnifocus-mcp`
- `./.build/release/omnifocus-cli`

## Run As MCP Server

Configure your MCP client to launch `omnifocus-mcp`.

Protocol compatibility:

- Supports MCP protocol versions: `2025-11-25`, `2025-06-18`, `2024-11-05`
- `initialize` negotiates protocol version (uses requested version when supported, otherwise falls back to latest supported)
- Accepts both lifecycle notifications: `initialized` (legacy) and `notifications/initialized` (current)
- `tools/call` execution failures are returned as MCP tool results with `isError: true` (invalid method/tool lookup still use JSON-RPC errors)
- `tools/list` supports cursor pagination (`params.cursor` / `result.nextCursor`)

Example MCP config:

```json
{
  "command": "/usr/local/bin/omnifocus-mcp",
  "args": [],
  "env": {
    "OF_APP_PATH": "/Applications/OmniFocus.app",
    "OF_BACKEND": "automation"
  }
}
```

Environment variables:

- `OF_APP_PATH` — path to OmniFocus app bundle (default `/Applications/OmniFocus.app`)
- `OF_BACKEND` — force backend: `automation` or `jxa` (default auto-detect)

## Run As CLI

Examples:

```bash
./.build/release/omnifocus-cli --help
./.build/release/omnifocus-cli list-tasks --status available --limit 20
./.build/release/omnifocus-cli create-task --name "Call Alex" --project "Work"
```

Daemon mode (faster repeated calls):

```bash
./.build/release/omnifocus-cli --daemon
./.build/release/omnifocus-cli --status
./.build/release/omnifocus-cli --stop
```

Install as launchd user agent (auto-start at login):

```bash
./.build/release/omnifocus-cli --install
./.build/release/omnifocus-cli --uninstall
```

`--install` uses modern `launchctl bootstrap gui/<uid>` with a legacy `load` fallback for older environments.

## Test

Protocol and integration tests (no OmniFocus required):

```bash
./scripts/test.sh            # build then test
./scripts/test.sh --no-build # skip build
```

Live tests (requires OmniFocus running and `jq`):

```bash
./scripts/test_live.sh
./scripts/test_live.sh --no-build
```

## Package (pkg)

Build an unsigned installer package:

```bash
./scripts/build_pkg.sh
```

Optional environment overrides:

- `PKG_VERSION` (default `0.2.0`)
- `PKG_IDENTIFIER` (default `com.omnifocus-mcp.cli`)
- `PKG_INSTALL_LOCATION` (default `/usr/local/bin`)
- `PKG_SIGN_ID` (set to sign with `pkgbuild`)

Package output: `./dist/`

## Tool Catalog

Current MCP catalog: **84 tools**.

Source of truth:

- Runtime: `tools/list`
- Static definitions: `Sources/OmniFocusCore/Tools.swift`

Dates use ISO 8601 strings.

### Read / list

- `omnifocus_list_tasks`
- `omnifocus_list_inbox`
- `omnifocus_list_projects`
- `omnifocus_list_tags`
- `omnifocus_list_perspectives`
- `omnifocus_list_folders`
- `omnifocus_list_flagged`
- `omnifocus_list_overdue`
- `omnifocus_list_available`
- `omnifocus_list_task_children`
- `omnifocus_get_task_parent`
- `omnifocus_get_task`
- `omnifocus_get_project`
- `omnifocus_get_tag`
- `omnifocus_get_folder`
- `omnifocus_get_task_counts`
- `omnifocus_get_project_counts`
- `omnifocus_get_forecast`
- `omnifocus_get_forecast_tag`
- `omnifocus_get_forecast_days`
- `omnifocus_get_settings`
- `omnifocus_get_focus`

### Search / lookup

- `omnifocus_search_tasks`
- `omnifocus_search_tags`
- `omnifocus_search_projects`
- `omnifocus_search_folders`
- `omnifocus_search_tasks_native`
- `omnifocus_lookup_url`

### Task create / update / lifecycle

- `omnifocus_create_task`
- `omnifocus_create_subtask`
- `omnifocus_update_task`
- `omnifocus_duplicate_task`
- `omnifocus_complete_task`
- `omnifocus_uncomplete_task`
- `omnifocus_drop_task`
- `omnifocus_delete_task`
- `omnifocus_append_to_note`
- `omnifocus_set_task_repetition`
- `omnifocus_next_repetition_date`
- `omnifocus_process_inbox`

### Project create / update / lifecycle

- `omnifocus_create_project`
- `omnifocus_update_project`
- `omnifocus_complete_project`
- `omnifocus_uncomplete_project`
- `omnifocus_delete_project`
- `omnifocus_set_project_status`
- `omnifocus_set_project_sequential`
- `omnifocus_move_project`
- `omnifocus_mark_reviewed`
- `omnifocus_duplicate_project`
- `omnifocus_move_projects_batch`

### Folders / tags

- `omnifocus_create_folder`
- `omnifocus_update_folder`
- `omnifocus_delete_folder`
- `omnifocus_move_folder`
- `omnifocus_create_tag`
- `omnifocus_update_tag`
- `omnifocus_delete_tag`
- `omnifocus_move_tag`
- `omnifocus_duplicate_tags`

### Batch operations

- `omnifocus_create_tasks_batch`
- `omnifocus_delete_tasks_batch`
- `omnifocus_move_tasks_batch`
- `omnifocus_duplicate_tasks_batch`
- `omnifocus_convert_task_to_project`

### Notifications / alarms

- `omnifocus_list_notifications`
- `omnifocus_add_notification`
- `omnifocus_remove_notification`
- `omnifocus_add_relative_notification`
- `omnifocus_set_notification_repeat`

### Linked files / pasteboard / focus

- `omnifocus_list_linked_files`
- `omnifocus_add_linked_file`
- `omnifocus_remove_linked_file`
- `omnifocus_copy_tasks`
- `omnifocus_paste_tasks`
- `omnifocus_set_focus`
- `omnifocus_set_forecast_tag`
- `omnifocus_reorder_task_tags`
- `omnifocus_import_taskpaper`

### Maintenance / power tools

- `omnifocus_undo`
- `omnifocus_redo`
- `omnifocus_save`
- `omnifocus_clean_up`
- `omnifocus_eval_automation`

## Claude Cowork Plugin

`cowork-plugin/` is a ready-made Claude Cowork plugin that connects to this MCP server.

Included skills:

- `capture-tasks`
- `check-workload`
- `manage-projects`

Included commands:

- `/omnifocus:capture [text]`
- `/omnifocus:forecast`
- `/omnifocus:review`

### Install Plugin

1. Build/install `omnifocus-mcp`.
2. In Claude Desktop: Cowork > Customize > Browse plugins, then upload `cowork-plugin/`.
3. Approve macOS automation prompt on first use.

For local testing:

```bash
claude --plugin-dir ./cowork-plugin
```

If your binary is not at `/usr/local/bin/omnifocus-mcp`, update `cowork-plugin/.mcp.json`.

## Notes

- First run prompts macOS automation permission.
- OmniFocus must launch in the current logged-in user session.
- If OmniFocus path differs, set `OF_APP_PATH`.
- If Omni Automation API is unavailable, set `OF_BACKEND=jxa`.
- launchd agent path: `~/Library/LaunchAgents/com.omnifocus-cli.daemon.plist`.
- launchd installs/uninstalls target the current user domain (`gui/<uid>`).

// Tool definitions for all 84 OmniFocus MCP tools.

nonisolated(unsafe) public let allTools: [ToolDefinition] = [
    ToolDefinition(
        name: "omnifocus_list_tasks",
        description: "List tasks with optional filters.",
        inputSchema: [
            "type": "object",
            "properties": [
                "status": ["type": "string", "enum": ["all", "available", "completed"]],
                "project": ["type": "string"],
                "tag": ["type": "string"],
                "search": ["type": "string"],
                "flagged": ["type": "boolean"],
                "limit": ["type": "integer", "minimum": 1]
            ]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_list_inbox",
        description: "List tasks in the OmniFocus inbox.",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_list_projects",
        description: "List all projects.",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_list_tags",
        description: "List all tags.",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_list_perspectives",
        description: "List all perspectives.",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_list_folders",
        description: "List all folders.",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_create_folder",
        description: "Create a new folder.",
        inputSchema: [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "note": ["type": "string"],
                "parent": ["type": "string"],
                "parentId": ["type": "string"]
            ],
            "required": ["name"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_move_project",
        description: "Move a project to a folder.",
        inputSchema: [
            "type": "object",
            "properties": [
                "projectId": ["type": "string"],
                "folder": ["type": "string"],
                "folderId": ["type": "string"],
                "createMissingFolder": ["type": "boolean"]
            ],
            "required": ["projectId"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_list_flagged",
        description: "List flagged tasks.",
        inputSchema: [
            "type": "object",
            "properties": [
                "limit": ["type": "integer", "minimum": 1]
            ]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_list_overdue",
        description: "List overdue tasks.",
        inputSchema: [
            "type": "object",
            "properties": [
                "limit": ["type": "integer", "minimum": 1],
                "includeCompleted": ["type": "boolean"]
            ]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_list_available",
        description: "List available tasks.",
        inputSchema: [
            "type": "object",
            "properties": [
                "limit": ["type": "integer", "minimum": 1],
                "includeCompleted": ["type": "boolean"]
            ]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_search_tasks",
        description: "Search tasks by name or note.",
        inputSchema: [
            "type": "object",
            "properties": [
                "search": ["type": "string"],
                "status": ["type": "string", "enum": ["all", "available", "completed"]],
                "project": ["type": "string"],
                "tag": ["type": "string"],
                "limit": ["type": "integer", "minimum": 1]
            ],
            "required": ["search"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_list_task_children",
        description: "List children of a task by id.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_get_task_parent",
        description: "Get the parent of a task by id.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_process_inbox",
        description: "Process inbox tasks with optional updates and move to a project.",
        inputSchema: [
            "type": "object",
            "properties": [
                "project": ["type": "string"],
                "projectId": ["type": "string"],
                "tags": ["type": "array", "items": ["type": "string"]],
                "due": ["type": "string", "description": "ISO 8601 date"],
                "defer": ["type": "string", "description": "ISO 8601 date"],
                "flagged": ["type": "boolean"],
                "estimatedMinutes": ["type": "integer"],
                "noteAppend": ["type": "string"],
                "limit": ["type": "integer", "minimum": 1],
                "createMissingTags": ["type": "boolean"],
                "createMissingProject": ["type": "boolean"],
                "keepInInbox": ["type": "boolean"]
            ]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_set_project_sequential",
        description: "Set a project's sequencing (sequential vs parallel).",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "sequential": ["type": "boolean"]
            ],
            "required": ["id", "sequential"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_eval_automation",
        description: "Evaluate Omni Automation JavaScript inside OmniFocus. DANGER: executes arbitrary code with full read/write/delete access to ALL OmniFocus data. This is an unrestricted code execution tool — use only when no other tool can accomplish the task. Never pass untrusted or user-generated input as the script parameter. Destructive operations (delete, drop, remove) are blocked by default — pass allowDestructive: true to permit them.",
        inputSchema: [
            "type": "object",
            "properties": [
                "script": ["type": "string", "description": "Omni Automation JavaScript to evaluate"],
                "parseJson": ["type": "boolean", "description": "Parse JSON output if possible"],
                "allowDestructive": ["type": "boolean", "description": "Allow destructive operations (delete, drop, remove) in the script. Default: false."]
            ],
            "required": ["script"]
        ],
        annotations: destructiveAnnotation.merging(["title": "Evaluate Omni Automation Script"]) { _, new in new }
    ),
    ToolDefinition(
        name: "omnifocus_get_task",
        description: "Get a task by OmniFocus id.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_get_project",
        description: "Get a project by OmniFocus id.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_get_tag",
        description: "Get a tag by OmniFocus id.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_create_task",
        description: "Create a new task in the inbox or a project.",
        inputSchema: [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "note": ["type": "string"],
                "project": ["type": "string"],
                "tags": ["type": "array", "items": ["type": "string"]],
                "due": ["type": "string", "description": "ISO 8601 date"],
                "defer": ["type": "string", "description": "ISO 8601 date"],
                "planned": ["type": "string", "description": "ISO 8601 planned date (v4.7+), or null to clear"],
                "flagged": ["type": "boolean"],
                "estimatedMinutes": ["type": "integer"],
                "sequential": ["type": "boolean", "description": "For task groups: children must be done in order"],
                "completedByChildren": ["type": "boolean", "description": "Auto-complete when all children done"],
                "shouldUseFloatingTimeZone": ["type": "boolean", "description": "Use floating time zone for dates"],
                "inbox": ["type": "boolean"],
                "createMissingTags": ["type": "boolean"],
                "createMissingProject": ["type": "boolean"]
            ],
            "required": ["name"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_create_project",
        description: "Create a new project.",
        inputSchema: [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "note": ["type": "string"],
                "due": ["type": "string", "description": "ISO 8601 date"],
                "defer": ["type": "string", "description": "ISO 8601 date"],
                "flagged": ["type": "boolean"],
                "estimatedMinutes": ["type": "integer"],
                "sequential": ["type": "boolean", "description": "Tasks must be completed in order"],
                "containsSingletonActions": ["type": "boolean", "description": "Single-action list (no next action)"],
                "reviewInterval": ["type": "object", "properties": ["steps": ["type": "integer"], "unit": ["type": "string", "enum": ["days", "weeks", "months", "years"]]], "description": "Review interval"],
                "shouldUseFloatingTimeZone": ["type": "boolean", "description": "Use floating time zone for dates"]
            ],
            "required": ["name"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_create_tag",
        description: "Create a new tag.",
        inputSchema: [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "active": ["type": "boolean"]
            ],
            "required": ["name"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_update_task",
        description: "Update an existing task by id.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string"],
                "note": ["type": "string"],
                "project": ["type": "string"],
                "tags": ["type": "array", "items": ["type": "string"]],
                "due": ["type": "string", "description": "ISO 8601 date"],
                "defer": ["type": "string", "description": "ISO 8601 date"],
                "planned": ["type": "string", "description": "ISO 8601 planned date (v4.7+), or null to clear"],
                "flagged": ["type": "boolean"],
                "estimatedMinutes": ["type": "integer"],
                "sequential": ["type": "boolean", "description": "For task groups: children must be done in order"],
                "completedByChildren": ["type": "boolean", "description": "Auto-complete when all children done"],
                "shouldUseFloatingTimeZone": ["type": "boolean", "description": "Use floating time zone for dates"],
                "createMissingTags": ["type": "boolean"],
                "createMissingProject": ["type": "boolean"]
            ],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_update_project",
        description: "Update an existing project by id.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string"],
                "note": ["type": "string"],
                "due": ["type": "string", "description": "ISO 8601 date"],
                "defer": ["type": "string", "description": "ISO 8601 date"],
                "flagged": ["type": "boolean"],
                "estimatedMinutes": ["type": "integer"],
                "sequential": ["type": "boolean", "description": "Tasks must be completed in order"],
                "containsSingletonActions": ["type": "boolean", "description": "Single-action list"],
                "reviewInterval": ["type": "object", "properties": ["steps": ["type": "integer"], "unit": ["type": "string", "enum": ["days", "weeks", "months", "years"]]], "description": "Review interval"],
                "shouldUseFloatingTimeZone": ["type": "boolean", "description": "Use floating time zone for dates"]
            ],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_update_tag",
        description: "Update an existing tag by id.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string"],
                "active": ["type": "boolean"],
                "allowsNextAction": ["type": "boolean", "description": "Whether tasks with this tag are considered for next action"]
            ],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_complete_task",
        description: "Mark a task complete by id.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "completionDate": ["type": "string", "description": "ISO 8601 date"]
            ],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_complete_project",
        description: "Mark a project complete by id.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "completionDate": ["type": "string", "description": "ISO 8601 date"]
            ],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_delete_task",
        description: "Delete a task by id.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: destructiveAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_delete_project",
        description: "Delete a project by id.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: destructiveAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_delete_tag",
        description: "Delete a tag by id.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: destructiveAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_uncomplete_task",
        description: "Mark a task incomplete (undo completion) by id.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_uncomplete_project",
        description: "Mark a project active again (undo completion) by id.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_append_to_note",
        description: "Append text to the note of a task or project.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "type": ["type": "string", "enum": ["task", "project"]],
                "text": ["type": "string"]
            ],
            "required": ["id", "text"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_search_tags",
        description: "Search tags by name (case-insensitive substring).",
        inputSchema: [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Substring to match against tag names"]
            ],
            "required": ["query"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_set_project_status",
        description: "Set a project's status to active, on_hold, or dropped.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "status": ["type": "string", "enum": ["active", "on_hold", "dropped"]]
            ],
            "required": ["id", "status"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_get_folder",
        description: "Get a folder by id or name, including its projects and subfolders.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string"]
            ]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_update_folder",
        description: "Update a folder's name by id.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string"]
            ],
            "required": ["id", "name"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_delete_folder",
        description: "Delete a folder by id. WARNING: irreversibly deletes the folder and ALL contained projects and their tasks.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: destructiveAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_get_task_counts",
        description: "Get aggregate task counts: total, available, completed, overdue, flagged, inbox.",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_get_project_counts",
        description: "Get aggregate project counts: total, active, on_hold, dropped, stalled.",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_get_forecast",
        description: "Get forecast view: overdue, today, flagged, and due this week task lists.",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_create_subtask",
        description: "Create a subtask under an existing task.",
        inputSchema: [
            "type": "object",
            "properties": [
                "parentId": ["type": "string"],
                "name": ["type": "string"],
                "note": ["type": "string"],
                "tags": ["type": "array", "items": ["type": "string"]],
                "due": ["type": "string", "description": "ISO 8601 date"],
                "defer": ["type": "string", "description": "ISO 8601 date"],
                "planned": ["type": "string", "description": "ISO 8601 planned date (v4.7+)"],
                "flagged": ["type": "boolean"],
                "estimatedMinutes": ["type": "integer"],
                "sequential": ["type": "boolean"],
                "completedByChildren": ["type": "boolean"],
                "createMissingTags": ["type": "boolean"]
            ],
            "required": ["parentId", "name"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_duplicate_task",
        description: "Duplicate a task, optionally with a new name.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string", "description": "Optional new name for the duplicate"]
            ],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_create_tasks_batch",
        description: "Create multiple tasks in one call.",
        inputSchema: [
            "type": "object",
            "properties": [
                "tasks": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "project": ["type": "string"],
                            "note": ["type": "string"],
                            "tags": ["type": "array", "items": ["type": "string"]],
                            "due": ["type": "string"],
                            "defer": ["type": "string"],
                            "flagged": ["type": "boolean"],
                            "estimatedMinutes": ["type": "integer"]
                        ],
                        "required": ["name"]
                    ]
                ]
            ],
            "required": ["tasks"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_delete_tasks_batch",
        description: "Delete multiple tasks by id in one call.",
        inputSchema: [
            "type": "object",
            "properties": [
                "ids": ["type": "array", "items": ["type": "string"]]
            ],
            "required": ["ids"]
        ],
        annotations: destructiveAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_move_tasks_batch",
        description: "Move multiple tasks to a project in one call.",
        inputSchema: [
            "type": "object",
            "properties": [
                "ids": ["type": "array", "items": ["type": "string"]],
                "project": ["type": "string", "description": "Project name to move tasks to"]
            ],
            "required": ["ids", "project"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_list_notifications",
        description: "List alarms/notifications on a task.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_add_notification",
        description: "Add an absolute-date alarm/notification to a task.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "date": ["type": "string", "description": "ISO 8601 date for the alarm"]
            ],
            "required": ["id", "date"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_remove_notification",
        description: "Remove an alarm/notification from a task.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Task id"],
                "notificationId": ["type": "string", "description": "Notification id to remove"]
            ],
            "required": ["id", "notificationId"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_set_task_repetition",
        description: "Set or clear the repetition rule on a task using iCal RRULE format.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "rule": ["type": "string", "description": "iCal RRULE string, e.g. FREQ=WEEKLY;INTERVAL=1, or null to clear"],
                "scheduleType": ["type": "string", "enum": ["due", "defer", "fixed"], "description": "How the repetition is scheduled"],
                "anchorDateKey": ["type": "string", "enum": ["due", "defer", "planned"], "description": "v4.7+: which date anchors repetition"],
                "catchUpAutomatically": ["type": "boolean", "description": "Whether missed repetitions should catch up"]
            ],
            "required": ["id", "rule"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_mark_reviewed",
        description: "Mark a project as reviewed (updates lastReviewDate to now).",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_drop_task",
        description: "Drop a task (mark as dropped without deleting). Preserves the task unlike delete.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_import_taskpaper",
        description: "Import tasks from TaskPaper-formatted text into the inbox or a project.",
        inputSchema: [
            "type": "object",
            "properties": [
                "text": ["type": "string", "description": "TaskPaper-formatted text to import"],
                "project": ["type": "string", "description": "Optional project name to import into"]
            ],
            "required": ["text"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_add_relative_notification",
        description: "Add a relative-time notification to a task (fires N seconds before due date).",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Task id"],
                "beforeSeconds": ["type": "number", "description": "Seconds before due date to fire (e.g. 3600 = 1 hour before)"]
            ],
            "required": ["id", "beforeSeconds"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_move_tag",
        description: "Move a tag under a different parent tag, or to the root level.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Tag id to move"],
                "parentTag": ["type": "string", "description": "Parent tag name, or omit/null for root"]
            ],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_move_folder",
        description: "Move a folder under a different parent folder, or to the root level.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Folder id to move"],
                "parentFolder": ["type": "string", "description": "Parent folder name, or omit/null for root"]
            ],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_convert_task_to_project",
        description: "Convert a task (and its children) into a project.",
        inputSchema: [
            "type": "object",
            "properties": ["id": ["type": "string"]],
            "required": ["id"]
        ],
        annotations: destructiveAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_duplicate_project",
        description: "Duplicate a project, optionally with a new name.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string", "description": "Optional new name for the duplicate"]
            ],
            "required": ["id"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_get_forecast_tag",
        description: "Get the forecast tag (OmniAutomation only, v4.5+). Returns null in JXA.",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_clean_up",
        description: "Run OmniFocus clean-up (compact database / hide completed items).",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        annotations: destructiveAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_get_settings",
        description: "Retrieve OmniFocus application settings. Pass specific keys to read their values.",
        inputSchema: [
            "type": "object",
            "properties": [
                "keys": ["type": "array", "items": ["type": "string"], "description": "Setting keys to retrieve"]
            ]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_list_linked_files",
        description: "List linked file URLs attached to a task.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Task id"]
            ],
            "required": ["id"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_add_linked_file",
        description: "Add a linked file URL to a task.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Task id"],
                "url": ["type": "string", "description": "File URL to link"]
            ],
            "required": ["id", "url"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_remove_linked_file",
        description: "Remove a linked file URL from a task.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Task id"],
                "url": ["type": "string", "description": "File URL to remove"]
            ],
            "required": ["id", "url"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_search_projects",
        description: "Search projects by name using native database search when available.",
        inputSchema: [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Search query"]
            ],
            "required": ["query"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_search_folders",
        description: "Search folders by name using native database search when available.",
        inputSchema: [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Search query"]
            ],
            "required": ["query"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_search_tasks_native",
        description: "Search tasks using native database search (database.tasksMatching) when available, with manual fallback.",
        inputSchema: [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Search query"]
            ],
            "required": ["query"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_lookup_url",
        description: "Look up an OmniFocus object by its URL (omnifocus:///task/ID, etc). Returns the serialized object.",
        inputSchema: [
            "type": "object",
            "properties": [
                "url": ["type": "string", "description": "OmniFocus URL to look up"]
            ],
            "required": ["url"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_get_forecast_days",
        description: "Get forecast day objects for upcoming days, including badge counts and deferred counts.",
        inputSchema: [
            "type": "object",
            "properties": [
                "count": ["type": "integer", "description": "Number of days to retrieve (default 14)"]
            ]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_get_focus",
        description: "Get currently focused projects and folders.",
        inputSchema: [
            "type": "object",
            "properties": [:]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_set_focus",
        description: "Set focus to specific projects/folders, or pass empty ids array to unfocus.",
        inputSchema: [
            "type": "object",
            "properties": [
                "ids": ["type": "array", "items": ["type": "string"], "description": "Array of project/folder ids to focus, or empty to unfocus"]
            ],
            "required": ["ids"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_undo",
        description: "Undo the last action in OmniFocus.",
        inputSchema: [
            "type": "object",
            "properties": [:]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_redo",
        description: "Redo the last undone action in OmniFocus.",
        inputSchema: [
            "type": "object",
            "properties": [:]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_save",
        description: "Save the OmniFocus database.",
        inputSchema: [
            "type": "object",
            "properties": [:]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_duplicate_tasks_batch",
        description: "Duplicate multiple tasks by their ids.",
        inputSchema: [
            "type": "object",
            "properties": [
                "ids": ["type": "array", "items": ["type": "string"], "description": "Task ids to duplicate"]
            ],
            "required": ["ids"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_duplicate_tags",
        description: "Duplicate multiple tags by their ids.",
        inputSchema: [
            "type": "object",
            "properties": [
                "ids": ["type": "array", "items": ["type": "string"], "description": "Tag ids to duplicate"]
            ],
            "required": ["ids"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_move_projects_batch",
        description: "Move multiple projects to a target folder.",
        inputSchema: [
            "type": "object",
            "properties": [
                "ids": ["type": "array", "items": ["type": "string"], "description": "Project ids to move"],
                "folder": ["type": "string", "description": "Target folder name"]
            ],
            "required": ["ids"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_reorder_task_tags",
        description: "Reorder tags on a task by removing all and re-adding in specified order.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Task id"],
                "tagIds": ["type": "array", "items": ["type": "string"], "description": "Ordered array of tag ids"]
            ],
            "required": ["id", "tagIds"]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_copy_tasks",
        description: "Copy tasks to the system pasteboard.",
        inputSchema: [
            "type": "object",
            "properties": [
                "ids": ["type": "array", "items": ["type": "string"], "description": "Task ids to copy"]
            ],
            "required": ["ids"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_paste_tasks",
        description: "Paste tasks from the system pasteboard into a project.",
        inputSchema: [
            "type": "object",
            "properties": [
                "project": ["type": "string", "description": "Target project name (optional, pastes to inbox if omitted)"]
            ]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_next_repetition_date",
        description: "Compute the next repetition date for a repeating task.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Task id"],
                "afterDate": ["type": "string", "description": "ISO 8601 date to compute next occurrence after (default: now)"]
            ],
            "required": ["id"]
        ],
        annotations: readOnlyAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_set_forecast_tag",
        description: "Set or clear the forecast tag. Pass a tag id to set, or null/empty to clear.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Tag id to set as forecast tag, or null to clear"]
            ]
        ],
        annotations: mutatingAnnotation
    ),
    ToolDefinition(
        name: "omnifocus_set_notification_repeat",
        description: "Set the repeat interval on an existing notification/alarm.",
        inputSchema: [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Task id"],
                "notificationId": ["type": "string", "description": "Notification id"],
                "repeatInterval": ["type": "number", "description": "Repeat interval in seconds (0 to disable)"]
            ],
            "required": ["id", "notificationId", "repeatInterval"]
        ],
        annotations: mutatingAnnotation
    )
]


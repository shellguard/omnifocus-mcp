---
name: inbox-processing
description: >
  Clarify and process items in the OmniFocus inbox using the GTD model.
  Use when the user wants to "process the inbox", "clean up inbox", "clarify",
  "triage", or asks to assign projects, tags, or dates to inbox items.
---

GTD inbox clarification. For each inbox item, decide one of:

- **Actionable now** → assign project + tags + dates, then move out of inbox.
- **Reference / someday** → either move to a reference project or drop with a note. Don't bulk-defer to "someday" by accident.
- **Trash** → drop or delete.
- **Ambiguous** → leave in inbox with a note describing what's unclear, so the user can come back to it.

Workflow:

1. Call `omnifocus_list_inbox` to fetch items.
2. For each item, propose a classification + concrete fields (project, tags, due/defer/planned). Ask the user to confirm in batches if there are many.
3. Apply with `omnifocus_update_tasks_batch` for actionable items (set `project`, `tags`, dates in one shot). Use `createMissingProject: true` / `createMissingTags: true` only when the user has approved the project/tag name.
4. For drops, use `omnifocus_drop_task`. For trash, use `omnifocus_delete_task`.
5. For "do it now < 2 minutes" items, suggest the user do it instead of filing it.

**Date semantics** when assigning:
- `due` — only for items with a real deadline.
- `planned` — for "I want to do this on day X" intent.
- `defer` — to hide an item until it becomes relevant.

Don't assume defaults. If a project or date isn't obvious from the task name, ask before guessing — bad inbox processing is worse than slow inbox processing.

Confirm at the end with a one-line summary, e.g. "Processed 7 items: 4 to projects, 2 dropped, 1 left in inbox for review."

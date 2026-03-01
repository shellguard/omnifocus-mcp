---
name: capture-tasks
description: >
  Capture tasks, reminders, or action items into OmniFocus. Use this skill
  when the user mentions something they need to do, remember, follow up on,
  or get done — even if they don't explicitly say "add to OmniFocus".
  Also use when the user asks to add, create, save, or log a task.
---

When the user describes something that needs to be done or remembered:

1. Extract the task name, and any details mentioned (project, due date, defer date, tags, priority/flagged, estimated time, notes).
2. If a project is mentioned and you're unsure of the exact name, use `omnifocus_list_projects` to find it first.
3. Use `omnifocus_create_task` to capture it. Put it in the inbox if no project is clear.
4. For multiple items in one message, use `omnifocus_create_tasks_batch` to capture them all at once.
5. Confirm what was captured with a brief summary.

Keep confirmations short. Don't ask for information that wasn't provided — capture what you have and move on.

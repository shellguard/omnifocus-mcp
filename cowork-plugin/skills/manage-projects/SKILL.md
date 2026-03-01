---
name: manage-projects
description: >
  Help the user manage their OmniFocus projects: create, update, review status,
  change status, move to folders, or get an overview. Use when the user asks
  about projects, wants to create a project, or wants to reorganise their work.
---

When the user wants to work with projects:

**Reviewing projects:**
- Use `omnifocus_get_project_counts` for a quick overview (active, stalled, on hold, dropped).
- Use `omnifocus_list_projects` to list all projects when the user wants details.
- Highlight stalled projects (active but no available next actions) — these often need attention.

**Creating projects:**
- Use `omnifocus_create_project` with name, note, due date, and folder as provided.
- After creating, offer to add initial tasks using `omnifocus_create_tasks_batch`.

**Updating projects:**
- Use `omnifocus_set_project_status` to mark projects active, on hold, or dropped.
- Use `omnifocus_update_project` to rename or update due dates.
- Use `omnifocus_move_project` to organise into folders.

**Stalled projects:**
- When a project is stalled, offer to add a next action with `omnifocus_create_task`.

Keep responses action-oriented. If the user seems overwhelmed by a list, offer to help prioritise or clean up.

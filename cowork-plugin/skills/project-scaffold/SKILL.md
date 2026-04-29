---
name: project-scaffold
description: >
  Turn a goal or outcome into an OmniFocus project with initial structure.
  Use when the user says "I need to start a project for X", "set up a project",
  "break this goal down", or describes an outcome that doesn't fit in a single task.
---

Help the user go from a goal to a structured project they can actually start working.

1. **Clarify the outcome**: what does "done" look like? One sentence. If unclear, ask once.

2. **Pick the project shape**:
   - **Sequential** — tasks must be done in order. Use for processes (onboard new hire, file taxes).
   - **Parallel** — tasks can be done in any order. Default for most projects.
   - **Single-action list** — bucket of unrelated tasks (Errands, Misc Admin). Set `containsSingletonActions: true`.

3. **Decide placement**:
   - Folder — ask if they have a relevant folder, or use `omnifocus_list_folders` to suggest one.
   - Review interval — propose `weekly` for active outcomes, `monthly` for slow-burn projects.
   - Planned date — if they have an intended start week. Don't set `due` unless the outcome has a real deadline.

4. **Create the project** with `omnifocus_create_project`, then if non-default, `omnifocus_set_project_sequential`.

5. **Add initial tasks** with `omnifocus_create_tasks_batch`. Aim for 3–7 concrete next actions, not 30 — projects with too many speculative tasks get abandoned. The first task should be doable today; phrase it as a verb-led action ("Email Sara about timeline", not "Timeline").

6. **Confirm**: one-line summary of project name, shape, folder, review interval, and number of initial tasks.

Avoid:
- Auto-generating large task trees from thin descriptions. Better to start with a few clear next actions and let the user grow it.
- Setting `due` dates speculatively. Use `planned` if there's intent but no deadline.
- Creating new folders without asking.

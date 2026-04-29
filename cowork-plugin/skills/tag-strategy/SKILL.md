---
name: tag-strategy
description: >
  Help the user design and maintain a useful OmniFocus tag taxonomy.
  Use when the user asks about tags, contexts, organizing by tag, or wants
  to clean up or rationalize existing tags.
---

Tags in OmniFocus are most useful when each tag means one specific thing. Common axes — pick the ones that match how the user actually decides what to work on:

- **Context / location** — `@home`, `@office`, `@errands`, `@phone`, `@computer`.
- **Energy** — `Deep Work`, `Low Energy`, `Quick Wins`.
- **Tool** — `iPad`, `Terminal`, `Editor`, `Browser`.
- **Person** — `Waiting: Sara`, `1:1 with Boss`, `@Family`.
- **Time of day** — `Morning`, `Evening`. Use sparingly; defer dates often work better.
- **Status** — `Waiting`, `Someday`.

**Mutually exclusive tag groups (4.7+)**

OmniFocus 4.7+ supports `childrenAreMutuallyExclusive` on parent tags — only one child can apply at a time. Good for axes where overlapping values don't make sense:

- Energy levels (`Deep Work` vs `Low Energy`).
- Time of day (`Morning` vs `Evening`).
- Effort estimate buckets (`<5min`, `15min`, `1hr+`).

When creating or updating a parent tag, set `childrenAreMutuallyExclusive: true` via `omnifocus_create_tag` or `omnifocus_update_tag`.

**Workflow when the user wants to clean up tags**:

1. `omnifocus_list_tags` to see what exists.
2. Look for redundancy (`Phone` vs `Calls`), one-off tags, and misuse (tag-as-project).
3. Use `omnifocus_list_untagged` to find available tasks that lack tags — these often need context to be findable.
4. To merge or rename, `omnifocus_update_tag` for renames; for merges, retag affected tasks via `omnifocus_update_tasks_batch` then `omnifocus_delete_tag`.

Avoid:
- More than ~20 active tags. Tag fatigue makes the system worse, not better.
- Tags that duplicate folder/project structure ("Project: Foo").
- Adding `childrenAreMutuallyExclusive` retroactively to a populated parent without warning the user — existing tasks may lose tags silently.

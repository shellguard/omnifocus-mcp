---
name: system-cleanup
description: >
  Maintenance pass on the OmniFocus database to find and clear stale state.
  Use when the user says "clean up OmniFocus", "my system feels stale",
  "everything is overdue", or wants to do periodic hygiene.
---

A stale OmniFocus database is one the user no longer trusts. The fix is to surface the rot, not hide it.

Walk the user through these checks in order. Pause for input after each — many of these are judgment calls, not bulk operations.

**1. Old overdue items**
- `omnifocus_list_overdue`. Tasks overdue by weeks usually mean the deadline was wrong, not the work. Offer to: complete (if actually done), reschedule (`due` or `planned` via `omnifocus_update_tasks_batch`), or drop.

**2. Deferred items that surfaced and were ignored**
- `omnifocus_list_available` — items that became available days/weeks ago but haven't been touched. These are common signs of "I deferred this hoping it would go away".

**3. Untagged available tasks**
- `omnifocus_list_untagged`. Without tags, available tasks rarely surface in context filters. Either tag, or ask whether the task still matters.

**4. Stalled active projects**
- `omnifocus_list_stalled_projects`. Add a next action, on-hold, or drop.

**5. Projects with no review date**
- `omnifocus_list_projects` and look for entries with no `nextReviewDate`. Set a review interval via `omnifocus_update_project` (weekly for active outcomes is a sensible default).

**6. Completed / dropped clutter**
- `omnifocus_clean_up` — the built-in clean-up moves completed items out of active views. Mention this rather than calling it without consent (it's UI-affecting).

**Output style**:
- Counts first (e.g. "12 overdue, 8 untagged available, 3 stalled").
- Then walk the user through each section, offering specific actions per item.
- End with a one-line summary of what changed.

Avoid:
- Bulk-completing or bulk-dropping without explicit confirmation per batch.
- Auto-rescheduling overdue items into the future — that's how trust gets broken.
- Touching `omnifocus_clean_up` silently.

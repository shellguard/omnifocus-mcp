---
name: weekly-review
description: >
  Run a structured GTD weekly review of OmniFocus projects. Use when the user
  asks for a "weekly review", "project review", or wants to walk through
  projects that need attention.
---

A weekly review is the GTD ritual that keeps the system trustworthy. Walk the user through projects in this order:

**1. Projects due for review**
- Call `omnifocus_list_review_due` (returns active projects whose `nextReviewDate <= now`).
- For each project: confirm purpose still applies, identify the next action, decide active / on-hold / dropped, then call `omnifocus_mark_reviewed` to update `lastReviewDate`.

**2. Stalled projects**
- Call `omnifocus_list_stalled_projects` (active projects with no available next action).
- For each: offer to add a next action with `omnifocus_create_task`, or mark on-hold / dropped via `omnifocus_set_project_status`.

**3. Inbox sweep**
- Call `omnifocus_list_inbox`. If non-empty, hand off to inbox processing.

**4. Overdue & flagged**
- Call `omnifocus_get_forecast`. For overdue: complete, reschedule, or drop each. For flagged: confirm still relevant.

**5. Tag hygiene** (optional)
- Use `omnifocus_list_untagged` to find available tasks with no tags. Tags drive context filtering, so untagged available tasks tend to fall through the cracks.

Pace yourself: pause after each section and let the user respond before moving on. The review can take 30+ minutes — don't try to finish in one response. If the user runs out of energy, save state implicitly (every `mark_reviewed` is durable) and offer to resume later.

Avoid:
- Auto-marking projects reviewed without showing them.
- Bulk operations that hide individual judgment calls.
- Pushing the user to commit to dates they didn't ask for.

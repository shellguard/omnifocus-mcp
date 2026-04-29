---
name: check-workload
description: >
  Check the user's current tasks, workload, or what they have on their plate.
  Use when the user asks what they need to do, what's due, what's overdue,
  what's coming up, how busy they are, or wants a summary of their work.
---

When the user wants to understand their current workload or task situation:

1. Start with `omnifocus_get_forecast` — it returns seven lists in one call: `overdue`, `today`, `flagged`, `dueThisWeek`, `plannedToday`, `plannedSoon`, and `forecastTagged` (tasks carrying the user's Forecast tag).
2. Use `omnifocus_get_task_counts` for a numeric summary if helpful.
3. If they ask about a specific project or tag, use `omnifocus_list_tasks` filtered by `project` or `tag`.

Present the information so each task only appears once. Order:

- Lead with **Overdue**.
- Then **Due today**.
- Then **Planned today** (intended-work-date today — OmniFocus 4.7+ semantics).
- Then **Forecast-tagged** tasks not already listed.
- Then **Flagged** tasks not already listed.
- Then **Due this week** and **Planned soon** as a forward look.

Keep entries to one line. Don't list every field unless asked. Offer to help reschedule, plan, or take action on specific items.

**Date semantics** (don't conflate them):
- `due` — real deadline. Use sparingly.
- `planned` — intended work date. Use for "I'd like to do this on X".
- `defer` — hide until X.

If the user describes intent ("I'd like to work on this Friday"), prefer `planned` over `due`.

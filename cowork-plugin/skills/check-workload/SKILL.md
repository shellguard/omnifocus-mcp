---
name: check-workload
description: >
  Check the user's current tasks, workload, or what they have on their plate.
  Use when the user asks what they need to do, what's due, what's overdue,
  what's coming up, how busy they are, or wants a summary of their work.
---

When the user wants to understand their current workload or task situation:

1. Start with `omnifocus_get_forecast` to get overdue, today, flagged, and due-this-week tasks in one call.
2. Use `omnifocus_get_task_counts` to give a quick numeric summary if helpful.
3. If they ask about a specific project, use `omnifocus_list_tasks` filtered by project.
4. If they ask about a specific tag or area, filter by tag.

Present the information clearly:
- Lead with anything overdue (these need attention first).
- Then today's tasks.
- Then flagged items not yet due today.
- Keep the summary concise — don't list every field of every task unless asked.
- Offer to help prioritise, reschedule, or take action on specific items.

---
description: Show your OmniFocus forecast — overdue, today, and flagged tasks
---

Show the user their OmniFocus forecast using `omnifocus_get_forecast`.

Present it in this order:
1. **Overdue** — list each task with its due date. Flag this section if non-empty.
2. **Due today** — list tasks due today.
3. **Flagged** — list flagged tasks not already shown above.
4. **Due this week** — list remaining tasks due in the next 7 days.

Keep each task to one line: name and due date only. Skip empty sections.
End with a one-line summary count, e.g. "3 overdue · 5 due today · 2 flagged".

If everything is empty, say so briefly and offer to help plan the day.

---
description: Run a quick OmniFocus review — inbox, overdue, stalled projects
---

Run a structured OmniFocus review in three parts:

**1. Inbox**
Call `omnifocus_list_inbox`. If there are items, list them and ask whether to process them (assign projects, tags, due dates) or leave for later.

**2. Overdue & today**
Call `omnifocus_get_forecast`. List overdue tasks first, then today's. For each overdue task, ask: complete it, reschedule it, or drop it?

**3. Projects**
Call `omnifocus_get_project_counts` and `omnifocus_list_projects`. Flag any stalled projects (active but no next action). Offer to add a next action for each stalled project.

After each section, pause and let the user respond before moving on. Keep the tone practical and focused on clearing blockers.

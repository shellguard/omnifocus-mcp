---
description: Show your OmniFocus forecast — overdue, today, planned, flagged, and forecast-tag tasks
---

Show the user their OmniFocus forecast using `omnifocus_get_forecast`.

The result has seven lists. Render only non-empty sections in this order:
1. **Overdue** — `overdue`. Flag this section.
2. **Due today** — `today`.
3. **Planned today** — `plannedToday` (intended-work-date today, OmniFocus 4.7+).
4. **Forecast tag** — `forecastTagged` (tasks carrying the user's Forecast tag, not already listed above).
5. **Flagged** — `flagged`, excluding entries already shown.
6. **Due this week** — `dueThisWeek`.
7. **Planned soon** — `plannedSoon`.

Keep each task to one line: name plus due date or planned date. Don't list a task in more than one section — first match wins.
End with a one-line summary count, e.g. "3 overdue · 5 due today · 2 planned · 4 flagged".

If everything is empty, say so briefly and offer to help plan the day.

Date semantics reminder when offering help: `due` is a real deadline, `planned` is an intended work date, `defer` hides until a date.

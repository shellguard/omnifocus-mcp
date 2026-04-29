---
name: date-semantics
description: >
  Reference for OmniFocus 4.7+ date semantics: due, planned, defer.
  Use when assigning dates, when the user says "schedule", "remind me", or
  any time it would otherwise be tempting to overload `due` for non-deadlines.
---

OmniFocus 4.7+ has three distinct date fields with different semantics. Pick deliberately.

**`due` — real deadline**
- Use only when missing the date has a real consequence (meeting, flight, court date, hard external commitment).
- Don't use `due` for "I'd like to get this done by". That overloads the Forecast view with false alarms and trains the user to ignore overdue.
- The Forecast view's "overdue" and "today" lists are driven by `due`.

**`planned` — intended work date** (4.7+)
- Use for "I want to work on this on Friday", "my plan is to tackle this Tuesday morning", "schedule it for next week".
- Surfaces in `plannedToday` / `plannedSoon` in `omnifocus_get_forecast`.
- Doesn't create urgency or overdue alarms — it's a planning aid, not a deadline.

**`defer` — hide-until date**
- Use for "remind me about this on X", "this isn't actionable until Y", "follow up next month".
- A deferred task is unavailable until the defer date passes — it disappears from available views.

**Repeat anchor (4.7+)**
- `omnifocus_set_task_repetition` accepts `anchorDateKey`: which of `due` / `defer` / `planned` should drive the next occurrence.
- Pick `due` for hard deadlines that recur (rent), `defer` for hidden-until-needed recurrences (replace filter every 90 days), `planned` for habits (write blog post weekly).

**Floating time zones**
- For dates that should fire at the same wall time anywhere (e.g., "9am every weekday"), pass `shouldUseFloatingTimeZone: true`.

**Picking among them — quick test**:
- Will the world penalize the user for missing the date? → `due`.
- Does the task literally not apply until the date? → `defer`.
- Otherwise → `planned`.

When the user says "schedule X for Friday" without context, ask: deadline, intent, or hide-until? Defaulting to `due` is the most common mistake.

---
name: routines
description: >
  Help the user set up recurring tasks and routines in OmniFocus correctly.
  Use when the user mentions "every week", "monthly", "every Tuesday",
  "recurring", "habit", "routine", "every N days".
---

OmniFocus 4.7+ has rich repeat semantics. The defaults are usually wrong for habits — pick deliberately.

**Repeat method** (passed to `omnifocus_set_task_repetition` as `rule.method`):

- **`fixed`** — next occurrence is computed from the previous one's anchor date, regardless of when it was completed. Use for true schedules (rent, billing, weekly meeting).
- **`start-after-completion`** — defer/start date moves N units after completion. Use for "every N days after I last did it" (replace filter, water plants).
- **`due-after-completion`** — due date moves N units after completion. Use for "I have N days from when I finished last to do it again" (renew a license).

**Anchor date** (`anchorDateKey` — 4.7+):

Pick which date drives the next occurrence:
- `due` — for hard deadlines that recur (rent on the 1st).
- `defer` — for "hide until N days from now" recurrences (review my goals).
- `planned` — for habits with intent dates but no deadlines (write blog post weekly).

**Common routine patterns**:

| Routine | method | anchorDateKey |
|---|---|---|
| Pay rent on the 1st | `fixed` | `due` |
| Replace water filter every 90 days after I last did it | `start-after-completion` | `defer` |
| Write blog post weekly (intent, not deadline) | `fixed` | `planned` |
| Renew passport — start working on it 6 months before expiry | `fixed` | `defer` |

**End conditions**:
- `repetitionEndDate` — stop repeating after this date.
- `maxRepetitions` — stop after N occurrences.

**Avoid**:
- Putting recurrence on a parent task whose children also repeat — nested repetition rarely behaves intuitively.
- Using `due` for habits (creates phantom overdue items every cycle).
- `start-after-completion` for hard deadlines (skipping a cycle silently moves the deadline).

**Verify with `omnifocus_next_repetition_date`** — after setting up a rule, ask for the next computed occurrence to confirm it matches the user's expectation.

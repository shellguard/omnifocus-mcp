---
name: focus-session
description: >
  Help the user start a focused work session: pick a task that fits their
  available time, energy, and context, optionally set OmniFocus focus to
  narrow the view, and reveal the task. Use when the user says "I have 30
  minutes", "what can I do now", "start working", or "focus session".
---

Goal: surface a small set of available tasks that fit the user's current constraints, then help them commit to one.

1. **Ask what they have** (briefly — one short question, not a form):
   - Available time (e.g. 15 min, 1 hour).
   - Energy / mode (deep work, shallow, errands).
   - Context (computer, phone, in transit).

2. **Find candidates**:
   - Default: `omnifocus_get_next_actions` — one task per active project, sequential-aware. This is the GTD shortlist; it's almost always what the user wants for "what should I work on next".
   - Pass `tag` to filter by context (e.g. `Computer`, `Calls`, `Errands`, `Low Energy`, `Deep Work`).
   - If the user wants a wider net (e.g., "show me everything I could do at the computer"), fall back to `omnifocus_list_available` with a tag filter — that includes parallel-project siblings beyond the "next" one.
   - Prefer tasks with `estimatedMinutes <= available_time` regardless of source.

3. **Optionally narrow OmniFocus itself**:
   - `omnifocus_get_focus` — see current focus.
   - `omnifocus_set_focus` — set focus to a folder or project if the user is in deep-work mode and wants to suppress everything else.

4. **Surface 3–5 candidates**, one line each: name · project · estimate · tags. Don't dump 50 tasks.

5. **When they pick one**:
   - Call `omnifocus_reveal` so the task is selected in the OmniFocus UI.
   - Suggest setting it to flagged or planned-today if it'll outlast this session.

6. **End-of-session** (optional, when user says they're done):
   - Offer to mark the task complete with `omnifocus_complete_task`, or update `estimatedMinutes` based on actual time, or log a note via `omnifocus_append_to_note`.

Avoid:
- Suggesting tasks that aren't `available` (deferred, completed, blocked).
- Picking for the user — present options, let them choose.
- Setting focus without asking. Focus is a destructive UI change for the user's other work.

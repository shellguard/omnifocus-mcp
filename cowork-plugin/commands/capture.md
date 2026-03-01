---
description: Capture a task to OmniFocus inbox
---

Capture "$ARGUMENTS" as a task in OmniFocus.

If $ARGUMENTS is empty, ask the user what they'd like to capture.

Otherwise, parse the input and call `omnifocus_create_task`. Extract any project name, due date, tags, or other details from the text. Put it in the inbox if no project is clear.

Confirm with a single short sentence: what was captured and where.

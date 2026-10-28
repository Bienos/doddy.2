# Messages: finished tasks as cards

Owner, 28 Oct 2026: item 1, "task results as a Messages bubble", then "Do all".

- Tasks Doddy finished in the background this week (done or failed; not cancelled, not still running) show as cards under the thread, headed "Tasks Doddy finished", newest three, oldest first (`ThreadTaskResults.shown`).
- A tap opens the task's own result screen (`ErrandDetailView`), which marks it seen, as Home's card does.
- Read from this iPhone's copy of the tasks (`ErrandsModel.shared`, `ErrandRepository`). Nothing new is stored in the thread, nothing is sent, and no task is started from here.
- Tasks still need the server switched on (`ERRANDS_ENABLED=1`, a worker that doesn't sleep, `SERPER_API_KEY`); until then there are no results to show.

Not compiled, not run (no Swift or Xcode in this session): `ThreadTaskResultsTests` (3), the view. Not seen on a device. New strings ("Tasks Doddy finished", "Couldn't finish. See why.") are untranslated.

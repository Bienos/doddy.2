# Doddy on one page

*19 Oct 2026. Owner direction (ADR-540); targets are proposals. Full version: `STRATEGY.md`.*

**Who:** busy iPhone users in Poland with a pile of small errands and promises hanging over them.

**Problem:** sprawy slip. The return window closes, the bill is late, the friend is still waiting. Reminders come back with no context, and notes to yourself never come back at all.

**Doddy:** a pomocnik, not a companion.
- You hand it a **sprawa** in one sentence: "Muszę oddać buty na Zalando do piątku."
- It keeps your exact words and asks one thing: "Mam ci przypomnieć w czwartek wieczorem?"
- It brings the sprawa back at that moment, with the next step ready.
- It acts only on your tap. One more tap, **Gotowe**, and it's logged done, with undo.

**Line:** Sharp online. Clumsy offline. Honest always.

**Why we win:**
- **It asks first and never fakes "done".** Every action waits for your tap, and "done" means you tapped Gotowe or the provider confirmed it.
- **It works in Polish now,** and still holds your sprawy without the internet, honestly plainer.
- **Several parts of the loop already exist:** the original text kept unchanged, local reminders with a Done button, ask-first cards and undo. Joining them is the work before the beta. The loop as one flow has never run on a device.

**Money:** the beta is free. Pricing comes after, with measured voice costs.

**Getting users:** 20 hand-picked Polish iPhone users, 2 weeks, private TestFlight. Each brings a real sprawa.

**What we're proving, and how we'll know** (thresholds proposed, owner sets them before the beta):
- **People hand it a sprawa on day 0:** at least 80% save their first sprawa on install day.
- **The bring-back works:** at least 50% close a sprawa after Doddy brought it back, in week one.
- **They keep using it:** at least 40% are active on 3 or more days in week two.

**The one thing we're not doing:** new features during the beta. Doddy proves one loop first.

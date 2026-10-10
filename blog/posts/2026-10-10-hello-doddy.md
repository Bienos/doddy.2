---
title: "Hello, Doddy: why our favourite first result was “I couldn’t find it”"
date: 2026-10-10
author: "The Doddy team"
status: published
summary: "Doddy is a hand-drawn mate for your iPhone that keeps the small things you ask it to keep. In its first real conversations it couldn't find a note, and said so. Here's why that matters, and what we fixed."
evidence:
  - docs/product/PRODUCT_REQUIREMENTS.md
  - docs/implementation/M1_STATUS.md
  - docs/implementation/V1_VOICE_STATUS.md
  - docs/implementation/BRANCH_CONSOLIDATION_2026-10-09.md
---

You know the parcel locker code. You knew it this morning. Now you're standing at the locker and
it's gone, along with the book a friend recommended last week and the wine you liked at that
dinner.

Most of us patch this with messages to ourselves, a Notes app full of half-sentences, or
screenshots we never find again. Doddy is our attempt at something friendlier: a small,
hand-drawn mate in your iPhone who keeps the things you ask it to keep, and gives you your exact
words back later.

This is the first post about building it: what Doddy is, what happened the first time we
actually talked to it, and what is and isn't working yet.

## Memory first, personality second

The easy version of this app would be a cute character attached to a chatbot. It would be fun
for a day. Then it would confidently "remember" a locker code you never gave it, and you'd stop
trusting it.

So we built it the other way round. Before the jokes and the animation, Doddy had to do one plain
thing reliably:

> **Tell Doddy before you forget. Find the original later.**

That comes with a few rules:

- **You choose what gets saved.** Doddy doesn't listen in the background or quietly collect notes
  from your conversations. Even when you're talking to it, nothing is stored until you tap
  **Save**.
- **"Saved" means saved.** The app only says a note is saved after it has been written to the
  phone and read back. If that fails, your text stays on screen.
- **Answers come from your notes.** Doddy shows the note you wrote, when you wrote it and which
  words matched. If nothing matches, it says it couldn't find it instead of making something up.
- **Your words are kept.** You can edit a note, and the original stays next to the edit.
- **You can leave with everything.** Export to JSON or plain text, delete one note, or delete them
  all.
- **No account.** Notes live on your iPhone. When you talk to Doddy, your voice goes to our voice
  provider, ElevenLabs, to run the conversation. The app says this up front.

## The first real conversation

On 9 October we had the first proper voice conversation with Doddy on an actual iPhone. It
lasted 79 seconds. It started in English, switched to Polish on its own when we did, and when we
said "Moje urodziny są jutro" ("my birthday is tomorrow") a **Save this note?** card popped up.
We tapped Save, and Doddy confirmed it only after the phone reported the note was stored.

A few minutes later we tried the obvious test. We had saved a code in Polish, spoken out loud, so
the note read *"Kod: pięć, sześć, siedem, osiem."* Then we asked, in English, "what code have you
saved?"

Doddy searched the phone four times across those conversations. Every time the answer was the
same: it couldn't find a matching note.

That was a failure, but the right kind. The note was there. The search just couldn't see it: we
asked in English, the note was in Polish, and the numbers were written as words. What Doddy
*didn't* do was guess. It didn't invent a code. If it had said "5678" because that sounded
plausible, the whole idea would be broken. A mate who makes things up is worse than a notebook.

We also caught a small honesty slip. Before the Save card even appeared, Doddy said "I'm saving
this for you", which isn't true if you then tap Don't save. Now it says "Confirm on screen if I
should save this" instead.

## What we changed

- **Search works across Polish and English.** Asking for a "code" now finds "kod".
- **Spoken numbers count as digits.** "pięć, sześć, siedem, osiem" matches 5678.
- **Word endings and small typos are forgiven**, which matters a lot in Polish.
- **Doddy is told to write codes, dates and times as digits** when it saves them, so the problem
  is smaller in the first place.

The search fixes pass our automated tests, including the exact question from that first
conversation. We haven't repeated it by voice on the phone yet. That's next.

## What is real today

| Thing | Where it stands |
|---|---|
| Saving, searching, editing, exporting and deleting notes | Built; app tests pass in the iPhone simulator |
| Talking to Doddy, with a Save card before anything is stored | Works on our own iPhone; a development setup, not open to anyone else yet |
| Finding a Polish note with an English question | Fixed in tests; not yet re-checked by voice on a phone |
| Doddy's look | The character is drawn; animation is still to come |
| People outside the team using it | None yet; you can sign up for early access |

Doddy is a bet, not a proven product. The bet is that people who already text themselves
reminders would rather tell a friendly character, and would come back to find things later. We
haven't tested that with anyone outside the team yet.

## What's next

1. **Ask the locker-code question again**, by voice, on the phone, and write down what happens.
2. **Lock down voice before anyone else uses it**, and decide how long voice recordings are kept
   on the provider's side.
3. **Open a small early-access group** and see whether anyone actually comes back.

We'll write each of these up as it happens, including the parts that don't work.

If you have a Notes app full of things you never find again, [join early access](/#join) or come
say hi in the [Telegram group](https://t.me/+u-YA6P_MISFjYWE0).

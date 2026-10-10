---
title: "Hello, Doddy: why the first thing we built is a memory you can check"
date: 2026-10-10
author: "TBD"
status: draft
summary: "Doddy is a cartoon mate for your iPhone. Before giving it a voice or a personality, we built the dull part first: notes it can save, find and show you exactly."
evidence:
  - docs/00_START_HERE/DECISIONS_AND_STATUS.md
  - docs/product/PRODUCT_REQUIREMENTS.md
  - docs/implementation/M0_REPORT.md
  - docs/implementation/M1_STATUS.md
  - docs/implementation/V1_VOICE_STATUS.md
---

# Hello, Doddy: why the first thing we built is a memory you can check

You know the parcel locker code. You knew it this morning. Now you're standing at the locker and
it's gone, along with the name of the book a friend recommended last week and the wine you liked
at that dinner.

Most of us patch this with messages to ourselves, a Notes app full of half-sentences, or
screenshots we never find again. Doddy is our attempt at something friendlier: a small,
hand-drawn mate who lives in your phone and keeps the things you ask it to keep.

This is the first post about building it. It covers what Doddy is meant to be, what we've built,
and what we haven't.

## Who is Doddy?

Doddy is a stick figure with a round head, a crooked smile, oversized trainers and an orange
backpack. The character is still being drawn and we haven't picked the final design, so treat
any picture you see of it as a draft.

The personality we're aiming for is easier to describe: someone who notices small annoyances and
fixes them without fuss, and might joke about the twelve tabs you left open. It shouldn't
guilt-trip you, pretend to miss you, or act like a person. It's an AI, and the app says so the
first time you open it.

## Why we started with memory

The easy version of this app would be a cute character attached to a chatbot. It would be fun
for a day. Then it would confidently "remember" a locker code you never gave it, and you'd stop
trusting it.

So we built in the opposite order. Before any voice, jokes or animation, Doddy had to do one
plain thing reliably:

> **Tell Doddy before you forget; find the original later.**

In practice that means:

- **You choose what gets saved.** Doddy doesn't listen in the background or quietly collect
  notes from your conversations. Nothing is stored unless you ask.
- **"Saved" means saved.** The app only says a note is saved after it has been written to the
  phone's storage and read back. If that fails, your text stays on screen so you don't lose it.
- **Answers come from your own notes.** When you search, Doddy shows the note you wrote, when you
  wrote it, and which words matched. If nothing matches, it says it couldn't find it instead of
  making something up.
- **Your words are kept.** You can edit a note, and the original version is kept next to the
  edit.
- **You can take everything with you, or delete it.** Export to JSON or plain text, delete one
  note, or delete all of them after a confirmation.
- **No account.** Notes are stored on your iPhone (and in your normal device backup). There's no
  Doddy server holding your memories. The one exception is voice: while you're talking to Doddy,
  your voice and any notes it looks up for you go to our voice provider, ElevenLabs, to run the
  conversation. The app tells you this up front.

None of this is exciting. That's intentional. A pocket mate is only useful if you can check
what it tells you.

## What is real today

We're keeping an honest scorecard, because "it works on my laptop" covers a lot of sins.

| Thing | State | Where it was checked |
|---|---|---|
| App shell: first hello, home, settings, AI disclosure | Built | Builds and passes its smoke tests in the iPhone simulator |
| Saving, searching, editing, exporting and deleting text notes | Built | Storage tests on real SQLite; app tests in the iPhone simulator |
| Talking to Doddy by voice (ElevenLabs), with a "Save this note?" card before anything is stored | Code written | **Not yet compiled or tried on a phone** |
| Character art | Drafts | Final design not chosen |
| Real iPhone (not the simulator) | Not checked yet | — |
| People outside the team using it | None yet | — |

That last row matters. Doddy is a bet, not a proven product. The bet is that people who already
text themselves reminders would rather tell a friendly character, and would come back to find
things later. We haven't tested that with anyone yet.

## What's next

1. **Run it on a real iPhone.** Storage, backups and app restarts need checking on actual
   hardware, not just the simulator.
2. **Have a real voice conversation**, in English and in Polish, and confirm Doddy can only
   answer from notes you've actually saved.
3. **Pick Doddy's final look.** Two drafts of the character are competing.
4. **Lock down voice before anyone else touches it.** The current voice setup is a development
   prototype and needs proper authentication first.
5. **A small, private test** with a few people, to see whether anyone actually comes back.

We'll write each of these up as it happens, including the parts that don't work.

*If you're the kind of person with a Notes app full of things you never find again, we'd like to
hear what you'd want Doddy to remember.* <!-- Owner: replace with the real contact/follow link once a channel exists. -->

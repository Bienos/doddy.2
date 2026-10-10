---
title: "Hello, Doddy. Why our favourite first result was 'I couldn't find it'"
date: 2026-10-10
author: "The Doddy team"
status: draft
summary: "Doddy is a hand-drawn mate for your iPhone that keeps the small things you ask it to keep. In its first real conversations it couldn't find a note, and it said so. Here's why we liked that, and what we fixed."
evidence:
  - docs/product/PRODUCT_REQUIREMENTS.md
  - docs/implementation/M1_STATUS.md
  - docs/implementation/V1_VOICE_STATUS.md
  - docs/implementation/BRANCH_CONSOLIDATION_2026-10-09.md
---

You knew the parcel locker code this morning. Now you're standing in front of the locker and it's
gone. So is the book a friend recommended last week, and the name of the wine you liked at that
dinner.

Most of us get by with messages to ourselves, a Notes app full of half sentences, and screenshots
we never find again. Doddy is our friendlier attempt. It's a small hand-drawn mate in your iPhone
that keeps whatever you ask it to keep and gives you your exact words back later.

This is the first post about building it. It covers what Doddy is, what happened the first time we
really talked to it, and what works so far.

## Memory first, personality second

The easy version of this app would be a cute character stuck on top of a chatbot. It would be fun
for a day. Then one morning it would confidently "remember" a locker code you never gave it, and
you'd stop trusting it.

So we started with the boring part. Before any jokes or animation, Doddy had to do one plain thing
reliably.

> Tell Doddy before you forget. Find the original later.

A few rules come with that. Doddy only saves what you ask it to save, and even in the middle of a
conversation nothing is stored until you tap Save. The app says "saved" once the note has been
written to the phone and read back, and if that fails your text stays on screen so you can try
again.

When you search, you get the note you wrote, the day you wrote it and the words that matched. If
nothing matches, Doddy tells you it couldn't find anything. You can edit a note and the original
wording stays next to your edit. You can also export everything as JSON or plain text, delete one
note or wipe the lot.

There's no account, and notes are stored on your iPhone. Voice works a bit differently.
Conversations run through our voice provider, ElevenLabs, and in the current test build your saved
notes are sent along when a conversation starts so Doddy has something to work with. The app tells
you this up front.

## The first real conversation

On 9 October we had the first proper voice conversation with Doddy on an actual iPhone. It lasted
79 seconds. We started in English, switched to Polish partway through, and Doddy switched with us. When
we said "Moje urodziny są jutro" ("my birthday is tomorrow"), a Save this note? card popped up. We
tapped Save, and Doddy only confirmed once the phone reported the note was stored.

A few minutes later we tried the obvious test. We had saved a code in Polish by saying it out loud,
so the note read *"Kod: pięć, sześć, siedem, osiem."* Then we asked in English, "what code have you
saved?"

Doddy searched the phone four times across those conversations, and every time it came back with
nothing.

We were oddly happy about that. The note was there and the search simply couldn't see it, because
we asked in English, the note was in Polish and the numbers were spelled out as words. Doddy also
didn't guess. If it had said "5678" because that sounded about right, the whole idea would fall
apart. A mate who makes things up is worse than a notebook.

We also caught a small honesty slip. Before the Save card even appeared, Doddy said "I'm saving
this for you", which isn't true if you then tap Don't save. Now it says "Confirm on screen if I
should save this" and waits.

## What we changed

Search now works across Polish and English, so asking for a "code" finds "kod". Spoken numbers
count as digits, which means "pięć, sześć, siedem, osiem" matches 5678. Word endings and small
typos are forgiven too, and in Polish that makes a big difference. We've also told Doddy to write
codes, dates and times as digits when it saves them, so the problem shows up less often in the
first place.

The search fixes pass our automated tests, including the exact question from that first
conversation. We haven't asked it again by voice on the phone yet. That's next.

## Where things stand

| Thing | Where it stands |
|---|---|
| Saving, searching, editing, exporting and deleting notes | Built, and the app tests pass in the iPhone simulator |
| Talking to Doddy, with a Save card before anything is stored | Works on our own iPhone. It's a development setup and nobody else can use it yet |
| Finding a Polish note with an English question | Fixed in tests, still to be checked by voice on a phone |
| Doddy's look | The character is drawn and animation is still to come |
| People outside the team using it | None yet, though you can sign up for early access |

Doddy is a bet. We think people who already text themselves reminders would rather tell a friendly
character, and would come back later to find things. Nobody outside the team has tried it yet, so
we honestly don't know.

## What's next

1. Ask the locker code question again, by voice, on the phone, and write down what happens.
2. Lock down voice before anyone else uses it, and decide how long the voice provider keeps
   recordings.
3. Open a small early access group and see whether anyone actually comes back.

We'll write each of these up as it happens, including the parts that go wrong.

If your Notes app is full of things you never find again, [join early access](/#join) or come say
hi in the [Telegram group](https://t.me/+u-YA6P_MISFjYWE0).

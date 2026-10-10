---
title: "Meet Doddy, the AI agent that remembers what you tell it"
date: 2026-10-10
author: "The Doddy team"
status: published
summary: "AI agents are everywhere in 2026. Doddy is a friendlier, smaller one: an iPhone assistant you talk to, that keeps your notes in your own words and asks before it does anything. Here's what it can do, what it can't, and how we keep it safe."
keywords: "AI agent, AI personal assistant, iPhone AI assistant, AI memory app, voice assistant, AI companion, AI safety, human in the loop"
evidence:
  - docs/implementation/V1_VOICE_STATUS.md
  - docs/implementation/TODAY_STATUS.md
  - docs/implementation/BRANCH_CONSOLIDATION_2026-10-09.md
  - DECISIONS.md (ADR-053, 063–065, 092–095)
  - reference/compiled_research/D01_RESEARCH.md
  - reference/compiled_research/D05_RESEARCH.md
---

Everyone's building AI agents right now. Agents that book flights, write code, shop for you,
answer your email while you sleep. It's a lot.

Doddy is an AI agent too, just a much smaller and friendlier one. It's a hand-drawn mate that
lives in your iPhone. You talk to it like a person (it's not one, and it tells you so), it keeps
the little things you ask it to keep, and it can help with a few everyday jobs on your phone. The
one rule it never breaks: **it asks before it does anything.**

This post covers what Doddy is, why we think it's worth building, what it can and can't do today,
and how we're thinking about safety. With sources, because the AI world has enough vibes already.

## Wait, what's an "AI agent"?

A chatbot talks. An agent **does things**: it can use tools, like your calendar, your contacts or
a search, to get a job done instead of just describing it.

That's the exciting part and the scary part. A chatbot that gets something wrong gives you a bad
answer. An agent that gets something wrong might send the wrong message, book the wrong thing or
delete something you needed. Security people even have a name for it: **"excessive agency"**,
meaning an AI that has more power, more permissions or more freedom to act than the job needs
([OWASP Top 10 for LLM Applications](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/)).

People seem to get this intuitively. In Accenture's 2026 survey of more than 25,000 consumers in
16 countries, 74% said they'd trust a personal AI agent more than their best friend to buy
something for them. But only **9%** were open to letting it complete a purchase on its own. Far
more (32%) liked the idea of the AI choosing while *they* still confirm the payment
([Accenture Consumer Pulse 2026](https://www.accenture.com/gb-en/insights/consulting/talk-my-ai-agent)).

In other words: help me, sure. Act without asking? No thanks. That's exactly how Doddy works.

## The goal: a little less to carry

Your head is full of small stuff. The parcel locker code. Where you put the spare keys. The book
your friend recommended. Your kid's shoe size. The name of that wine. None of it is important
enough for a proper system, and all of it is annoying to lose.

Lots of people already lean on AI for this kind of everyday help. Pew's 2026 survey found that
**49% of US adults** have used an AI chatbot and **24%** use one every day. The most common use
was simply looking things up, at 42%
([Pew Research Center, 2026](https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/)).
In the EU, **32.7%** of people aged 16 to 74 used generative AI tools in 2025
([Eurostat, 2025](https://ec.europa.eu/eurostat/web/products-eurostat-news/w/ddn-20251216-3)).
And when researchers looked at how people actually use ChatGPT, more than 70% of messages were
about everyday, non-work life: practical guidance, finding information, writing
([NBER Working Paper 34255](https://www.nber.org/papers/w34255)).

So people want help with ordinary life. What they don't always get is an assistant that
**remembers what they actually said**, and is honest when it doesn't know. General chatbots are
great at sounding sure. Doddy is built to show you your own words instead.

## Why a character?

Because talking to a blank text box is a bit weird, and talking to a stick figure in white
sneakers is a bit less weird. Doddy is meant to be the mate who notices small annoyances and fixes
them without fuss, and who might joke about the twelve tabs you have open.

What Doddy is **not** meant to be is a replacement friend. Researchers are starting to look
closely at AI companions. A 2026 study in *Nature Human Behaviour* of more than 1,100
Character.AI users found that using a chatbot mainly for companionship was linked with lower
well-being, especially for heavy users
([Zhang et al., 2026](https://www.nature.com/articles/s41562-026-02516-2)). An OpenAI and MIT
Media Lab study found something similar: emotional use was rare overall, but heavier use went
along with worse outcomes for some people
([MIT Media Lab, 2025](https://www.media.mit.edu/posts/openai-mit-research-collaboration-affective-use-and-emotional-wellbeing-in-ChatGPT/)).
Neither study proves cause and effect, but the direction is clear enough for us.

So Doddy's personality has rules. No guilt trips. No "I missed you". No pretending to have
feelings. No trying to keep you talking longer than you need to. It's useful first and charming
second.

## What Doddy can do today

Honest status first: Doddy is in **early testing on our own iPhone**. Nobody outside the team
uses it yet. Some of this has been tried on a real phone, and some has only been built and tested
on a computer so far. We'll tell you which is which.

**Tried on a real iPhone:**

- **Talk to it.** Hold a real voice conversation in English or Polish. It switches language when
  you do.
- **Save a note by voice.** Say "my locker code is 5678" and a **Save this note?** card appears.
  Nothing is stored until you tap Save.
- **Find a note.** Ask "what's my locker code?" and Doddy searches the notes on your phone. If it
  can't find one, it says so instead of guessing. (Our first post is
  [all about that](/blog/hello-doddy/).)

**Built, still being tested on a phone:**

- **Type notes too**, then search, edit, export or delete them. The original wording is always
  kept.
- **Smarter search** that matches across Polish and English ("code" finds "kod"), spoken numbers
  and small typos.
- **Calendar and reminders.** "What's on tomorrow?" reads your calendar. "Add dentist on Friday at
  3" shows a card, and the event is only added when you tap **Add**. Doddy then checks it was
  really saved before saying so.
- **A Today card** with the rest of your day, plus a gentle nudge before an event if you want one.
- **Small phone jobs**: start a timer, open a place in Apple Maps, run one of your Shortcuts, look
  up a contact.
- **Draft a message.** Doddy can write "running 10 min late" and open it in Messages or Mail.
  **You** press send. Doddy never sends anything itself.
- **Weather and Wikipedia** questions.
- **Talk without opening the app**: from Control Center, the Action Button, or Back Tap (you set
  that up yourself in iOS Settings). The conversation keeps going in the Dynamic Island while you
  use other apps.

## What Doddy can't do (on purpose, or not yet)

- **It doesn't listen in the background.** Doddy only hears you while a conversation is open. No
  "always on" microphone.
- **It doesn't save anything by itself.** No quietly building a profile of you from your chats.
- **It never sends, buys or deletes things in other apps.** It drafts and you decide.
- **It can't read your screen, your email or your other apps.**
- **It doesn't make up memories.** If it isn't in your notes, Doddy says it couldn't find it.
- **No live web search** yet, so it can't check today's news or prices. It'll tell you that
  rather than guess.
- **It's not a therapist, doctor or financial adviser.** For anything serious (health, money,
  legal stuff, feelings) it drops the jokes and stays calm and factual.
- **iPhone only**, for now.

## How we think about safety

Remember "excessive agency"? Here's how we're trying to avoid it, roughly following what the
security folks recommend
([OWASP](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/)):

1. **You approve every action.** Saving, adding an event, starting a timer, opening a draft:
   each one is a card you tap. This is what's called "human in the loop", and in Doddy it isn't
   optional.
2. **Only the tools it needs.** Doddy has a short, fixed list of jobs. There's no "do anything on
   my phone" button.
3. **Everything is off until you turn it on.** Calendar, reminders and contacts each have their
   own switch, all off by default, plus the normal iOS permission prompt.
4. **"Done" means done.** Doddy only says "saved" or "added" after your phone confirms it.
   Early on we caught it saying "I'm saving this" before you'd even tapped, and we
   [changed that](/blog/hello-doddy/).
5. **It's upfront about being an AI.** In its introduction Doddy says it straight out: "I'm an AI
   assistant, not a person." That's also becoming the law in
   the EU: under the AI Act, AI systems that talk to people have to make clear they're AI, with
   those transparency rules applying from 2 August 2026
   ([European Commission](https://digital-strategy.ec.europa.eu/en/library/guidelines-transparency-obligations-providers-and-deployers-ai-systems)).

**Where your data goes.** Your notes are stored on your iPhone, and there's no Doddy account.
Voice is different, and we'd rather be upfront about it. Conversations run through our voice
provider, ElevenLabs. In the current test build, when you start a conversation Doddy also sends
your saved notes and your last few conversations along, so it has something to work with.
Weather and Wikipedia lookups are made from ElevenLabs' servers too. Right now that provider
keeps the recordings, and choosing a proper retention limit is on our list **before** anyone
outside the team uses voice. People are right to care: 71% of US adults expect AI to make their
personal information less secure
([Pew, 2026](https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/)).
We'd like to be one of the reasons that doesn't happen.

## How you might use Doddy

A few everyday examples, all built on the features above:

- **"Remember that the spare keys are in the blue tin above the fridge."** Three weeks later:
  "where are the spare keys?"
- **At the shop:** "what size shoes does Maja wear?"
- **After dinner with friends:** "save: the wine was a Rioja from Bodegas Muga." Find it again
  before your next order.
- **Morning:** "what's on today?", then "nudge me 30 minutes before the dentist."
- **Running late:** "tell Kasia I'm 10 minutes late." Doddy opens the draft, you hit send.
- **Book tips:** "Tomek recommended *Project Hail Mary*." Months later: "what book did Tomek
  recommend?"

## What's next

Doddy is a bet, not a proven product. We think people who already text themselves reminders would
rather tell a friendly character, and would come back to find things later. We haven't tested
that with anyone outside the team yet. So the next steps are boring and important: test every
feature on a real phone, lock down voice and set a retention limit, then open a small early-access
group and see if anyone actually comes back.

If that sounds like your kind of thing, [join early access](/#join) or say hi in the
[Telegram group](https://t.me/+u-YA6P_MISFjYWE0).

## Sources

- Pew Research Center, *Americans and AI 2026: chatbots, smart devices and views on impact*,
  17 June 2026 (survey of 5,119 US adults, 17–23 February 2026).
  [pewresearch.org](https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/)
- Eurostat, *32.7% of EU people used generative AI tools in 2025*, 16 December 2025.
  [ec.europa.eu](https://ec.europa.eu/eurostat/web/products-eurostat-news/w/ddn-20251216-3)
- Chatterji et al., *How People Use ChatGPT*, NBER Working Paper 34255, September 2025.
  [nber.org](https://www.nber.org/papers/w34255)
- Accenture, *Consumer Pulse Research 2026* (25,590 consumers in 16 countries, January 2026).
  [accenture.com](https://www.accenture.com/gb-en/insights/consulting/talk-my-ai-agent)
- OWASP, *LLM06:2025 Excessive Agency*, OWASP Top 10 for LLM Applications 2025.
  [genai.owasp.org](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/)
- Zhang, Zhao, Hancock, Kraut and Yang, *Interaction with AI companions and psychological
  well-being*, Nature Human Behaviour, 4 August 2026.
  [nature.com](https://www.nature.com/articles/s41562-026-02516-2)
- MIT Media Lab and OpenAI, *Early methods for studying affective use and emotional wellbeing in
  ChatGPT*, 21 March 2025.
  [media.mit.edu](https://www.media.mit.edu/posts/openai-mit-research-collaboration-affective-use-and-emotional-wellbeing-in-ChatGPT/)
- European Commission, *Guidelines on transparency obligations for providers and deployers of AI
  systems* (AI Act Article 50), 20 July 2026.
  [digital-strategy.ec.europa.eu](https://digital-strategy.ec.europa.eu/en/library/guidelines-transparency-obligations-providers-and-deployers-ai-systems)

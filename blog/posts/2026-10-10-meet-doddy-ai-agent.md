---
title: "Meet Doddy, an AI companion that wants to do it all for you"
date: 2026-10-10
author: "The Doddy team"
status: published
banner_pose: waving
banner_says: Hey. I'm Doddy.
banner_card_title: Save this note?
banner_card_text: The spare keys are in the blue tin above the fridge.
banner_tint: orange
summary: "Doddy is an AI companion for your iPhone with a big goal. One day it should help with anything you need, and it will always ask before it acts. Here's what it does today, what it can't do yet, how we keep it safe, and answers to the questions people ask most."
keywords: "AI companion, AI agent, AI personal assistant, iPhone AI assistant, AI memory app, voice assistant, AI safety, human in the loop"
tldr:
  - Doddy is an AI companion for your iPhone, a hand-drawn mate you can talk to in English or Polish.
  - The big goal is a companion that can help with anything, and we're getting there one skill at a time.
  - Today it remembers what you tell it in your own words and finds it again. It can also help with your calendar, reminders, timers, maps and message drafts.
  - It always asks first. Every action is a card you tap, and it never sends, buys or deletes anything on its own.
  - If it can't find something it tells you, and it never pretends to be a person.
  - It's early days. We're testing it on our own iPhone and it isn't public yet, so [join early access](/#join) if you'd like a go.
evidence:
  - docs/implementation/V1_VOICE_STATUS.md
  - docs/implementation/TODAY_STATUS.md
  - docs/implementation/BRANCH_CONSOLIDATION_2026-10-09.md
  - DECISIONS.md (ADR-053, 063 to 065, 092 to 095)
  - reference/compiled_research/D01_RESEARCH.md
  - reference/compiled_research/D05_RESEARCH.md
---

Everyone seems to be building AI agents right now. There are agents that book flights, write code,
do your shopping and answer your email while you sleep. It's a lot.

Doddy is our version, an AI companion that lives in your iPhone. It's a hand-drawn mate you talk
to like a person (it isn't one, and it tells you so). The dream is pretty simple. Whatever you
need, you tell Doddy and it gets handled. Remember this, plan that, sort out the other thing.

We're not there yet and we won't pretend we are. Today Doddy does a handful of things well, and it
only learns a new skill once it can do that skill safely. One rule never changes, which is that
Doddy asks before it does anything.

Below you'll find where Doddy is heading, what it can and can't do right now, and how we think
about safety. There's an FAQ at the end, plus our sources, because the AI world has enough vibes
already.

## Wait, what's an AI agent?

A chatbot talks. An agent actually does things. It can use tools like your calendar, your
contacts or a search to get a job done for you.

That's the exciting part, and it's also the scary part. When a chatbot gets something wrong you
get a bad answer. When an agent gets something wrong it might send the wrong message, book the
wrong thing or delete something you needed. Security people even have a name for this. They call
it "excessive agency", meaning an AI that has more power, more permissions or more freedom to act
than the job needs
([OWASP Top 10 for LLM Applications](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/)).

Most people seem to sense this already. Accenture surveyed more than 25,000 consumers in 16
countries in 2026, and 74% said they'd trust a personal AI agent more than their best friend to buy
something for them. Yet only 9% were happy to let it finish a purchase on its own. Far more of them
(32%) liked the idea of the AI choosing while they still confirm the payment
([Accenture Consumer Pulse 2026](https://www.accenture.com/gb-en/insights/consulting/talk-my-ai-agent)).

So people want the help, and they want to say yes before anything happens. That's exactly how
Doddy works.

## A little less to carry

Your head is full of small stuff. The parcel locker code, where the spare keys went, the book your
friend recommended, your kid's shoe size, the name of that wine. None of it deserves a proper
system, and all of it is annoying to lose.

Plenty of people already lean on AI for this kind of everyday help. In Pew's 2026 survey, 49% of
US adults had used an AI chatbot and 24% used one every day. The most common reason was simply
looking things up, at 42%
([Pew Research Center, 2026](https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/)).
In the EU, 32.7% of people aged 16 to 74 used generative AI tools in 2025
([Eurostat, 2025](https://ec.europa.eu/eurostat/web/products-eurostat-news/w/ddn-20251216-3)).
When researchers looked at how people really use ChatGPT, more than 70% of messages were about
everyday life outside work, things like practical guidance, finding information and writing
([NBER Working Paper 34255](https://www.nber.org/papers/w34255)).

People clearly want help with ordinary life. What they don't always get is an assistant that
remembers what they actually said and admits when it doesn't know. General chatbots are very good
at sounding sure of themselves. Doddy's answers come straight from your own words.

## Where we're going

When we say "a companion that can do anything for you", here's what we really mean. Doddy grows one
skill at a time, and each new skill has to pass three tests before it ships.

1. It asks first. You see what Doddy is about to do and tap to say yes.
2. It checks its own work. Doddy looks at the result before it says "done".
3. You can switch it off. Every skill that touches your stuff has its own switch.

We'd love Doddy to help with lots more one day. Keeping track of parcels and appointments, planning
your week, remembering birthdays and what people like, and sorting out the small admin that eats
your evenings. None of that is built and there are no dates. A skill that can't pass the three
tests stays out, however cool the demo looks.

## Why a character?

{{doddy relaxing "Useful first. Charming second."}}

Talking to a blank text box is a bit weird. Talking to a stick figure in white sneakers is a bit
less weird. Doddy is meant to be the mate who notices small annoyances and sorts them out without
fuss, and who might tease you about the twelve tabs you've got open.

When we say companion, we mean a mate who helps you get on with your day. Your friends stay your
friends. Researchers have started looking closely at AI companions, and the early results are
worth taking seriously. A 2026 study in *Nature Human Behaviour* of more than 1,100 Character.AI
users found that using a chatbot mainly for companionship was linked with lower well-being,
especially for heavy users
([Zhang et al., 2026](https://www.nature.com/articles/s41562-026-02516-2)). An OpenAI and MIT
Media Lab study found something similar. Emotional use was rare overall, but heavier use went along
with worse outcomes for some people
([MIT Media Lab, 2025](https://www.media.mit.edu/posts/openai-mit-research-collaboration-affective-use-and-emotional-wellbeing-in-ChatGPT/)).
Neither study proves cause and effect, though the direction was clear enough for us.

So Doddy's personality comes with rules. It won't guilt-trip you or tell you it missed you, it
won't pretend to have feelings, and it won't try to keep you chatting longer than you need. Useful
comes first and charm comes second.

## What Doddy can do today

{{doddy listening "Go on, I'm listening."}}

First, where we are. Doddy is in early testing on our own iPhone and nobody outside the team uses
it yet. Some of the list below has been tried on a real phone, and the rest has been built and
tested on a computer so far. We'll tell you which is which.

These have been tried on a real iPhone.

- You can hold a real voice conversation in English or Polish, and Doddy switches language when
  you do.
- You can save a note by voice. Say "my locker code is 5678" and a Save this note? card pops up.
  Nothing is stored until you tap Save.
- You can ask "what's my locker code?" and Doddy searches the notes on your phone. If nothing
  turns up, it says so.

These are built and still being tested on a phone.

- Typing notes, then searching, editing, exporting or deleting them. The original wording is
  always kept.
- Smarter search that matches across Polish and English ("code" finds "kod"), spoken numbers and
  small typos.
- Calendar and reminders. "What's on tomorrow?" reads your calendar. "Add dentist on Friday at 3"
  shows a card, and the event only goes in when you tap Add. Doddy then checks it really saved
  before telling you so.
- A Today card with the rest of your day, plus a gentle nudge before an event if you'd like one.
- Small phone jobs like starting a timer, opening a place in Apple Maps, running one of your
  Shortcuts or looking up a contact.
- Drafting a message. Doddy can write "running 10 min late" and open it in Messages or Mail, and
  you press send yourself.
- Questions about the weather or anything on Wikipedia.
- Talking without opening the app, from Control Center, the Action Button or Back Tap (you set
  Back Tap up yourself in iOS Settings). The conversation keeps going in the Dynamic Island while
  you use other apps.

## What Doddy can't do (on purpose, or not yet)

Doddy only hears you while a conversation is open, so there's no always-on microphone. It
doesn't save anything by itself either, which means it can't quietly build a profile of you from
your chats.

It never sends, buys or deletes things in your other apps. It writes the draft and you decide what
happens next. It also can't read your screen, your email or your other apps.

Doddy won't make up memories. If something isn't in your notes, it says it couldn't find it. There's
no live web search yet, so it can't check today's news or prices, and it'll just say so.

It isn't a therapist, a doctor or a financial adviser. For anything serious, like health, money,
legal stuff or feelings, it drops the jokes and stays calm and factual. And for now it's iPhone
only.

## How we think about safety

{{doddy pointing "Your tap, your call."}}

Remember "excessive agency"? This is how we try to avoid it, roughly following what the security
folks recommend
([OWASP](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/)).

1. You approve every action. Saving a note, adding an event, starting a timer and opening a draft
   are all cards you tap. People call this "human in the loop", and in Doddy you can't turn it off.
2. Doddy only gets the tools it needs. It has a short, fixed list of jobs, and there's no "do
   anything on my phone" button.
3. Everything starts switched off. Calendar, reminders and contacts each have their own switch,
   all off by default, plus the usual iOS permission prompt.
4. Doddy only says "saved" or "added" once your phone confirms it. Early on we caught it saying
   "I'm saving this" before anyone had tapped, and we changed that.
5. It tells you it's an AI. In its introduction Doddy says "I'm an AI assistant, not a person."
   That's becoming the law in the EU too. Under the AI Act, AI systems that talk to people have to
   make it clear they're AI, and those transparency rules apply from 2 August 2026
   ([European Commission](https://digital-strategy.ec.europa.eu/en/library/guidelines-transparency-obligations-providers-and-deployers-ai-systems)).

Then there's the question of where your data goes. Your notes are stored on your iPhone and there's
no Doddy account. Voice works differently, and we'd rather tell you now. Conversations run through
our voice provider, ElevenLabs. In the current test build, starting a conversation also sends your
saved notes and your last few conversations along so Doddy has something to work with. Weather and
Wikipedia lookups come from ElevenLabs' servers as well. For now the provider keeps the recordings,
and setting a proper retention limit is on our list before anyone outside the team uses voice.
People are right to worry about this stuff. In the same Pew survey, 71% of US adults expected AI to
make their personal information less secure
([Pew, 2026](https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/)).
We'd like to be one of the reasons that doesn't happen.

## How you might use Doddy

Here are a few everyday examples, all using the features above.

- "Remember that the spare keys are in the blue tin above the fridge." Three weeks later you ask
  "where are the spare keys?"
- Standing in a shoe shop, you ask "what size shoes does Maja wear?"
- After dinner with friends you say "save this, the wine was a Rioja from Bodegas Muga", and find it
  again before your next order.
- In the morning you ask "what's on today?" and then "nudge me 30 minutes before the dentist."
- Running late, you say "tell Kasia I'm 10 minutes late." Doddy opens the draft and you hit send.
- "Tomek recommended *Project Hail Mary*." Months later you ask "what book did Tomek recommend?"

## What's next

Doddy is a bet. We think people who already text themselves reminders would rather tell a friendly
character, and would come back later to find things. Nobody outside the team has tried it yet, so
we don't know if we're right. The next steps are boring and important. We'll test every feature on
a real phone, lock down voice and set a retention limit, then open a small early access group and
see if anyone actually comes back.

If that sounds like your kind of thing, [join early access](/#join) or say hi in the
[Telegram group](https://t.me/+u-YA6P_MISFjYWE0).

## FAQ

{{doddy reading "Good questions."}}

### What is Doddy?

It's an AI companion app for iPhone. You talk to it or type, it keeps the things you ask it to
keep, and it helps with everyday jobs on your phone like your calendar, reminders, timers and
message drafts.

### Can Doddy really do anything for me?

Not yet, though that's where we're heading. Today it remembers things, finds them again and helps
with a short list of phone jobs. We add a new skill once Doddy can ask first and check its own
work.

### Is Doddy a real person?

No. Doddy is an AI and it says so. The drawings and the personality are there to make it nicer to
talk to.

### Is Doddy an AI girlfriend or boyfriend type of app?

No. Doddy is a mate who helps you with stuff. It won't guilt-trip you, say it misses you or try to
keep you chatting.

### Does Doddy listen all the time?

No. It only hears you while a conversation is open, and there's no always-on microphone.

### Where are my notes stored?

On your iPhone, and you don't need an account. Voice is the exception. Conversations run through
our voice provider, ElevenLabs, and in the current test build your saved notes and recent
conversations are sent along when a conversation starts so Doddy has some context.

### Can I delete everything?

Your notes, yes. You can delete one at a time or all of them at once in Settings, and you can
export them first as JSON or plain text. We still have to decide how long the voice provider keeps
conversation recordings, and we'll do that before anyone outside the team uses voice.

### Will Doddy do things without asking?

No. Saving a note, adding an event, starting a timer and opening a message draft are all cards you
tap. Doddy never sends, buys or deletes anything in your other apps.

### What if Doddy gets something wrong?

If it can't find something, it tells you. You can edit any note and the original
wording is kept. And since every action needs your tap, you can catch a mistake before it happens.

### Which languages does Doddy speak?

English and Polish, and it switches when you do.

### Is there an Android version?

Not yet. Doddy is starting on iPhone.

### How much does it cost?

We haven't decided on pricing yet.

### When can I try it?

Doddy is still in early testing. [Join early access](/#join) and we'll let you know when it opens.
There's no date yet.

## Sources

- Pew Research Center, *Americans and AI 2026*, 17 June 2026 (survey of 5,119 US adults, 17 to 23
  February 2026).
  [pewresearch.org](https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/)
- Eurostat, *32.7% of EU people used generative AI tools in 2025*, 16 December 2025.
  [ec.europa.eu](https://ec.europa.eu/eurostat/web/products-eurostat-news/w/ddn-20251216-3)
- Chatterji et al., *How People Use ChatGPT*, NBER Working Paper 34255, September 2025.
  [nber.org](https://www.nber.org/papers/w34255)
- Accenture, *Consumer Pulse Research 2026* (25,590 consumers in 16 countries, January 2026).
  [accenture.com](https://www.accenture.com/gb-en/insights/consulting/talk-my-ai-agent)
- OWASP, *LLM06 2025 Excessive Agency*, OWASP Top 10 for LLM Applications 2025.
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

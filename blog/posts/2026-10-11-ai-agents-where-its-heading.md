---
title: "AI agents are coming. Here's where it's heading, and where Doddy fits"
date: 2026-10-11
author: "The Doddy team"
status: published
summary: "AI agents are moving from talking to doing, and fast. We looked at the research on where agents are heading, what's holding them back, and why we think the winners will be the small, trustworthy ones that ask before they act."
keywords: "AI agents, agentic AI, future of AI, AI assistant, AI companion, personal AI agent, AI trust, human in the loop"
banner_pose: pointing
banner_says: The future asks first.
banner_card_title: Add to your calendar?
banner_card_text: Dentist, Friday at 3pm. Doddy checks it saved before saying so.
banner_card_buttons: Not now | Add
banner_tint: orange
og_image: /assets/blog/agents-cover.png
tldr:
  - AI agents are software that can actually do things for you, like book, buy, schedule and send, instead of only chatting.
  - The research says they're getting better fast. The length of task an agent can finish has been doubling roughly every seven months.
  - Big money is lining up behind them. McKinsey thinks agents could steer 3 to 5 trillion dollars of global shopping by 2030.
  - The catch is trust. Only 9% of people would let an agent buy something without checking first, and Gartner expects over 40% of agent projects to be cancelled by 2027.
  - We think the agents that win will be small, personal and honest, and that's the kind of agent Doddy is built to be.
evidence:
  - DECISIONS.md (ADR-204, 229, 247, 253, 254, 258, 268, 270)
  - docs/implementation/ACTIVITY_UNDO_STATUS.md
  - docs/implementation/CALCULATOR_STATUS.md
  - docs/implementation/SAID_TIME_STATUS.md
  - docs/implementation/HEY_DODDY_STATUS.md
---

For the last few years, AI mostly talked. You asked a question, it wrote an answer, and then you went and did the actual thing yourself.

That's changing. The big story in tech right now is AI agents. That means software that doesn't just tell you how to book the dentist but opens your calendar and books it. We spent some time reading the research on where this is going, and honestly, it's exciting. It also explains why we're building Doddy the way we are.

## From chatting to doing

The difference is simple. A chatbot gives you words. An agent uses tools, like your calendar, your reminders, your email or a shop, to get something done for you.

And the tools are getting standardised. In December 2025, Anthropic, OpenAI and Block set up the Agentic AI Foundation under the Linux Foundation, with support from Google, Microsoft and Amazon Web Services, to look after shared standards for agents. One of them is the Model Context Protocol, a common way for an AI to plug into apps and data. Anthropic said there were already more than 10,000 public MCP servers when it handed the protocol over ([Anthropic, 2025](https://www.anthropic.com/news/donating-the-model-context-protocol-and-establishing-of-the-agentic-ai-foundation)). When rival companies agree on plumbing, it usually means the thing is here to stay.

## Agents are getting better, fast

The most striking number we found comes from METR, a research group that measures what AI can actually do. They tracked the length of tasks an AI agent can finish on its own, measured by how long the same task takes a skilled person. That length has been doubling roughly every seven months since 2019. If the trend holds, they expect agents to handle many software tasks that take people a month within about five years ([METR, Kwa et al., arXiv 2503.14499](https://arxiv.org/abs/2503.14499)).

METR is careful to say this is measured on software tasks and the exact numbers depend on how you test. The direction is hard to ignore, though. Agents that could manage a few minutes of work a couple of years ago can now manage a lot more.

![Bar chart in Doddy's notebook style showing what doubling every 7 months looks like: 1x today, 2x after 7 months, 4x after 14, 8x after 21 and 16x after 28 months. Labelled as an illustration of METR's reported trend, not measured data.](/assets/blog/agents-doubling.webp "If the pace METR measured keeps up, the tasks agents can handle grow 16 times in under two and a half years.")

## People are already spending real time with AI

This isn't a lab-only story. Sensor Tower estimates people will spend 36 billion hours in generative AI apps in the first half of 2026, up from 17.2 billion hours a year earlier. That's more than double in a year ([Sensor Tower, 2026](https://sensortower.com/press/sensor-tower-state-of-ai-2026-report-global-time-spent-on-generative-ai-apps-projected-to-more-than-double-year-over-year)). In the US, 49% of adults have used an AI chatbot and 24% use one every day ([Pew Research Center, 2026](https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/)).

![Bar chart of hours spent in generative AI apps worldwide. First half of 2025, 17.2 billion hours. First half of 2026, 36 billion hours, shown hatched because it is a projection. Source Sensor Tower.](/assets/blog/agents-hours.webp "Hours in AI apps, first half of 2025 against the first half of 2026 (projected).")

Same story inside companies. Gartner predicts that by 2028, a third of business software will include agents, up from under 1% in 2024. It also expects at least 15% of everyday work decisions to be made by agents by then ([Gartner, 2025](https://www.gartner.com/en/newsroom/press-releases/2025-06-25-gartner-predicts-over-40-percent-of-agentic-ai-projects-will-be-canceled-by-end-of-2027)).

## The money is following

McKinsey has looked at what happens when agents start shopping for people. Their estimate is that agents could steer up to 1 trillion dollars of US retail sales by 2030, and between 3 and 5 trillion dollars globally ([McKinsey, 2025](https://www.mckinsey.com/industries/retail/our-insights/the-agentic-commerce-opportunity-how-ai-agents-are-ushering-in-a-new-era-for-consumers-and-merchants)). That figure counts every purchase an agent helps along, including comparing and recommending, so it's a broad measure. Still, it tells you how seriously the industry is taking this.

## The catch is trust

Here's the part we find most interesting. People like the idea of agents, and they're nervous about letting them loose.

In Accenture's 2026 survey of more than 25,000 people in 16 countries, 74% said they'd trust a personal AI agent more than their best friend to make a purchase for them. Only 9% were open to an agent completing a purchase entirely on its own, though. Far more, 32%, liked the version where the AI chooses and they confirm the payment ([Accenture, 2026](https://www.accenture.com/gb-en/insights/consulting/talk-my-ai-agent)).

![Horizontal bar chart from Accenture's 2026 survey. 74% would trust a personal AI agent more than their best friend to buy something for them. 32% are happy for the AI to choose if they still confirm the payment. 9% are happy for the AI to buy entirely on its own.](/assets/blog/agents-trust.webp "Lots of trust in theory, very little appetite for agents acting alone.")

And 71% of US adults expect AI to make their personal information less secure ([Pew, 2026](https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/)).

Businesses are hitting the same wall. Gartner expects more than 40% of agent projects to be cancelled by the end of 2027, because of rising costs, unclear value and weak risk controls. It also warns about "agent washing", old chatbots relabelled as agents, and reckons only about 130 of the thousands of companies selling "agentic AI" are the real thing ([Gartner, 2025](https://www.gartner.com/en/newsroom/press-releases/2025-06-25-gartner-predicts-over-40-percent-of-agentic-ai-projects-will-be-canceled-by-end-of-2027)).

Security people have a name for the risk. They call it "excessive agency", meaning an AI with more power, permissions or freedom than the job needs. The fix they recommend is a human approving anything important before it happens ([OWASP, 2025](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/)).

Put it all together and the picture is pretty clear. Agents are coming either way, and the ones people keep using will be the ones they trust.

## Where Doddy fits

Doddy is a personal AI agent for your iPhone, a hand-drawn mate you can talk to. We started small on purpose, with your notes, your calendar, your reminders and your lists, and we built the trust part in from day one.

![Four steps in Doddy's notebook style. You ask, "Add the dentist on Friday at 3". Doddy shows an Add to your calendar card and nothing changes yet. You tap Add. Doddy checks the event saved and only then says Added. Underneath, changed your mind? Undo it from What Doddy did.](/assets/blog/agents-flow.webp "Every action Doddy takes goes through the same four steps.")

Here's how that shows up in the app.

- It asks first. When Doddy wants to add an event, set a reminder or save a note, it shows you a card and waits for your tap. Doddy can write a message for you, but you're the one who presses send.
- It checks its own work. Doddy only says "added" or "saved" once your phone confirms the change really happened.
- You can undo it. Doddy keeps a list of what it did, and you can undo the calendar, reminder and list changes it made. Agents will make mistakes, so undo matters as much as the action.
- It asks when you're unclear. If "Friday" could mean this week or next, Doddy asks one quick question instead of guessing.
- It doesn't guess numbers. For sums and unit conversions, Doddy hands the maths to your phone instead of working it out in its head, where AI tends to slip.
- Big jobs come as one plan. A request with several steps shows up as a single card, and you can change any step before anything runs.
- Everything is opt-in. Calendar, reminders and contacts each have their own switch, all off at the start. Even the new "Hey Doddy" wake word only listens if you turn it on, and the phone shows clearly when it's listening, with a Stop button right there.

To be straight with you, Doddy is still in early testing. Voice conversations and saving notes have been tried on a real iPhone. Most of the features above are built and are being tested on our own phone, so nobody outside the team has used them yet. We'd rather tell you that than oversell it.

## What happens next

The trend lines all point the same way. Agents will be able to do more every year, more of our day will run through them, and the real competition will be over who people trust with their stuff.

We think there's room for something different from the giant do-everything assistants. A small, personal agent that knows the little things in your life, does what you ask, asks before it acts, and owns up when it can't find something. That's Doddy. It grows one skill at a time, and each skill has to pass the same tests. It asks first, it checks its own work, and you can switch it off.

If that sounds like the kind of AI you'd actually want in your pocket, [join early access](/#join) or come say hi in the [Telegram group](https://t.me/+u-YA6P_MISFjYWE0).

## FAQ

### What is an AI agent?

It's AI that can take actions for you, like adding an event, setting a reminder or placing an order, instead of only answering questions.

### Is Doddy an AI agent?

Yes, a small and personal one. It works with your notes, lists, calendar and reminders on your iPhone, and it asks before it changes anything.

### Will AI agents replace apps?

Probably not completely. What's more likely is that agents work through your apps for you, which is why shared standards like the Model Context Protocol matter.

### Are AI agents safe?

They can be, if they're built carefully. The safest designs give the agent only the tools it needs and let a person approve anything important. That's how Doddy works.

### When can I try Doddy?

Doddy is in early testing on iPhone. [Join early access](/#join) and we'll let you know when it opens.

## Sources

- Anthropic, *Donating the Model Context Protocol and establishing the Agentic AI Foundation*, 9 December 2025. [anthropic.com](https://www.anthropic.com/news/donating-the-model-context-protocol-and-establishing-of-the-agentic-ai-foundation)
- Kwa et al. (METR), *Measuring AI Ability to Complete Long Tasks*, arXiv 2503.14499, March 2025, updated July 2026. [arxiv.org](https://arxiv.org/abs/2503.14499)
- Sensor Tower, *State of AI 2026*, 16 June 2026. [sensortower.com](https://sensortower.com/press/sensor-tower-state-of-ai-2026-report-global-time-spent-on-generative-ai-apps-projected-to-more-than-double-year-over-year)
- Pew Research Center, *Americans and AI 2026*, 17 June 2026 (survey of 5,119 US adults, 17 to 23 February 2026). [pewresearch.org](https://www.pewresearch.org/internet/2026/06/17/americans-and-ai-2026-chatbots-smart-devices-and-views-on-impact/)
- Gartner, *Gartner Predicts Over 40% of Agentic AI Projects Will Be Canceled by End of 2027*, 25 June 2025. [gartner.com](https://www.gartner.com/en/newsroom/press-releases/2025-06-25-gartner-predicts-over-40-percent-of-agentic-ai-projects-will-be-canceled-by-end-of-2027)
- McKinsey, *The agentic commerce opportunity*, October 2025. [mckinsey.com](https://www.mckinsey.com/industries/retail/our-insights/the-agentic-commerce-opportunity-how-ai-agents-are-ushering-in-a-new-era-for-consumers-and-merchants)
- Accenture, *Consumer Pulse Research 2026* (25,590 consumers in 16 countries, January 2026). [accenture.com](https://www.accenture.com/gb-en/insights/consulting/talk-my-ai-agent)
- OWASP, *LLM06 2025 Excessive Agency*, OWASP Top 10 for LLM Applications 2025. [genai.owasp.org](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/)

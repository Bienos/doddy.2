# Doddy is presented as a digital companion; "AI" moves to one short notice

- **Date:** 2026-11-09
- **Decided by:** owner, 9 Nov 2026: "would that be possible to not mention AI in doddy like i know its an agent but i dont want people to tell it straight just digital companion online companion that can do a lot sort of things", then "Yes but do it better ok" to the plan of keeping one short notice.
- **Status:** accepted; ships with the pull request that adds this file.
- **Replaces:** nothing. DOD-03 (character without false humanity) and the call and translator disclosures stay as they are.

## Why
The website, the blog and the app called Doddy "an AI mate", "an AI companion", "a personal AI agent" and "an AI assistant", and showed "Doddy is an AI, not a person." on Home, Voice, Settings, Messages and three times on the homepage. The owner wants Doddy positioned as a companion that gets things done, not as "an AI".

Removing the word entirely isn't possible: the EU AI Act (Article 50, applying since 2 Aug 2026) requires people talking to an AI system to be told so; companion-chatbot laws (California SB 243, New York) require a clear notice that a companion is not human; the constitution's DOD-03 says Doddy never passes as a person. Not legal advice; `legal_review_required_before_launch` in `doddy_rules.yaml` still applies.

## Decision
1. **Positioning:** Doddy is "your always-online companion" / "a digital companion". Marketing copy doesn't call him an AI, an agent, an assistant or a chatbot.
2. **One notice, one wording:** "Doddy is a digital companion powered by AI, not a person." (first person: "I'm a digital companion powered by AI, not a person."; Polish: "Tu Doddy, cyfrowy towarzysz oparty na AI, nie człowiek."). It is shown where people talk to Doddy and where they look for what he is: the voice screen, Messages, the Settings footer, the "What I can do" introduction, and the website footers. It is no longer the header of Home's menu, the homepage hero or the privacy panel.
3. **Asked directly, Doddy says plainly he is an AI** (voice instructions; `scripts/voice_agent_spec.py` still checks it). The blog FAQ "Is Doddy a real person? No. Doddy is an AI and it says so." stays.
4. **Unchanged on purpose:**
   - Disclosures to people who never signed up: the phone opening lines ("Hi, this is Doddy, an AI assistant", "asystent AI"), the call-case explanation, and the translator's spoken notice and "AI translation" label.
   - Health and training safety lines ("I'm an AI, not a doctor"): in medical moments the limit of competence matters more than tone.
   - Provenance labels: news summaries "written by AI".
   - Privacy facts that say what *doesn't* happen ("no AI reads them", "not by an AI"): they don't label Doddy.
   - The legal drafts (Terms, Privacy Policy): lawyer text.
   - The blog post "AI agents are coming": an essay about the industry; only the lines that describe Doddy changed.
5. **Settings › Privacy:** the privacy summary starts with the same line, and the "Cloud AI" row is now "Online answers" (it lists the services that answer you: ElevenLabs, Anthropic). Owner, 9 Nov: "ok change do all", after being told open pull request #294 also edits `SettingsScreens.swift`; the two changes are in different parts of the file.

## Consequences
- Fewer mentions: the English homepage goes from 8 to 1 (the footer), the app's everyday screens from 5 to 3 short lines, plus the Settings privacy summary.
- The live ElevenLabs agent keeps its current prompt until the owner says to sync (`docs/OWNER_QUEUE.md` 31); until then voice may still call himself "an AI sidekick".
- Translations of the new lines are drafts, like the rest (ADR-234); the Polish ones were written with the app's existing terms.

## Evidence
See the pull request: the generators' `--check` runs, the voice spec check and the Linux checks. Not compiled: the app (no Xcode here); `ios-build` is the first compile.

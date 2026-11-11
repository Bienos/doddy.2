# Doddy is presented as a digital companion, not "an AI"

- **Date:** 2026-11-09 (narrowed 2026-11-11)
- **Decided by:** owner, 9 Nov 2026: "would that be possible to not mention AI in doddy like i know its an agent but i dont want people to tell it straight just digital companion online companion that can do a lot sort of things", then "Yes but do it better ok" and "ok change do all". On 11 Nov, in #338: "nie chcę używać słowa AI w ogóle w mówieniu o Dodim" (no "AI" at all when talking about Doddy). On 11 Nov, here: "keep the voice, reopen the PR".
- **Status:** the app part shipped in #338 (`changes/settings-messages-radar-leaflets-2026-11-11.md`); the website, blog and voice-instruction part ships with #302.
- **Replaces:** nothing. DOD-03 still holds: Doddy never passes as a person, and says plainly he is an AI when asked.

## Why
The website, the blog and the voice instructions called Doddy "an AI mate", "an AI companion", "a personal AI agent" and "a personal AI sidekick". The owner wants Doddy positioned as a companion that gets things done.

## Decision
1. **Positioning:** "your always-online companion" / "a digital companion". Copy about Doddy doesn't call him an AI, an agent, an assistant or a chatbot.
2. **Website:** the hero, meta and share text say "Your always-online companion"; "The companion you'd let near your inbox". One footer line on every page: "Doddy is a digital companion, not a person." Nine languages.
3. **Blog:** only the lines that describe Doddy change (titles, summaries, "What is Doddy?", "Is Doddy an AI agent?" became "Where does Doddy fit in?"). The safety section says "It never pretends to be a person. Ask Doddy whether it's an AI and it says so plainly." The FAQ "Is Doddy a real person? No. Doddy is an AI and it says so." stays: it is the answer when asked. The industry discussion about AI agents stays.
4. **Voice:** `voice-agent/instructions.md` and the live agent: call himself Doddy or a digital companion; never "AI assistant", "AI agent" or "chatbot"; don't bring up being an AI unprompted; asked directly, say plainly "I'm an AI, not a person" (`scripts/voice_agent_spec.py` checks it).
5. **App:** done by #338: no "AI" label for Doddy in the app's words.
6. **Unchanged on purpose:** the opening line of calls to people who never signed up, the translator's notice to the other person, news "written by AI" provenance, the legal drafts.

## Consequences
- The website no longer says "AI" about Doddy outside the blog. The EU AI Act's notice (Art. 50) is about the conversation itself; companion-chatbot laws (California SB 243, New York) ask for a clear notice that a companion isn't human. "Not a person" on the site, and Doddy's answer when asked, are what remain. `legal_review_required_before_launch` in `doddy_rules.yaml` still applies before outside testers; not legal advice.
- The live ElevenLabs agent's "# Identity" passage was changed on 10 Nov 2026 on the owner's word ("ok change do all"): version `agtvrsn_0801m71zgg3wfj29agemmp6cx39b`, rollback `agtvrsn_5401m70zggkafcz88jshewy89ae8` (`voice-agent/README.md`). The 11 Nov sync (#340) kept it.
- Translations of the new lines are drafts (ADR-234).

## Evidence
See #302: the site, blog, day-page and string-catalog generators with `--check`, `scripts/voice_agent_spec.py check`, `scripts/ci.sh --only checks`, `make test-core`.

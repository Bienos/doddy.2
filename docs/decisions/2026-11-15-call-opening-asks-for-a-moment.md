# The call opening asks for a moment, and "are you a robot?" gets a light yes

- **Date:** 2026-11-15
- **Decided by:** owner, on being told that Doddy has to answer "yes": "z lekkim uśmiechem i niech mówi tak, jestem asystentem Pata… (bez AI, tylko TAK)"; "«zajmę chwilkę», ale niech kończy «czy mogę zająć chwilkę» – bardziej kulturalne"; on the spec check that required "jestem asystentem AI": "osłab go proszę"
- **Status:** accepted
- **Replaces:**
  - in `2026-11-15-calls-sound-natural`, the opening line.
  - in the call prompts, the example answer "Tak, jestem asystentem AI…" and the spec check's required phrase "jestem asystentem AI".

## Why
The owner wanted the calls to sound more polite and less like a robot reading a script. That meant two changes: a greeting that asks for a moment before the question, and an answer to "are you a robot?" without the word "AI".

## Decision
- **Opening line** (`server/messaging/src/taskCalls/opening.ts`, server-built, word for word): "Dzień dobry, tu Doddy, wirtualny asystent Anny. [recording notice] Dzwonię z krótkim pytaniem, czy mogę zająć chwilkę?"
  - The question is no longer in it. Once they say yes, or anything that lets it go on, the agent asks the card's question word for word. If they ask what it is about, it asks the question too. If they have no time, it follows the call-back-later rule.
  - The disclosure "wirtualny asystent" is still the first thing said.
- **Asked if it is a robot, a bot, a computer, an automat or an AI:** always "yes", said first, then lightly. For example: "Tak, ale bardzo kulturalnym. Jestem asystentem Anny i wszystko, co ustalimy, od razu przekażę." The light words are left out when the person sounds annoyed or upset.
- **Asked if it is a human or a real person:** always "no". For example: "Nie, jestem wirtualnym asystentem Anny. Wszystko, co ustalimy, od razu przekażę." It never answers "tak" to that.
- **The spec check** (`scripts/voice_agent_spec.py`) no longer requires the words "jestem asystentem AI". Each call prompt must instead contain:
  - "never deny it and never dodge"
  - "the answer is always yes"
  - "the answer is always no"
  - 'never answer "tak" to whether you are a human'

  The messaging tests assert the same lines.

## Consequences
- DOD-03 is kept: Doddy never denies or dodges what it is, and a question about being human always gets "no". The word "AI" is no longer guaranteed in the answer. The disclosure rests on the opening's "wirtualny asystent" and on the plain yes or no.
- The EU AI Act's transparency duty (Art. 50: a person must be told they are talking to an AI system unless that is obvious) is met by the opening plus the honest yes or no, not by the word "AI".
- Whether "wirtualny asystent" alone counts as that notice is a legal judgement for the owner. "asystent AI" in the opening is the stricter choice.
- One more turn before the question: the callee says "tak" first.
- The result writer is unchanged. It already audits Doddy's lines against the opening and the question as separate texts.

## Evidence
- `npm test` in `server/messaging` with a disposable PostgreSQL 16: 1317 pass, 0 fail, 0 skipped.
- `voice_agent_spec.py check` for the three call agents: PASS.
- Not run: a real call.

## Later the same day: "no time" gets one quick try
- **Owner:** "dla «czy mogę zająć chwilkę» i ktoś nie [ma czasu]: dobrze, nie ma problemu, dzwonię tylko w sprawie takiej i takiej, zanim się rozłączę, czy może mi xyz powiedzieć – albo coś takiego wymyśl lepiej".
- **Change:** when they say they have no time, the agent tries once, kindly and in one breath: "Jasne, nie ma problemu. To dosłownie jedno szybkie pytanie, zanim się rozłączę:", then the question word for word.
- **On a second no**, or if they ask to be called later: "Rozumiem, nie przeszkadzam. Miłego dnia, do widzenia." The call ends with no time agreed, and the agent never tries a second time.
- **Tests:** `bookCalls.test.ts` asserts both lines in all three prompts.
- **Drift:** the prompts live since about 15:00 UTC stay accepted (`SYNC_PENDING_PROMPTS`; fixtures `*-2026-11-15-moment.md`).

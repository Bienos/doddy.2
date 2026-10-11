# Sums and unit conversions on the iPhone: status (ADR-270)
Date: 2026-10-11. Owner: "build next", after ADR-269. Claude's proposal list item 3: "calculator, unit and currency conversion". Currencies are left out (see Decisions).

## Why
Language models often get arithmetic wrong. With these two tools the agent passes the sum or the conversion, and reads back the number the app worked out.

## What ships
- **Two new phone tools** in `voice-agent/tools.json` (35 tools in total):
  - **`calculate(expression)`** accepts:
    - numbers with a dot for decimals;
    - `+ - * / ^` and brackets; `×`, `÷` and `−` are accepted too;
    - `%` after a number, which divides it by 100 ("80 * 15%" = 12).
  - The usual order of operations applies. Powers group from the right, and `-2^2` is −4.
  - There are no names, variables or functions, so an expression can only do arithmetic.
  - **Refused, with a reason the agent can act on:** a comma decimal, `12:30`, words, currency signs, dividing by zero, a result too large, more than 200 characters, or nesting more than 20 deep.
  - **`convert_units(value, from, to)`** covers:
    - length (mm … mi, nautical miles);
    - weight (mg … t, oz, lb, stone);
    - volume (ml, l, US tsp/tbsp/fl oz/cup/pint/gallon, and imperial gallon as `uk gal`);
    - temperature (°C, °F, K, never below absolute zero);
    - speed (m/s, km/h, mph, knots);
    - area (m², km², ft², ha, acre);
    - time (s … weeks).
  - Exact defined factors are used, e.g. 1 in = 2.54 cm and 1 lb = 0.45359237 kg.
  - Different kinds (kg → l), unknown units and negative amounts are refused.
  - **Currencies are refused** with "Currencies can't be converted".
- **Replies:**
  - "result: ( 124.50 + 37 ) ÷ 3 = 53.83333333. Calculated by the app; say this number, don't work it out again." Sums are given to 10 significant digits.
  - "converted: 5 mi = 8.04672 km. …" Conversions are given to 7.
- **Runs on the iPhone only.** No network, account, permission or connection switch is involved. Pause all doesn't apply (no other app is used), and nothing is stored or logged in What Doddy did. Translator mode still runs no tools.
- **Prompt:**
  - One line asks the agent to use these tools for every sum and conversion.
  - "Convert currencies" was added to "What you cannot do yet".

## Files
- **Core:** `Calculator.swift` (new: tokenizer, parser, number text, the unit table, conversion, parsing, replies); `VoiceTools.swift` (cases and parser hooks); `ConnectionPause.swift`; `ActivityLog.swift`.
- **App:** two cases in `VoiceSessionController`.
- **Agent:** `voice-agent/tools.json` and `voice-agent/instructions.md`.
- **Tests:** `CalculatorTests` (9).

## Verified (Linux, Swift 6.1.2)
- `CalculatorTests` (9) pass. They cover:
  - order of operations, powers and percent;
  - the exact replies and number text, including 0.1 + 0.2 = 0.3;
  - everything refused;
  - the factors and temperatures;
  - mismatched and unknown units, currencies, negative amounts;
  - parsing;
  - no Pause all, no activity log, no connection, blocked in translator mode.
- A planted precedence bug was caught by two failing assertions, then removed.
- `scripts/ci.sh --core-only`: PASS (636 DoddyCore tests; voice agent spec with 35 tools). `swiftc -parse` passes on `VoiceSessionController.swift`. iOS app NOT RUN.

## NOT RUN / UNVERIFIED
- **Live agent NOT updated.** Until `calculate` and `convert_units` are added to the ElevenLabs agent, it can't call them.
- Whether the agent actually uses the tools rather than doing sums itself, and how it reads long decimals aloud, has not been tried in a conversation.
- No Xcode build.

## Mac checklist
| # | Do this | Expect |
|---|---|---|
| C1 | "What's 124.50 plus 37, split three ways?" | About 53.83; nothing logged in What Doddy did |
| C2 | "How many kilometres is 5 miles?" / "350 Fahrenheit in Celsius?" | 8.05 km / about 177 °C |
| C3 | "Convert 20 euros to złoty" | Doddy says it can't convert currencies yet |
| C4 | Pause all on; ask a sum | Still answered (no other app is used) |

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-02 honesty_over_agreeableness | The number comes from the app; the reply says not to work it out again; refusals give a reason instead of a guess | `testTheReplyShowsTheSumAsReadAndARoundedResult`, `testAnythingButArithmeticIsRefused` | The agent's use of the tool is untested live |
| DOD-06 tool content is data | The expression is only parsed as arithmetic; nothing can be evaluated or run | `testAnythingButArithmeticIsRefused` | — |
| DOD-11 observable_privacy | On the iPhone, not logged or stored | `testParsingAndThatNoAppIsUsed` | — |

## Decisions for the owner
- **Currencies:** they need live exchange rates from an outside service. Choosing a provider, its terms, and how stale a rate may be is an owner decision.
- Sync the two tools to the live agent.

**Live agent updated 2026-10-11** (owner approved): see the last paragraph of `DECISIONS.md` for tool ids and versions; `voice_agent_spec.py compare` MATCH.

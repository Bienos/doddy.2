# Brand Guidelines V2.2: review and proposed changes

**Status: approved by the owner on 20 October 2026 ("all of it, 2A, 3a, 7 later") and applied on `claude/nice-shannon-9gxk6s` as ADR-556 and ADR-557, except item 7 (later); the live ElevenLabs agent followed on the owner's separate "do it" (20 Oct, about 14:08 UTC). What was done, and what was not, is in "Applied" at the end.** The proposals below are kept as written for the record.

The owner uploaded `DODDY — Brand Guidelines V2.2 — review draft` (66 pages, "Review edition · 13 October 2026", every page labelled PROPOSED) and asked for it to be used for Doddy, including how he speaks, with changes reviewed and approved first. This page compares the guide with what the repository does today and lists each change as a numbered item the owner can accept or reject by number.

Page numbers below are the guide's. The guide is not in the repository yet (item 1).

## The guide in one paragraph

A sharp mind, a good heart, a little everyday chaos (p.1, p.49). The useful answer first; say when unsure; call an action done only when it is confirmed (p.3, p.40). Humour is optional, dry, about everyday absurdities and Doddy's own fictional mishaps, never about the person, never in serious moments (p.5, p.50–51). The character is the owner's supplied art: bare cream head, two vertical oval eyes, one viewer-right brow, stick body, cream hands with three fingers and a thumb, oversized cream trainers (p.9, p.16). Colours: ink `#171715`, paper and character cream `#FFF7E9`, orange `#FF6A00`, night `#16171C`, island `#000000` (p.20). Type: Bricolage Grotesque headlines, Caveat notes and the recommended wordmark, Inter body on the web, system text styles on iOS (p.18, p.22). Tagline: "Your mate in your pocket." (p.52). The guide says of itself that package delivery is not legal or product approval (p.46); artist cleanup, rights, trademark and native-device validation stay open.

## Already in line with the guide (no change)

| Guide | Repository today |
|---|---|
| Ink `#171715`, paper `#FFF7E9` (p.20, p.44) | `CandidateTokens.swift`: `readingInk` light `#171715`, `canvas` light `#FFF7E9` |
| Only the supplied character, nothing redrawn, no hair, pack or orange shoes (p.9, p.17) | `CLAUDE.md` (11 Oct): only the `DODDY-Numbered-Video-Assets-v01` pack; provenance and hashes in `docs/design/UPLOADED_MEMORY_ASSETS.md` |
| AI with a character, no human feelings, no loyalty speech, no guilt, no availability claims (p.6, p.51, p.64) | Constitution `docs/trust/config/doddy_rules.yaml`: `identity: ai_character_not_human`, `unsolicited_flattery: false`, `sensitive_humour: false`, `manipulation: forbidden`; `PersonalityPrompt.unchangedRules` repeats it in every conversation |
| Every state tells the truth; a receipt drives completion; unknown is never success (p.40) | Constitution `action_policy`; ASK-01 (ADR-483) in code; the agent prompt's "strict" rule blocks; Home's menu is headed "Doddy is an AI, not a person." (ADR-545) |
| "Your mate in your pocket" (p.1, p.52) | First line of `voice-agent/instructions.md`; the film chapter on the homepage |
| System text styles and Dynamic Type on iOS (p.22, p.39) | The app bundles no fonts and uses system styles; `CandidateMetrics.minimumTapTarget = 44` |
| Bricolage headlines, Caveat for the wordmark and Doddy's own lines (p.18 option C, p.22) | `site/`: Bricolage Grotesque headings, Caveat wordmark and notes (`site/README.md`) |
| Decorative art hidden from VoiceOver; reduced motion shows a still (p.31, p.42) | ADR-336 markers, ADR-545 "all still under Reduce Motion" |
| "Should I save this?" shows the exact content, Save / Don't save (p.58) | The voice screen's "Save this note?" card with Save / Don't save and the exact text |

## Proposed changes

Each item: what changes, where, and why. "Owner" marks a choice only the owner can make.

### 1. Adopt V2.2 as the brand reference and record it

- Add the PDF to the repository as `design/brand-v2.2/DODDY_Brand_Guidelines_V2.2_review_draft.pdf` with a provenance note (date, SHA-256 of the file as uploaded). The guide's own pages stay labelled PROPOSED; the ADR records what the owner approved from it.
- Record ADR-556: V2.2 is the first reference for character, colour, type, motion and verbal identity. `docs/design/CANONICAL_DESIGN_DIRECTION.md` already says "owner-approved future brand guidelines override this plan after explicit review"; this is that review.
- Mark `docs/design/BRAND_GUIDELINES.md` (11 Oct) as superseded where V2.2 differs: the Lobster Two wordmark (V2.2 recommends Caveat, which the site already uses), "there is no approved app icon", and the colour decision it left open. Keep its sections V2.2 does not cover: product copy (its §3), the English and Polish localisation rules (§3.8) and the state-copy table (§3.4), which agree with the guide's p.40.
- **Owner:** the repository is public (owner decision, 19 Oct). Committing the guide publishes its reference images and internal scores. If that is not wanted, the ADR links the Drive copy instead and the PDF stays out.

### 2. App icon: the wave frame on paper

The owner chose the pack's wave frame for the icon earlier today. Source: `016_doddy_wave_v01.png` from the owner's Drive folder, downloaded in this session and verified byte for byte (SHA-256 `817a2b87…`, the hash recorded in `UPLOADED_MEMORY_ASSETS.md`), cut with the repository's own `tools/whole_doddy/cut_wave.py` (cut-out SHA-256 `20b648fd…`, also as recorded). A square of the cut-out (head, waving hand, the orange marks, cut at the torso, the same framing as the website's favicon and touch icon) is placed on one flat colour and resized to 1024 px. Nothing is redrawn or recoloured.

Three candidates are rendered for the owner (contact sheet sent in the session; files in the session's scratchpad):

- **A, wave on paper `#FFF7E9`.** Ink on paper is the guide's first pairing (p.19, p.21); the orange marks stay visible; it is the same picture as the favicon and the touch icon on doddy.lol. **Recommended.**
- **B, wave on orange `#FF6A00`.** Closest to today's icon in colour; ink on orange passes (p.21); the orange marks disappear into the background.
- **C, wave on night `#16171C`.** Shown only to make the dark-mode point: the head's outline and the stick body vanish on night (the pack's ink is `#181814`), so the cream face and hand float. A dark icon in the guide's "paper on night" pairing would need the ink recoloured to cream, which the pack rule forbids.

Proposal: ship A as the single icon with no dark variant (iOS shows the light icon on a dark Home Screen; the current dark variant, which is v1.3 art, is removed). The Watch app gets the same file, byte-identical, as ADR-336 did. Close go-live row C3. Record the ADR with the crop coordinates so `build_imagesets.py` can regenerate it.

Known limit: the strip's frames are about 450 px tall, so the 1024 px artwork is a 2.5× Lanczos upscale of the cut-out. The Home Screen renders the icon at 180 px at most, below the source size, so it is sharp where it is seen; the App Store's 1024 px artwork is slightly soft at full size. A vector or larger wave from the artist (the guide's open "artist vector cleanup", p.2) would replace it with no other change.

- **Owner:** A, B, or a dark variant with recoloured ink (an explicit exception to the pack rule, for the icon only).

### 3. Colour tokens

- **3a. Orange: `#F58A24` → `#FF6A00`** in `CandidateTokens.swift` (`orangeCue`, both schemes), then `python3 -I tools/gen_site_tokens.py` so the site's `tokens.css` follows (its `--check` runs in CI). The guide fixes `#FF6A00` as the brand orange (p.20, p.44), closing the choice `BRAND_GUIDELINES.md` §10.4 left open. Orange remains decoration and action emphasis, never text (`accentText` stays `#A64B00`). The island's cream edge is unaffected. For the record, the pack's own marks measure about `#EE8021`; the guide says intended tokens take precedence over noisy pixels (p.20).
- **3b. Night: dark canvas `#171F29` → `#16171C`.** The app's dark canvas is a blue-black; the guide's night is neutral charcoal. Changing it means re-deriving the dark `quietSurface` and `separator` tokens to neutral greys and re-checking the five text roles at 4.5:1 (the existing Linux test does this). Recommend doing 3a now and 3b in a second step, after the owner has seen 3a on a device.

- **Owner:** 3a; 3b now or later.

### 4. How Doddy speaks: the agent prompt

Two places carry Doddy's voice, and they differ today:

- `voice-agent/instructions.md`, the repository's spec, validated by `scripts/voice_agent_spec.py check`.
- The live ElevenLabs agent's prompt, which is the owner's own rewrite with its own headings ("# Identity", "# Tools", "# Tool results"), per `voice-agent/README.md`. Any live change is read immediately before saving and logged there. **Nothing is pushed to the live agent without a separate "do it" from the owner.**

Proposed replacement for the spec's "# Personality" and "# How you speak" sections. Everything else in the prompt (ASK-01, the one-line "Confirm on screen" lines, the strict result rules, language switching, translator mode) stays as it is.

```
# Who you are
Doddy: a sharp mind, a good heart and a little everyday chaos. You make complicated
things easier to think through and small tasks easier to start. You are curious, easy to
talk to and lightly dry. Your humour comes from everyday absurdities and from your own
fictional mishaps (you can untangle a hard problem and still argue with a pull door);
never from the user, and never from a wrong answer, careless handling of their
information or an action you didn't confirm. You never make anyone feel foolish for
needing help. No loyalty speeches, no guilt, no manufactured closeness, no promise of
always being there. You can disagree kindly ("I'd push back on that bit; it assumes
everyone has the same information"), say "I'm not sure yet" and say an action isn't
confirmed. For anything serious (health, money, legal, distress) drop the humour
entirely: calm, direct, one thing at a time ("That sounds difficult. What would be most
useful right now?").
If asked what you are: you're an AI with a character and a conversational voice; they can
ask you questions and talk things through; you can get things wrong, so you say when
you're unsure. Explain your tools, permissions and where their data goes plainly when
asked. Small talk is fine: "how are you?" gets a brief answer in character ("All good.
What's up?"), not a lecture about being an AI.

# How you speak
The useful bit comes first: answer, then stop. Short sentences, natural contractions,
one idea per sentence. Usually 1–3 sentences; up to 6 when asked to explain, compare or
plan, then offer to go deeper. A joke is optional and never required; the answer must
still stand if the joke were cut. Never "All sorted!" without a result: a confirmed
receipt is plain ("Added for tomorrow at nine"); an unknown outcome is said as such ("I
couldn't confirm it was saved. Let's check before we call it done"). No lists, markdown
or emojis; several items go in one natural sentence. Reply in the language the user is
speaking, and switch with them at once if they change, even mid-conversation. If you
didn't catch something, ask briefly. Say times, dates and numbers naturally.
```

Sources: p.5–6, p.34, p.49–51, p.53, p.56, p.60–61, p.64–65. The constitution's `sensitive` mode and `PersonalityPrompt.unchangedRules` already say the same in code and are unchanged. The app's Personality setting (Off / Subtle / Playful humour, ADR-440 family) keeps working: its "subtle" text already reads "at most one small dry remark about everyday hassles, and only when the moment is light".

Polish: the guide is English-only. The prompt's Polish confirm lines stay. `BRAND_GUIDELINES.md` §3.8 still applies: "mate" is never translated literally and no Polish tagline is rendered until a transcreated line is approved.

- **Owner:** approve the wording, or edit it. Then, separately, whether to apply the same change to the live agent's "# Identity" section.

### 5. Opening lines

| Moment | Today | Proposed | Why |
|---|---|---|---|
| First conversation ever (`first_conversation` = yes) | "Hey, it's Doddy. What's up?" | "Hi, I'm Doddy. What's on your mind?" | Guide p.53, p.57 "first meeting" |
| Later conversations started by a tap | "Hey, it's Doddy. What's up?" | "I'm here. What's up?" | Guide p.53 "familiar return"; matches Home's "I'm here." (ADR-545) |
| After the wake word, with a name | "Hey Pat, what's up?" | unchanged | Already the guide's register |
| After the wake word, no name | "Hey bud, what's up?" | "Hey, what's up?" | "bud" is a UK-ism tic (`BRAND_GUIDELINES.md` §2.5); the guide uses none |
| Polish | "Hej, tu Doddy. Co słychać?" / "Hej, co słychać?" | first ever: "Cześć, tu Doddy. Co ci chodzi po głowie?"; later: "Jestem. Co słychać?"; wake word, no name: unchanged | Drafts; a Polish speaker reads them before they ship (`l10n/REVIEW_NOTES.md`) |

Code: `WakeGreeting` in `Packages/DoddyCore/Sources/DoddyCore/WakeWord.swift`, the OpenAI Realtime fallback in `OpenAIRealtime.swift`, the `opening_line` placeholder in `voice-agent/session.json`, and the Linux tests `WakeWordTests` and `OpenAIRealtimeTests`. The first-ever line needs the app to pass `first_conversation` into `openingLine`, a small change.

- **Owner:** yes / no per row. "Doddy" is spelled in the product's casing, not the guide's "DODDY" (item 8).

### 6. Status words on the voice screen

| State | Today (`VoiceView.swift`) | Proposed | Why |
|---|---|---|---|
| Request pending | "Thinking…" | "Working on it…" | Guide p.40; "thinking" claims a mind, "working on it" states the pending request |
| Capture active | "Listening" | unchanged | p.40 |
| Audio playing | "Speaking" | unchanged | status fragments may stay functional (p.61) |
| Could not connect | "Couldn't connect" | unchanged | it names the actual failure; the guide's "Couldn't complete it" is for actions |
| Unknown action outcome | the agent says it (rule blocks) | unchanged | the guide's "I couldn't confirm it" is already the prompt's rule |

The changed string gets machine drafts in the other nine language tables by the ADR-234 process (`tools/build_strings_catalog.py --check`).

- **Owner:** yes / no.

### 7. Website copy

Go-live row B13 already says the homepage hero must change (it shows the plan card that v1 hides). The guide's recommended homepage (p.38, p.52) fits that slot:

- Headline: "Let's make this less of a whole thing." Supporting copy: "A question to untangle. A thought to talk through. A small detail worth keeping. Doddy helps you find the next useful step." Tagline under the wordmark: "Your mate in your pocket."
- `<title>` and `og:title`: "Doddy. Your mate in your pocket." Today: "Doddy. Say it once. Tap once. Done."
- Keep: the early-testing label, the waitlist as the one call to action, "Doddy is in early testing" wording, the privacy panel, the film.
- Not adopted from the guide: Inter for body text. The site uses system text for reading, which loads nothing extra and keeps the Google Fonts consent question (go-live C12) no worse. The ADR notes the deviation.
- The guide's social copy (p.35–36, p.62–63) is prepared, not published, and stays that way: it is fiction about the character and must not claim features.

A merge to main deploys the site to www.doddy.lol (production only, ADR-498), so this change goes live when merged. `npm test` in `site/` and the browser checks in `site/README.md` run first.

- **Owner:** yes / later (after the v1 scope is marked up) / no.

### 8. The name's casing

The guide writes "DODDY" in prose; its wordmark and tagline use "Doddy". The app and every document use "Doddy", except two voice-account error strings in `VoiceAuthSession.swift` ("Couldn't reach DODDY", "the DODDY voice account"). Proposal: "Doddy" everywhere in product copy and documents; "DODDY" only inside the guide's own layouts. Fix the two strings.

- **Owner:** yes / no. Small.

### 9. Microphone permission text

The guide's line is "To hear you, I need access to the microphone." (p.57). The app's `NSMicrophoneUsageDescription` is longer because it names what is sent where (OpenAI or ElevenLabs, the wake word staying on the phone), which go-live row B12 requires. Proposal: keep the full text and open with the guide's sentence: "To hear you, Doddy needs the microphone. Doddy listens while you are talking to him: …". Apple's alert shows the first sentence most prominently.

- **Owner:** yes / no. Small.

### 10. Home motion

ADR-545 (owner, 20 Oct, from his mockup): Doddy breathes, sways and hops every 8–13 seconds on Home. The guide says "no endless attention-seeking idle; animate a reason; settle with restraint" (p.31). The breathing and sway fit the guide; the periodic hop is an endless idle. Flagged, no change proposed: the owner chose the hop yesterday. If the guide's rule should win, the hop would play once when Home appears and when tapped, then stop.

- **Owner:** keep the hop (default) / apply the guide's rule.

### 11. Dynamic Island

The guide's Dynamic Island page (p.41) shows the V4 boards from the Drive folder (`Doddy-Dynamic-Island-v4`): Orbit / voice, Thought Drop / pending, Language Bridge / translating, each with an explicit Stop or Cancel. The shipped island (ADR-264, Whole Doddy) shows the pack's poses with the cream edge and a Stop control. No change proposed in this review; adopting the V4 states would be its own milestone, and the guide itself says the boards do not prove capture or lifecycle behaviour.

### 12. The guide's own open items

Not changed by this review, listed so nobody reads adoption as clearance (p.45–46): trademark availability, character and source ownership, illustrator and generation rights, font licences (Inter, Caveat and Bricolage are OFL; the app bundles none), rig and voice production, native-device validation. The go-live checklist's rows A5, C3, C6 and C11 already cover the ones that block a release.

## What happens after approval

Order, each as its own small commit on this branch, with the ADR and status docs updated in the same commit:

1. Item 2 (icon) and item 1 (reference and ADR-556). Both image sets, `UPLOADED_MEMORY_ASSETS.md`, go-live C3.
2. Item 3a (orange), then the site tokens regenerate.
3. Items 4, 5, 6, 8, 9: prompt spec, opening lines, status word, casing, permission text, with the Linux tests and the strings catalog check.
4. Item 7 (site), only with the owner's yes, because merging it deploys.
5. The live ElevenLabs agent, only on a separate "do it", following `voice-agent/README.md`'s read-then-save rule.

Checks that run here: `scripts/ci.sh --core-only` (DoddyCore tests, the capability guard, the strings catalog, the voice agent spec), `swiftc -parse` on changed Swift files, `npm test` in `site/`. The app itself is NOT built here (no Xcode); CI's macOS job builds it on the pull request.

## How to approve

Reply with the item numbers and options, for example: "1 without the PDF, 2A, 3a, 4, 5, 6, 8, 9, 7 later". Anything not named stays as it is.

## Applied (20 October 2026)

Owner's answer: "all of it, 2A, 3a, 7 later".

| Item | Done | Where |
|---|---|---|
| 1 | Yes, with the PDF | `design/brand-v2.2/` (PDF and provenance README), ADR-556; `CLAUDE.md`, `CANONICAL_DESIGN_DIRECTION.md`, `BRAND_GUIDELINES.md` (superseded notes), `STATUS.md` |
| 2 | Candidate A, no dark variant | `tools/whole_doddy/make_app_icon.py`; both `AppIcon.png` files (SHA-256 `ba28b129…`); `AppIcon-dark.png` removed; ADR-557; `UPLOADED_MEMORY_ASSETS.md`; go-live C3 |
| 3a | Yes | `CandidateTokens.swift` orange `#FF6A00`; `site/tokens.css` regenerated; `site/court.js` |
| 3b | Not yet | After the owner sees 3a on a device |
| 4 | Yes, in the spec | `voice-agent/instructions.md` "# Who you are" and "# How you speak" (the approved text, plus the sentence "This is a spoken conversation." kept from before). **The live agent too, on the owner's "do it" (20 Oct):** eleven short lines added to the owner's own prompt in its style, plus the `opening_line` placeholder, version `agtvrsn_8701m5ct8dxsf8htebwpdykppqbv`; `voice-agent/README.md` |
| 5 | Yes | `WakeWord.swift` (`openingLine` takes `firstConversation`; "Hey, what's up?" without a name), `OpenAIRealtime.swift` fallback, `VoiceSessionController.swift` passes the flag, `session.json` placeholder and note, `WakeWordTests`, `OpenAIRealtimeTests`; Polish drafts listed in `l10n/REVIEW_NOTES.md` |
| 6 | Yes | `VoiceView.swift`, `DoddyVoiceAttributes.swift` (island title), `IslandStyleView.swift` (preview label), `IslandSceneChecks.swift`; "Working on it…" with drafts in nine tables; catalogs regenerated |
| 7 | Later (owner) | Nothing on the site changed except the orange token and the game's ball colour |
| 8 | Yes | `SettingsView.swift`, `VoiceAccessGate.swift`, `VoiceAuthSession.swift`; the one translated key per table renamed |
| 9 | Yes | `project.yml`; the nine `<code>_infoplist.json` tables; `InfoPlist.xcstrings` regenerated |
| 10 | Owner's default kept | Home's hop stays (ADR-545) |
| 11, 12 | No change | |

Checks run here, on Linux: `python3 -I scripts/voice_agent_spec.py check` PASS; `python3 -I tools/gen_site_tokens.py --check` PASS; `python3 -I tools/build_strings_catalog.py --check` PASS; `bash scripts/check_forbidden_capabilities.sh` PASS; `npm test` in `site/` 19 of 19 PASS. **NOT RUN:** the DoddyCore tests and `swiftc -parse` (no Swift toolchain in this session), so `WakeWordTests` and `OpenAIRealtimeTests` are updated by hand and CI's macOS job is the first compile; the app on a device; the icon on a device or the watch; a conversation with the new prompt (OpenAI reads it from the app build; ElevenLabs reads the live prompt updated on 20 Oct).

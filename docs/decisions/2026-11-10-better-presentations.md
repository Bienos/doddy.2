# Decks are researched, outlined as typed slides, checked in code and laid out in Doddy's design

- **Date:** 2026-11-10
- **Decided by:** owner (translated from Polish): "I asked Doddy to make a presentation; it came out crap; it sent it to Messages." Then: "It's more about how they're shown and how they're made — they need better research, and the presentation should be neater, better, easy to read, better visualisations, not plain empty text; where something needs illustrating, illustrate it."
- **Status:** applied in the pull request from `claude/better-presentations`
- **Replaces:** for `make_document` with `kind: "deck"` only, the single request to Claude's `pptx` skill (ADR-564). Word, Excel, PDF and text are unchanged.

## Why
The owner's example (ElevenLabs conversation `conv_7901m7322gxpf2wtfprcm71t86y0`, "Prezentacja o Iławie", tools `web_search` then `make_presentation`; not readable from here, worked from the code):

- It went through **`make_presentation`** (ADR-567), not `make_document`. There the **voice model** writes every slide as a title plus up to six bullet strings, with only the five web snippets it had, and the **iPhone** writes them on paper-coloured slides (`PresentationFile.swift`): one layout, no pictures, no charts, no speaker notes, no sources. That is the "plain empty text".
- The server path for decks (`make_document`, `kind: "deck"`) asked Claude's `pptx` skill for "6 to 12 slides with one idea each" in one sentence, with no research beyond what the voice agent passed and no check of what came back: the look and the facts depended on one model run.

## Decision
`make_document` with `kind: "deck"` now runs a pipeline in `backend/src/decks/` (the other kinds are unchanged):

1. **Plan** (Claude, structured output, low effort): the deck's language, up to two Wikipedia phrases, up to two web queries.
2. **Research** (code, `research.ts`), all of it untrusted data:
   - **Wikipedia** article text in the deck's language (English if nothing is found), reference sections dropped, clipped to 9,000 characters. The host is built from a fixed language list. Free, no key; the voice agent already reads Wikipedia.
   - **Wikimedia Commons** lead pictures, only with a licence Doddy can honour with an attribution line (CC0, public domain, CC BY, CC BY-SA), an author, no `NonFree` flag and no restriction, served from `upload.wikimedia.org` or `thumb.wikimedia.org`, JPEG or PNG checked by its bytes, at least 480 px wide. Author and licence go under the picture and on the sources slide. No picture is ever generated.
   - **Web search through Monid**, the server's existing search: only when the user's web search switch is on and it fits the same daily caps as a voice search. Snippets only.
   - The **material** the agent passed (often its own search results), as source `m1`.
3. **Outline** (Claude, structured output, medium effort, `spec.ts` schema): 5 to 10 content slides, each with a layout (`bullets`, `two_column`, `stats`, `timeline`, `comparison`, `chart`, `quote`, `image`), the ids of the sources it uses, and speaker notes; 3 to 5 takeaways; the words for "Agenda", "Summary", "Sources" in the deck's language. Claude never writes the file, a link, a colour or a position.
4. **Check** (code, `checkDeck`): shape and limits (zod); 5 to 10 content slides; at least two layouts other than bullets when there are sources; cited sources exist; on `stats`, `chart`, `timeline` and `comparison` slides **every number must appear in the text of the sources the slide cites** (as written, or rounded to the places shown); a `quote` must be word for word in its source; pictures exist and are used once. Problems go back to Claude once with the list. Slides still wrong are left out; fewer than three left fails the file.
5. **Layout** (code, `render.ts`): Office Open XML written directly (as the phone's `PresentationFile.swift`), 16:9, Brand V2.2 colours (ink `#171715`, paper `#FFF7E9`, night `#16171C`, orange `#FF6A00` for marks only, `#A64B00` for accent text), Arial (in PowerPoint, Keynote and Google Slides; no font file). Code adds the title slide (a Commons picture if one is unused, else a quiet disc-and-dot mark), the agenda, the summary and a sources slide with numbered, clickable sources and picture credits. Each content slide names its sources at the foot (`Źródło: [1] Iława — Wikipedia`). Charts are bars drawn as shapes, so Quick Look, Keynote and PowerPoint show the same thing. Every slide has speaker notes. Text sizes are fitted to their boxes.
6. **Read back**: the ZIP is opened again; every slide must be there with words and notes, or the job fails. The file is "ready" only after that, as before.

The ask card for a deck adds one line saying where the research goes (`DECK_RESEARCH_LINE`).

## Consequences
- **Cost and time:** two Claude calls (three with a repair) instead of up to nine with a code-execution container; up to two Monid searches (about $0.002) counted against the user's web search cap; Wikimedia is free. The deck still counts as `DODDY_DOCUMENT_CLAUDE_UNITS` Claude runs.
- **Honesty:** a deck about a topic with no sources is written without figures, dates or quotes (the data layouts need a citation). Numbers in plain bullet text are not checked against the sources; only the data slides are (a gap, listed in the pull request).
- **Privacy:** the deck's research phrases (a few words from the request, chosen by Claude) now go from Doddy's server to Wikipedia and Wikimedia Commons, and, with web search on, to Monid. The privacy page names Wikipedia only for lookups made through ElevenLabs. Owner queue row added.
- **Wikimedia rate limits:** from this session's machine both Wikipedia and Commons answered 429 after a few requests (10 Nov 2026). A 429 waits once (Retry-After, at most 3 s) and is tried once more; after that the deck is made without that source. Render's shared addresses may see the same.
- **Not changed:** the phone's `make_presentation` (the owner's example). It makes a better deck only if the voice agent stops choosing it for ordinary presentations: the pull request proposes the exact tool descriptions for `make_presentation` and `make_document`; the live agent changes only on the owner's separate instruction.
- **Preview:** the file page and Messages are unchanged: Quick Look shows the deck itself; no thumbnail is rendered on the server (no rasteriser there).

## Evidence
See the pull request: `npm run typecheck` and `npm test` in `backend/` (22 new tests in `backend/test/decks.test.ts`); a sample deck rendered with LibreOffice from fixture research text and one real Commons picture; nothing run against Anthropic or a live Render service.

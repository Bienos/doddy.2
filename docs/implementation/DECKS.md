# Decks with Doddy's look, opened the iPhone's own way (ADR-654)

Owner, 25 Oct 2026: "ty robisz te prezentacje, ale zachowujesz skill set, na przykład brandingu do Doddy'ego … i otwierasz je … czy systemowo to działa … jak najbardziej taki interfejs systemowy, żeby otwierał w takich domyślnych też rzeczach". Proposal and mockups: `docs/strategy/DECKS_2026-10.md`.

## What changed

1. **Doddy's own skill, `doddy-decks`** (`backend/skills/doddy-decks/`): a custom Agent Skill sent next to Anthropic's `pptx` skill on every deck (`container.skills`: `{type: "anthropic", skill_id: "pptx"}` and `{type: "custom", skill_id: <id>}`). It holds the look (Brand V2.2's paper, ink, orange; Arial only; Clean and Night variants when the request asks), where Doddy may appear (the owner's three poses, title and last slide only), and the honesty rules (no invented numbers). It is used only for decks, only when `DODDY_DECK_SKILL_ID` is set; without it decks are made as before.
2. **Opened the system way.** A file bubble in Messages used to open the signed link in Safari. It now downloads the file with the iPhone's own session and shows it in **Quick Look**, whose Share button lists Keynote ("Copy to Keynote" for a .pptx), PowerPoint and Google Slides if installed, Files, AirDrop and Mail. Doddy builds no viewer. If that fails (no session, the file is still being made, it is gone after a week) the link opens in Safari as before, and its page says which.
3. **A bug fixed on the way.** The app's HTTP code refused any answer over 512 KB, so any deck over that size (one with pictures) failed to open from Files. Files and the bubble now use a transport with a 16 MB limit (the server keeps 15 MB) and a 60 s wait.

## Doing the upload (owner, once; not done)

The skill reaches Claude only after it is uploaded with Doddy's Anthropic key. That key is on the server only, so this is a step for whoever holds it, and nothing here ran it.

```bash
cd backend/skills
curl -X POST "https://api.anthropic.com/v1/skills" \
  -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
  -F "display_title=Doddy decks" \
  -F "files[]=@doddy-decks/SKILL.md;filename=doddy-decks/SKILL.md" \
  -F "files[]=@doddy-decks/art/doddy_wave.png;filename=doddy-decks/art/doddy_wave.png" \
  -F "files[]=@doddy-decks/art/doddy_fistpump.png;filename=doddy-decks/art/doddy_fistpump.png" \
  -F "files[]=@doddy-decks/art/doddy_listening.png;filename=doddy-decks/art/doddy_listening.png"
```

The answer has an `id`. Set it as `DODDY_DECK_SKILL_ID` on the live service (it is in `render.yaml`, empty) and deploy. To change the skill later, upload a new version with `POST /v1/skills/{id}/versions` (a whole new file set each time; the name in `SKILL.md` stays `doddy-decks`); the server asks for `version: "latest"`. The request shape is from Anthropic's Skills guide as read on 25 Oct 2026 (the guide shows no beta header for it now). Check that against the live API on the first upload.

## Checked and not checked

- **Checked here (Linux):** backend 432 tests with Postgres, including the new ones: both skills on a deck and on its `pause_turn` continuation, none on a Word file, `pptx` alone when no id is set, the id's shape in config, and the skill folder (name, description, size, art byte-identical to the app's `WholeDoddy_*`, colours equal to the app's). DoddyCore 1,898 tests, including the link-to-document rule the bubble uses (`ThreadDocument.madeDocument`); the app-logic type-check (30 files, `URLSessionTransport` among them).
- **Not checked:** the skill's upload and what Sonnet 5.5 makes with it (no key here: one real deck is the test, ideally the same "Warszawa" request with and without the skill); whether Anthropic's container can render the deck to images for the skill's last step; Quick Look and its Share sheet on a device; `ThreadFileOpener` and `MessagesView` (not compiled until the hosted Mac job).

## Not built (needs the owner)

Styles picked on the card (`make_document` stays as is; the look is chosen from the words of the request), PDF and image copies, a viewer with Present mode, Google Slides. See the proposal.

# Prompt: put the Doddy website in more languages

Copy everything below the line into a Claude Code session opened on this repository. It builds the machinery, translates the landing page into the same ten languages as the app, and checks the result. It does not deploy anything. Written 2026-10-13 from a read of `site/`; the facts in it were true then, so the session should confirm them first.

The app's equivalent is `TRANSLATION_PROMPT.md` and `README.md` in this folder. Read them: this job reuses their method.

---

You are putting the Doddy website (`site/`) into **Spanish, German, French, Simplified Chinese, Japanese, Brazilian Portuguese, Italian, Croatian and Polish**, next to the English it has today. Work on the branch you are given. Commit in small units. Do not deploy, do not touch Vercel, do not merge.

Before you start, read `CLAUDE.md`, `STATUS.md`, `site/README.md`, `l10n/README.md`, `l10n/REVIEW_NOTES.md`, `docs/design/BRAND_GUIDELINES.md` section 3.8, and `docs/legal/PRIVACY_POLICY_DRAFT.md` (the waitlist row). Confirm the facts below against the files; if one is wrong, say so and adjust.

## What the site is

- **Static, no build step on Vercel.** Plain HTML, CSS and vanilla JavaScript in `site/`. Generated HTML is committed, as `tools/build_blog.py` does for the blog, with `--check` in `scripts/ci.sh`. Follow that pattern: standard-library Python only, no new dependency.
- **One landing page,** `site/index.html`: about 435 lines, `<html lang="en">`, eleven sections (hero, film, problem, how it works, note receipt, voice "In testing", privacy panel, Meet Doddy, Take a shot, Remember it, join), a footer. `site/admin/index.html` is internal and `noindex`: leave it alone.
- **English text also lives outside the HTML:**
  - `site/main.js`: waitlist and optional-question messages, "Open Doddy" messages, the film player.
  - `site/court.js`: the basketball game's lines ("Swish.", "Off the rim.").
  - `site/memory.js`: six memory cards (label and line each), the miss lines, the live-region text and the card labels such as "Card 3: Spare keys, matched".
  - `site/analytics.js`: the Google Analytics consent banner, built in JavaScript ("Can we use Google Analytics? …", Allow, the choices button, `aria-label`).
  - Attributes in `index.html`: `aria-label`, `alt`, `placeholder`, `title`, plus `<title>`, the description and the Open Graph and Twitter tags.
- **Blog:** `blog/posts/*.md` renders to `site/blog/` through `tools/build_blog.py`. Two posts are published. Leave the blog in English for now.
- **Content Security Policy** in `site/vercel.json`: `script-src 'self'` plus the SHA-256 hashes of exactly two inline scripts (the `js` class line and the Vercel analytics queue), `form-action 'none'`. An inline script that is not byte-identical, or a new inline script, is blocked. External scripts from the same origin are allowed.
- **Signup consent is versioned.** `main.js` sends `CONSENT_VERSION = "waitlist-note-v1"`; `site/api/waitlist.js` stores it (cut to 40 characters) with the email; the privacy policy draft describes it. The note under the email field is the wording that version names.
- **Brand and design rules:** the site is light-only; Bricolage Grotesque for headings and Caveat for Doddy's own voice load from Google Fonts; **no font binaries may be added to the repository**; character art comes only from the files already in `site/assets/poses/`; the tagline "Your mate in your pocket." is not translated.
- **Hosting:** Vercel, but the account is blocked and recent builds are cancelled. You cannot see it live. Test with a local server.

## Decisions already made by the owner

- English is the default: `/` stays English. No automatic redirect by browser language. A visible language switcher is how people change.
- The ten languages are the same as the app's, with the app's register: informal "you", Doddy is "he", names and product terms unchanged, Apple's own names for iOS features. The app's finished tables in `l10n/<code>.json` are your glossary: reuse their wording for the same terms (Hey Doddy, early access, notes, lists, reminders, Face ID …) so the site and the app agree.

## What to build

1. **One URL per language,** generated from the English master, root-absolute so they work from any depth: `/es/`, `/de/`, `/fr/`, `/zh-hans/`, `/ja/`, `/pt-br/`, `/it/`, `/hr/`, `/pl/` (lowercase slugs; `hreflang` values `es`, `de`, `fr`, `zh-Hans`, `ja`, `pt-BR`, `it`, `hr`, `pl`). `index.html` uses relative asset paths today (`assets/…`, `tokens.css`, `main.js`): the generated pages must rewrite them to `/assets/…` and so on, and the English page must not change at all.
2. **A generator,** `tools/build_site_i18n.py`, with `--check`, wired into `scripts/ci.sh` next to "Blog pages up to date". It reads `site/index.html` (the English master, the source of truth) and `l10n/site/<code>.json` (English text → that language) and writes `site/<slug>/index.html`. Key the tables by the English text, like the app's tables, so a changed English sentence shows up as a missing translation instead of silently going stale. `--check` fails when a page is out of date, a table lacks or has an extra key, or a translated line breaks a rule below.
3. **Translation units:** text nodes of the page and the attributes listed above. Keep inline markup (`<strong id="made">`, links, `<br>`) inside the unit so a translator can reorder words around it. Skip `<script>`, `<style>`, SVG internals and comments. A translation must keep the same tags, ids, hrefs and classes as the English; order may change. Check that.
4. **Text built in JavaScript:** give each translated page `/i18n/<slug>.js` (loaded before `main.js`) that defines a dictionary, and make `main.js`, `court.js`, `memory.js` and `analytics.js` read it with the **English string kept in the code as the fallback**, so the English page and the existing tests behave exactly as now. Adding a string must need one edit; `--check` must fail if the code asks for a key a language lacks. Strings with parts to fill in ("Card {n}: {label}") use named placeholders that must survive translation.
5. **Head and SEO per page:** `<html lang>`, translated `<title>`, description, Open Graph and Twitter text, `og:locale`, a self-referencing canonical on the language's own URL, and `<link rel="alternate" hreflang>` for every language plus `x-default` pointing at `/`, on every page including the English one. Keep `og:image`. If there is still no `sitemap.xml`, add a minimal one with the alternates.
6. **Language switcher** in the header (and the footer): a plain list of links, each language in its own name ("Deutsch", "日本語"), `lang` and `hreflang` set on each link, `aria-current` on the current one, usable with a keyboard and on a 390 px screen. No dropdown that needs JavaScript. Links to `/blog/` stay, labelled so a visitor knows the blog is in English.
7. **Consent wording gets its own version.** A translated note under the email field and the optional-questions note is different wording, so it must not be recorded as `waitlist-note-v1`. Put the version on the form (`data-consent`), have `main.js` send it, give each language its own id such as `waitlist-note-v1-de`, keep the English at `waitlist-note-v1`, and list every version in `docs/legal/PRIVACY_POLICY_DRAFT.md` next to the existing row. Add a test in `site/test/` that the API stores a translated version. Do not change what the API stores otherwise.
8. **Fonts and layout:** no font files. Add `:lang(zh-Hans)` and `:lang(ja)` rules with system font stacks (for example PingFang SC, Hiragino Sans, Microsoft YaHei, Noto Sans CJK) for headings, body and Doddy's handwriting lines; check Polish and Croatian diacritics render in the existing fonts. German, Croatian and French text runs longer than English: it must wrap, not clip or scroll sideways, in the nav, buttons, chips and cards.

## Rules for the translation

- **Transcreate, don't translate word for word.** Keep meaning, facts and the joke mechanism; drop the English idiom. Short, warm, plain sentences. No exclamation marks the English does not have. Never translate "mate" literally and never script youth slang.
- **Claims must stay exactly as honest as the English.** Keep "In testing", "Later, maybe", "Voice hasn't been tested on a real iPhone yet", "Doddy is an AI assistant, not a person", and every statement about what is stored on the iPhone and what leaves it. Add nothing, soften nothing, drop nothing. Do not add a claim that the app is available in the new languages: they are drafts. The existing sentence that mentions Polish alongside English stays as written; list it for the owner.
- **Privacy, consent and analytics text** (the privacy panel, the footer notes, both form notes, the analytics banner) is translated completely and literally. Do not add reassurance the English does not give.
- **Names stay in English:** Doddy, iPhone, Face ID, Siri, Telegram, TikTok, Instagram, Vercel, Google Analytics, Google Fonts, OpenAI, ElevenLabs. Decline "Doddy" only where the language must, as the app's Polish and Croatian tables do.
- **The tagline** "Your mate in your pocket." stays in English everywhere.
- **Do not touch** the film file, its chapter timings, the poses, or the example note's content beyond translating its visible words; translate chapter names. The film's spoken language does not change, and captions are not part of this job.

## How to work

1. Read, confirm the facts, write a short plan, and record the decision as the next ADR number in `DECISIONS.md` (check the last one first).
2. Build the generator and the extraction for English only, and prove it: the English page must come out byte-identical, `--check` must pass, `npm test --prefix site` must pass. Commit.
3. Add the JavaScript dictionary mechanism and the consent versions. Commit.
4. Translate. Extend `tools/l10n_batch.py` (do not copy it) to also work on the site tables, with the same numbered `show`, `merge`, `status` flow and the same refusals (empty text, changed tags or placeholders). The translator never types a key. If you can start subagents, use one per language, each writing only its own `l10n/site/<code>*.json`; tell them to read the glossary in the app's table for that language first, and to report the lines they are least sure about. Otherwise do the languages one after another.
5. Generate the pages, run every check, take screenshots, fix what they show, commit and push.

## Checks you must run, and report as run or not run

- `python3 -I tools/build_site_i18n.py --check`, `python3 -I tools/build_blog.py --check`, `python3 -I tools/build_strings_catalog.py --check`, `npm test --prefix site`, `scripts/ci.sh --core-only`.
- A structure check on every generated page: same tags, ids and hrefs as English; one `<h1>`; every internal link and asset resolves; no leftover English sentence longer than a few words (list the exceptions); `hreflang` set is complete and reciprocal.
- **CSP:** serve `site/` with the headers from `site/vercel.json` and load every page in headless Chromium (Chromium is installed at `/opt/pw-browsers/chromium`; do not run `playwright install`). Fail on any `securitypolicyviolation` or console error. Also compare the SHA-256 of every inline script in every generated page with the hashes in `vercel.json`.
- **Behaviour in two or three languages, at least German and Japanese:** the waitlist form with a mocked `/api/waitlist` (added, invalid email, server error), the optional questions, the basketball and memory games, the analytics banner, the switcher, keyboard use.
- **Layout:** screenshots of every language at 390 px and 1440 px, and a script that reports horizontal overflow or clipped text per page. Look at the pictures, not only the numbers.
- Say plainly what you could not check: the live site, real devices, a native speaker's read.

## Do not

- Do not change the English page's output, claims, art or colours.
- Do not add dependencies, font files, analytics, trackers, forms, redirects by language, or storage beyond what exists.
- Do not deploy, change Vercel settings, or touch the waitlist data.
- Do not translate the admin page, the API error codes or `site/api/`'s export labels.
- Do not write "supported", "live" or "tested" for a language; call them drafts.

## Report at the end (CLAUDE.md, item 10)

Files changed, what now works, the checks you ran with their output and the ones you did not, manual checks still needed (native review, a phone, the live site), privacy and security risks (especially the consent versions and the analytics banner), decisions for the owner, and the next step. Include the constitution evidence log: the rule ids touched, the code that enforces each, the tests run, the gaps, and the claims you are limiting. Add a `l10n/REVIEW_NOTES.md` section for the site listing each language's least-sure lines and the terms to check, as the app round did.

---

## Languages and URLs

| Language | Table | URL | `hreflang` |
|---|---|---|---|
| English (master) | `site/index.html` | `/` | `en` and `x-default` |
| Spanish | `l10n/site/es.json` | `/es/` | `es` |
| German | `l10n/site/de.json` | `/de/` | `de` |
| French | `l10n/site/fr.json` | `/fr/` | `fr` |
| Simplified Chinese | `l10n/site/zh-Hans.json` | `/zh-hans/` | `zh-Hans` |
| Japanese | `l10n/site/ja.json` | `/ja/` | `ja` |
| Brazilian Portuguese | `l10n/site/pt-BR.json` | `/pt-br/` | `pt-BR` |
| Italian | `l10n/site/it.json` | `/it/` | `it` |
| Croatian | `l10n/site/hr.json` | `/hr/` | `hr` |
| Polish | `l10n/site/pl.json` | `/pl/` | `pl` |

Arabic and Hebrew read right to left and need a layout review first; Korean and Hindi are not in the app yet. Add them later by the same method.

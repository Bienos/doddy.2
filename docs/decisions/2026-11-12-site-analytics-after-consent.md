# The website loads Google Analytics only after the visitor allows it

- **Date:** 2026-11-12
- **Decided by:** requested in the 12 Nov 2026 site hardening task; it reverses the owner's choice of 15 Oct 2026 (no consent step), so the owner confirms it when reviewing the pull request
- **Status:** proposed
- **Replaces:** ADR-245 as amended on 15 Oct 2026 (Google Analytics on every page with no banner)

## Why
Since 15 Oct, `site/analytics.js` loaded Google's tag on every page view and GA set `_ga` cookies with no question asked. The Privacy Policy draft said so ("It runs without asking first") and left the EU consent question open (`docs/legal/LEGAL_PAGES_OWNER_CHECKLIST.md`, B2). Analytics cookies for EU visitors very likely need consent first.

## Decision
- A first visit shows a small banner: Allow / No thanks. Nothing from Google loads before Allow; No thanks means it never loads.
- The choice is kept in `localStorage` (`doddy-analytics-consent`), not in a cookie. "Analytics choices" in every footer opens the banner again.
- Until the visitor allows it, `_ga` / `_ga_*` cookies left from earlier visits are removed.
- Once allowed, the tag starts with ads consent denied and Google signals off: the banner asks about measuring visits only.
- Vercel Web Analytics (no cookies) is unchanged and runs for everyone. Google Fonts is unchanged (`site/README.md`, Needs the owner 4).

## Consequences
- GA will count fewer visits: only those of visitors who tap Allow. Vercel Web Analytics still counts every visit.
- The Privacy Policy's `#website` section (EN, PL) and `docs/legal/PRIVACY_POLICY_DRAFT.md` now describe the banner; B2 stays open for the lawyer to confirm the wording and the consent basis. The policy's version date is unchanged, as in #281's edits to the same draft.
- The banner's texts in the nine other languages are drafts, like the rest of the site's translations.

## Evidence
`npm test` in `site/` (`test/analytics.test.js`), and a headless Chromium check of five pages in four languages (`site/README.md`, Google Analytics 4). Not checked: real Safari, VoiceOver, the live deploy, GA's dashboard.

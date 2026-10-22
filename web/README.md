# Doddy Web

The browser workspace for the same Doddy account the iPhone uses (ADR-585, ADR-586). Built to `web/dist` and served by `backend/` on the same origin, so the session is an HttpOnly cookie and there is no CORS.

- How it works, how to run, test, deploy and roll back: `docs/platforms/web.md`.
- Why it is built this way and what comes next: `docs/architecture/WEB_AND_SHARED_PLATFORM.md`.
- Colours, metrics, wordmark, Doddy's pose and the favicon are generated from the iPhone app by `tools/gen_web_assets.py`; don't edit `src/styles/tokens.css` or `public/brand/` by hand.
- Every visible word is in `src/i18n/messages.ts` (Polish default, English).

```sh
npm ci
npm run typecheck && npm test   # unit tests against contracts/ fixtures
npm run build                   # web/dist
npm run e2e                     # needs backend/ built: real server + Chromium
```

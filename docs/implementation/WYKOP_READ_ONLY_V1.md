# DODDY × Wykop API v3 — read-only adapter (11 November 2026)

**Status:** server-side **adapter and tests only**, not a connected app or live voice tool.
DODDY does not yet hold a Wykop application's credentials, and no real Wykop API
request has been performed. The iPhone app has no Wykop screen or call path in this PR.

## Verified resources

- Official developer entry: https://dev.wykop.pl/
- Official Swagger documentation: https://doc.wykop.pl/
- Official API base: `https://wykop.pl/api/v3`
- Public read endpoints documented by Wykop's API / v3 client implementations:
  `GET /entries?sort=hot&last_update=12&limit=10`;
  `GET /tags/popular`;
  `GET /search/entries?query={encoded query}&limit=10`.
- Wykop application authentication is needed for API calls. Register an app in
  the Wykop developer panel. Application-only JWT suffices for public read
  operations; posting, voting, and private notifications require **different**
  user permissions and are intentionally excluded.

## Implemented

- `backend/src/integrations/wykop.ts`: fixed HTTPS origin and exact GET paths;
  search terms validated and URL encoded; no arbitrary host/method/path;
  caller-injected *server-side* bearer token, never a personal Wykop login.
- Timeouts (8s), redirect refusal, 256 KiB hard response size limit; 10 results max.
- Typed, minimal data: post/tag, safe Wykop URL, excerpt, source, original publish
  date when present. HTML tags stripped; unknown IDs, invalid/NSFW entries discarded.
- Unconfigured/unauthorized/rate-limited/invalid responses fail explicitly;
  **never** emit invented Polish discussions or a fake 'today' date.
- Node tests cover route pinning, normalization, failure cases, and token handling.

## What remains before turning it on

1. Owner registers a Wykop developer application and obtains **app key + secret**.
   Do not paste credentials into chat, GitHub or the app bundle.
2. Implement an authorized server-side application-JWT credential manager
   (with rotation, in-memory caching, Wykop provider rate limits), then
   supply the short-lived token via `WykopToken` to this adapter.
3. Add a secure, bounded backend endpoint or approved voice tool that calls the
   adapter. Apply DODDY authentication, per-user limits and AskFirst to any
   voice API calls. No direct Wykop key on the iPhone.
4. Verify real response schemas and attribution against Wykop API v3
   using the registered app, and confirm usage/caching/commercial terms.
5. Polish UX: present user content as **opinions**, with clickable original URLs,
   not verified news or instructions. Summaries must distinguish claims from facts.
6. Run backend CI and smoke tests before production or TestFlight. Do not merge
   this PR until tests and reviewer checks pass.

## Explicitly excluded

No publishing posts, likes, private DMs, comments, automatic replies, scraping,
account connect, real-time monitoring or notifications. No credentials committed.

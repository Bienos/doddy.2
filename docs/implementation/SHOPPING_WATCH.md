# Shopping stage 2: watching a price ("daj znać, jak spadnie poniżej 1800 zł")

Owner, 24 Oct 2026: "Wszystko rób" (do everything), after a list that included stage 2 of `docs/strategy/TRYB_ZAKUPOW_2026-10.md` section 2 C. This page is the contract; ADR-614 records it. **It only notifies. It never buys, orders, signs in or fills in anything.**

Status: see "Built and checked" at the end (filled in as the parts land).

## 1. What it does

On a pick of a shopping result, "Pilnuj ceny" shows one card with the exact words below. After the user's tap, Doddy's server reads that shop's own page a few times a day for 30 days and sends one notification when the confirmed price is at or below the user's number. Then it stops. The user can stop it, or delete it, any time.

The card says, in the user's language: what is watched (title, shop, the page address), the price that was read just now, the user's price, "I check the page 4 times a day for 30 days, then I stop. I only tell you; I don't buy anything."

## 2. Rules (code enforces them; the prompt isn't involved: no model is used)

- **Exact content, bound to the tap.** Creating a watch makes a draft whose canonical JSON the user approves by its SHA-256 digest (like errands: ERRANDS.md). Only a draft can be approved, only with its own digest, only within 10 minutes. Nothing is checked before the approval.
- **Only a price Doddy can read.** Creating a draft reads the page once, politely (the shared `PoliteFetcher`: `DoddyBot/1.0`, robots.txt, 10 s, 3 MB, HTTPS only, never bypassing a block; ADR-608), from its published product data. If it can't read a price, there is no draft: the user is told why (blocked, not allowed, no price). Listing prices, notes and anything a model wrote are never used.
- **"Dropped" is only said after a confirmed read.** A check that fails or can't read a price is recorded as a failed check, never as a price. A page that says out of stock never triggers. A price in another currency never triggers.
- **Already below.** If the price just read is at or below the user's number, there is no draft ("it is already at or below your price").
- **One notification.** At the first confirmed read at or below the number the watch becomes `triggered`, with the price and the time, and a push is queued (the push has no product words: "Cena, której pilnujesz, spadła." / "A price you're watching dropped."). The app shows the details when opened, with "Kup w sklepie" (the shop's own page).
- **It ends.** After 30 days (`expired`), on the user's Stop (`stopped`), or after 8 failed checks in a row, about two days (`failed`, with a push saying Doddy can no longer read that price, never claiming anything about the price).
- **Caps.** At most 5 active watches per account (`WATCHES_MAX_OPEN`); 30 creates and 30 approvals an hour per device; 4 checks a day per watch (every 6 hours, with a small random shift); the worker checks one watch at a time and leaves at least 2 seconds between two requests to the same host.
- **Off unless on.** `WATCHES_ENABLED` (default `0`) and `MEMORY_ENCRYPTION_KEY`: otherwise every route answers `503 watches_disabled` and nothing is stored or checked.
- **Privacy.** Title, shop and the page address are stored encrypted (AES-256-GCM, AAD `{account}:watch:{id}`) and only for the watch's life: a finished watch (any end) is deleted, content and all, 30 days after it ended; DELETE removes it at once; deleting the account removes all. The server keeps no page content, only the price read, the time and counts. Logs carry ids and counts, never words or addresses.

## 3. Wire (device token on every route; bodies strict; fixture `schemas/fixtures/watch_create_v1.json`)

**`POST /v1/watches`** body: `title` (1 to 120 chars, not blank), `shop` (1 to 80), `url` (https, at most 2048, with a host), `thresholdMinor` (integer, 1 to 1,000,000,000: the user's price in minor units), `currency` (`[A-Z]{3}`), `language` (`[a-z]{2}`). 201 body (the preview): `id`, `digest`, `title`, `shop`, `url`, `thresholdMinor`, `currency`, `language`, `currentMinor` (the price read now), `checkedAt`, `expiresAt` (the draft's, 10 minutes), `days` (30), `checksPerDay` (4).

Errors: `400 invalid_request {fields}`; `422 price_not_readable {reason}` with reason `blocked`, `not_allowed`, `no_price` or `failed`; `422 currency_mismatch` (the page's currency isn't `currency`); `422 already_below {currentMinor}`; `429` (rate limit); `503 watches_disabled`.

**The digest** is SHA-256 (hex) over the canonical JSON of `{checksPerDay, currency, days, language, shop, thresholdMinor, title, url}` with `days` = 30 and `checksPerDay` = 4: keys sorted, no spaces, strings as JavaScript's `JSON.stringify` writes them. The fixture holds the exact text and the digest (computed with Python). The current price is not in it: it varies, and the user approves the promise, not a quote.

**`POST /v1/watches/{id}/approve`** body `{digest}` → `202 {id, state: "active", endsAt}`. Errors: `404 not_found`; `409 not_approvable {state}` (not a draft, or the draft expired); `409 digest_mismatch`; `409 too_many_open_watches`; `503 watches_disabled`.

**`GET /v1/watches`** → `{watches: [summary]}`, newest first, at most 50, drafts left out. **`GET /v1/watches/{id}`** → one summary (404 `not_found`; a draft reads as `state: "draft"` with `expiresAt`).

Summary: `id`, `state` (`draft`, `active`, `triggered`, `expired`, `stopped`, `failed`), `title`, `shop`, `url`, `thresholdMinor`, `currency`, `language`, `createdAt`, `endsAt` (set at approval), `lastCheckedAt?`, `lastPriceMinor?` (the last confirmed price), `checksDone`, `triggeredAt?`, `triggeredPriceMinor?`, `failure?` (`unreadable`). Optional fields are left out, never null.

**`POST /v1/watches/{id}/stop`** (empty body) → `204`; `409 not_stoppable {state}` unless active. **`DELETE /v1/watches/{id}`** → `204` in any state, after the row is gone; `404 not_found`.

## 4. The app

- **Button.** Under "Kup w sklepie" on a pick: "Pilnuj ceny". It opens the card of section 1 with the user's price field (suggested: 5% below the price, rounded down to whole złoty; the user can type another). "Tak, pilnuj" creates the draft, shows the server's preview (with the price it read) and, on the tap, approves that digest. Every refusal is said in words (can't read this shop's price, already below, too many watches, not set up).
- **List.** "Pilnowane ceny": each watch with its state in words ("Pilnuję", "Cena spadła do …", "Skończone po 30 dniach", "Zatrzymane", "Nie mogę już odczytać ceny"), the last confirmed price and when, Stop, Delete and, when triggered, "Kup w sklepie".
- **Not here.** No voice tool yet (it would need its own ask card and agent text; ASK-01). Not in `What leaves this iPhone` until the app row exists: it is added with the screens (the shop's page address, the title and the user's price go to Doddy's messaging server; the server reads that shop's page).

## 5. Failure and recovery

| What goes wrong | What happens |
|---|---|
| The page can't be read at creation | No draft; the user is told why |
| The page can't be read at a check | The check is recorded as failed; 8 in a row end the watch as `failed` with a push that says only that |
| The price is read in another currency, or the page says out of stock | No trigger; the check is recorded |
| The push can't be delivered | The watch is still `triggered`; the app shows it when opened |
| The server restarts | Due watches are picked up again at the next tick; a watch is never checked twice for one due time |
| The user is offline | Nothing is lost: the state is on the server |

## Built and checked

(Filled in as the parts land; see STATUS.md.)

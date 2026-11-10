# Apple or Google on the web opens the same Doddy account the iPhone uses for that sign-in

- **Date:** 2026-11-09
- **Decided by:** owner, 9 Nov 2026: "chce aby ktos na stronie mogl tez uzyc sing in with apple po prostu i z kodem" and, asked whether signing in with Apple in the app gives the same account on the web: "czy jak na apce sie zaloguje z apple to na web bede mial to samo". Approved the change in code ("Tak, PR i scal po zielonym CI").
- **Status:** applied in the pull request that adds this file
- **Replaces:** the linking-first rule of ADR-818 for the same Apple or Google user. Linking stays for joining a different user to an account.

## Why
- ADR-818 was written when the iPhone's account was an anonymous device session. A web sign-in with Apple or Google then had to be linked to it by hand, and one that wasn't got a new, empty account with a random id.
- Since `2026-11-08-required-account` the iPhone's account IS a Supabase user (Apple, Google or email), and every server already calls it by that user's id (`LinkedAccountVerifier`: the id, or the id of the earlier iPhone's data it took over, `account_links`).
- Left as it was, a person who signed in with Apple in the app and then with Apple on the site met an empty second account. On 9 Nov the database held no `web_identities` row and no `account_links` row, so no one had been caught by it yet.

## Decision
1. `GET /v1/web/oauth/callback` (signin): the account opened is, in this order, the one the Supabase user was linked to or made on the web (`web_identities`), then the one it took over an iPhone's data for (`account_links`). Only when neither exists is the person asked "Make a Doddy account?".
2. `POST /v1/web/signup` makes the account with the Supabase user's own id, not a random one, so the web and the iPhone meet in one account. It makes nothing when an iPhone took the user over since the person was sent back; signing in again opens that account.
3. Linking (Settings › Doddy on the web › Link) is unchanged and still joins a different Apple or Google user to an account. Nothing is merged (ADR-600). An account that already exists under another id is never changed.
4. The web copy says so: the same Apple or Google account as on the iPhone opens that account; the "don't make a second account" advice is for someone who uses a different account there.

## Consequences
- Signing in with Apple on the iPhone and on the site is one account, with no step in between. The owner's `/admin` opens with Apple alone: the owner check matches the Supabase user id (`DODDY_OWNER_ACCOUNTS`).
- A web-made account is marked "made on the web" (`web_accounts`), so the site's Delete account is offered for it. For a person who also uses the iPhone with that sign-in, deleting from the site deletes the same account and its Supabase user, like deleting on the iPhone (`eraseUser` queues the Supabase removal once; the queue's key makes a repeat harmless).
- A web account whose only sign-in was unlinked keeps its row; signing in with the same Apple or Google again opens that account again, not an error (`web_accounts` takes the repeat). Its id is the Supabase user's own, so this can only be that user's account.
- Isolation holds: the id comes from a Supabase token this server checked (signature, issuer, audience, provider), so a person can only open their own Supabase user's account; two users never share one.
- Still true: Apple on the web needs Apple's Services ID and key in Supabase (owner queue 28); without them the Apple button fails at Apple.
- Not done: skipping the "Make a Doddy account?" question for someone who already uses the iPhone with that sign-in. The server cannot tell a user it has never seen from a new one (there is no user table), so the question stays; its text now says it opens the iPhone's account.

## Evidence
- Ran: `backend` `node --test dist/test/web-social.test.js` 48 of 48 (one test updated, five added: unlinking a web account's only sign-in and signing in again opens the same account; an account that took over an iPhone's data opens straight in without a question; two Supabase users get two accounts and neither opens the other's; the button makes nothing when the iPhone took the user over in the meantime; the owner's sign-in opens `/v1/web/owner` and another's gets 404). Web: `vitest run` 166 of 166, `tsc --noEmit` clean.
- Not run: the real Supabase, Apple or Google (no Services ID exists yet); a sign-in on a device. That Apple gives the same user id on the web as in the app (Apple's subject is per developer team, so Supabase should match the user) is unchecked until owner queue 28 is done.

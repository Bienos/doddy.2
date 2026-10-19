# Remote branches: what to do with each

Written 2026-10-19 for the owner's review (Phase 1 of the beta plan). **Nothing was deleted, closed or merged.** Measured against main (`claude/loving-dirac-uuxoux`) at `01e7b345` (2026-10-19), after a full fetch of all 141 remote branches.

## Summary

- **141 branches.** Fully on main: 78 (plus main itself). Every change already on main through other commits: 2. With commits that aren't on main: 60.
- **Suggested:** merge 6, keep 22, close 112.
- **Merge** means it goes in through its own small PR after you review it, under the feature freeze: fixes and records of live state only. Nothing on the merge list adds a feature.
- **Keep** means don't merge for the beta, and don't delete: payments, the strategy branch, work another session is still doing, and open PRs for features that may come back after the beta.
- **Close** means main needs nothing from it: it's fully merged, superseded, reverted, throwaway, or frozen work that would have to be redone on main anyway.
- **Before deleting a "close" branch that isn't fully on main,** you could tag its tip (`git tag archive/<name> <tip>` and push the tag), so the commits stay recoverable. The tip of every branch is in the tables.

## How it was measured

- `git fetch --unshallow origin`. The session's clone was shallow at first, and a shallow clone reports merged branches as unmerged.
- **On main:** "yes" when the branch tip is an ancestor of main. "changes on main" when it isn't, but every non-merge commit has an identical change on main (`git log --cherry-pick --right-only main...branch` is empty). Otherwise the number of commits whose change isn't on main.
- **Behind:** commits on main that aren't on the branch.
- **Open PR:** GitHub's list of open pull requests on 19 Oct.
- **The suggestion and reason** come from reading each branch's own commits, `docs/product/V1_SCOPE.md` (ADR-500), the 11 Oct triage (`docs/implementation/BRANCH_TRIAGE_2026-10-11.md`), and the feature freeze. Nothing was built for this list.
- Render deploys only from main (`docs/integrations/DEPLOY_RENDER.md`), and Vercel deploys only main since ADR-498, so deleting a branch can't stop a live deploy.

## Merge (6)

Each one separately, after review. The two marked optional can wait until after the beta.

| Branch | Last commit | Tip | On main | Behind | Open PR | Suggested | Why |
|---|---|---|---|---|---|---|---|
| `claude/happy-volta-9a11kw` | 2026-10-19 | `6b30a251` | no (11 commits) | 19 | #94 | **merge** | Privacy fix: private notes stay out of every Memory-on-calls upload (ADR-310). Also adds three session prompts under `prompts/`. Review the code part on its own. |
| `claude/epic-wright-vz93xh` | 2026-10-19 | `f4d372a6` | no (3 commits) | 19 |  | **merge** | Its voice-address fix is already on main (#88). What's left is the 19 Oct check of the voice token server: all production settings set, deployed from `fc8a502`. Phase 3 needs that record. One conflict with main's header note. |
| `claude/elegant-hopper-6qrj3z` | 2026-10-19 | `c83ac6ac` | no (2 commits) | 19 |  | **merge** | Docs only (`DEPLOY_RENDER.md`): the first live Gmail read and send through Doddy's server, and the Composio grant. Evidence, even though Gmail is hidden in the beta. |
| `claude/trusting-sagan-7lky84` | 2026-10-18 | `58d05b07` | no (1 commit) | 48 |  | **merge** | Two lines in `voice-agent/README.md`: the correct ASK-01 rollback version, and the BLIK session that overwrote the live agent and restored it (`2801`). Phase 2's live sync depends on this being right. |
| `claude/determined-newton-tci3t6` | 2026-10-12 | `f2f03af5` | no (1 commit) | 327 |  | **merge** | Optional, docs only: one research note (`docs/research/COMPETITOR_INSTINCT_2026-10.md`). |
| `claude/sleepy-bell-795a0u` | 2026-10-11 | `7f729257` | no (1 commit) | 546 |  | **merge** | Optional, 2 lines: Settings still shows "TikTok · doddy_mate"; this drops the handle, as the site footer already did. Take the space-after-comma fix from `c3b6d4b2` with it. |

## Keep (22)

| Branch | Last commit | Tip | On main | Behind | Open PR | Suggested | Why |
|---|---|---|---|---|---|---|---|
| `claude/payments-apple-pay-blik` | 2026-10-19 | `15c8ec62` | no (7 commits) | 19 | #89 | **keep** | Payments (Apple Pay and BLIK in test mode, ADR-530). Owner: do not merge. |
| `claude/motion-mv6` | 2026-10-19 | `59475144` | no (10 commits) | 38 |  | **keep** | Top of the motion v2 stack. Its last commit (19 Oct) says "WIP (local, to be amended)", so another session is still working on it. New UI: not for the beta. |
| `claude/motion-mv5` | 2026-10-19 | `94de2f3a` | no (9 commits) | 38 |  | **keep** | Motion v2 stack: behaviours. |
| `claude/motion-mv4` | 2026-10-19 | `e77f11ad` | no (8 commits) | 38 |  | **keep** | Motion v2 stack: Doddy rides what moves. |
| `claude/motion-mv3` | 2026-10-19 | `3106f3e6` | no (7 commits) | 38 |  | **keep** | Motion v2 stack: one Doddy across tabs. |
| `claude/motion-mv2` | 2026-10-19 | `0fd451e8` | no (5 commits) | 38 |  | **keep** | Motion v2 stack: Doddy's surfaces. |
| `claude/bold-noether-gtd1l5` | 2026-10-19 | `fc8a5027` | yes | 19 |  | **keep** | This PR's branch (Phase 1). |
| `claude/motion-v2-plan` | 2026-10-18 | `44bbe294` | no (1 commit) | 62 |  | **keep** | Motion v2 stack, base. All of it is contained in `motion-mv6`. |
| `claude/motion-mv1` | 2026-10-18 | `fd649a10` | no (3 commits) | 38 |  | **keep** | Motion v2 stack: motion engine in DoddyCore. |
| `claude/modest-pasteur-7jnwfd` | 2026-10-18 | `ebf9d360` | no (15 commits) | 38 | #90 | **keep** | Doddy calls on your behalf (ADR-500 to 507 there; 500 is taken on main). New feature, frozen; V1 scope cuts calls. |
| `claude/connect-in-conversation` | 2026-10-18 | `9e6eda44` | no (3 commits) | 62 | #86 | **keep** | Connect an online account from the conversation (draft; claims ADR-483, taken by ASK-01). Frozen while online accounts are hidden. |
| `claude/awesome-cray-2lb9ia` | 2026-10-18 | `1a39a1b2` | no (11 commits) | 62 | #92 | **keep** | Doddy's own phone number, U0 to U4 (draft). New feature, frozen; V1 scope cuts calls and texts. |
| `claude/affectionate-lovelace-4qyfwm` | 2026-10-18 | `ee97d606` | no (1 commit) | 62 | #93 | **keep** | Draft for the owner: `docs/ARCHITECTURE.md` and new rules in `CLAUDE.md`. Your call, since it changes the agent rules. |
| `claude/doddy-strategy-docs` | 2026-10-17 | `38161c11` | no (1 commit) | 62 |  | **keep** | The 17 Oct strategy (memory-recall wedge). This PR copies its three files to main unchanged, then rewrites them to the sprawa direction, so the branch stays as the record of the earlier version. |
| `work` | 2026-10-16 | `0ba262d6` | no (4 commits) | 62 |  | **keep** | Codex work from 16 Oct: personal Home, Orbit island, an Uber Eats handoff, translator changes. New UI and a new integration, so frozen. Your call. |
| `codex/doddy-redesign-voice-timers` | 2026-10-16 | `d91ab9a3` | no (3 commits) | 64 |  | **keep** | Codex work from 16 Oct: voice, Home and timer redesign, Watch and Mac changes, plus startup and store-refresh speedups (`d91ab9a3`). Frozen; the speedup is worth a look if the device run shows a slow start. |
| `claude/jolly-clarke-hclp82` | 2026-10-14 | `17a7fe82` | no (1 commit) | 83 |  | **keep** | One persona for both voice providers, Wiktor by default (claims ADR-483, taken). Decide when the beta's one voice provider is picked (V1 scope decision 5). |
| `claude/youthful-pasteur-25tuhv` | 2026-10-13 | `9f32347b` | no (3 commits) | 259 | #78 | **keep** | "Big brain. Small body." share card for the site and the app (claims ADR-444, taken). After the beta; renumber first. |
| `claude/zealous-lamport-hxt7lw-xcode` | 2026-10-12 | `527f6858` | no (4 commits) | 327 | #63 | **keep** | Draft, not compiled: test seams in the voice controller (fake microphone and link, a second-start test). Useful for Phase 2's session work. 300+ commits behind, so it needs rebuilding on main. |
| `claude/youthful-pasteur-j4orlu` | 2026-10-12 | `936087a6` | no (3 commits) | 327 |  | **keep** | 12 Oct voice prompt diet and speed quick wins. Read before Phase 4 splits the prompt, then close. |
| `claude/fervent-hamilton-ot5z1f` | 2026-10-12 | `668f9b97` | no (10 commits) | 327 |  | **keep** | The earlier payments line: x402 with a Coinbase wallet, `pay_for_page`, and the owner's payment approvals (ADR-450 to 452 there; 450 is taken on main). Kept with payments. |
| `claude/gifted-bardeen-vmepof` | 2026-10-11 | `0a6754af` | no (4 commits) | 327 |  | **keep** | `make team`: keeps the signing team across `make project` with a git-ignored xcconfig (`b44d1666`, `dec1c8c1`). Not on main; look at it in Phase 3 (team change). Its build fixes are superseded. |

## Close: has commits that aren't on main (35)

| Branch | Last commit | Tip | On main | Behind | Open PR | Suggested | Why |
|---|---|---|---|---|---|---|---|
| `claude/payments-ci-diagnose` | 2026-10-19 | `a9bd73ff` | no (8 commits) | 19 |  | **close** | Throwaway CI annotations for PR #89 (its commit says "not for merge"). The payments commits on it are also on `payments-apple-pay-blik`. |
| `claude/voice-access-gate-import` | 2026-10-18 | `1e3b414a` | changes on main | 48 |  | **close** | Every commit's change is already on main (PR #85). |
| `claude/upbeat-ride-5k7ldq` | 2026-10-18 | `28484673` | no (3 commits) | 62 |  | **close** | Same fixes, superseded by PR #84. Its `ARCHITECTURE.md` commit is PR #93. |
| `claude/sweet-albattani-shbi30` | 2026-10-18 | `010702fd` | no (3 commits) | 62 |  | **close** | Fixes for the checks `754e5d6` broke: superseded by PR #84. Its private-notes commits are carried by PR #94 (`happy-volta`). |
| `claude/funny-clarke-hjo92e` | 2026-10-18 | `dc930bd7` | no (1 commit) | 62 |  | **close** | Same guard fix, superseded by PR #84 (ADR-494). |
| `claude/zealous-albattani-7ay32v` | 2026-10-14 | `9fb13161` | no (19 commits) | 128 |  | **close** | 13 Oct status notes for an integration branch and a `build_blog.py` fix; main's `build_blog.py` has been rewritten since. |
| `claude/great-shannon-i93mh3` | 2026-10-14 | `fbddf473` | no (12 commits) | 128 |  | **close** | 13-14 Oct: access codes (retired since `754e5d6`) and "Hey Doddy" on Apple speech (ADR-472, not on main). "Hey Doddy" is hidden in the beta; reopen from `cb0906f6` if it comes back. |
| `claude/affectionate-cray-1c7ftq` | 2026-10-14 | `0d62d163` | no (1 commit) | 78 |  | **close** | Timer Live Activity push (claims ADR-483, taken). Timers are hidden in the beta. |
| `vercel/vercel-web-analytics-to-projec-6x9y6k` | 2026-10-13 | `d9d81627` | no (7 commits) | 327 | #77 | **close** | Vercel Web Analytics on the 12 Oct project. The site has used Google Analytics on every page since `8cd6e3d6`. |
| `claude/quirky-allen-11ijel` | 2026-10-13 | `0a70ca2b` | no (1 commit) | 128 |  | **close** | A site page transition. Site polish, frozen. |
| `claude/friendly-bohr-gy15jv` | 2026-10-13 | `06b2be17` | no (9 commits) | 128 |  | **close** | 13 Oct device-run notes and a UI-test tweak; all 29 UI tests pass on main in hosted CI since 18 Oct. |
| `claude/elegant-bardeen-xgi7c9` | 2026-10-13 | `3e9c2351` | no (1 commit) | 306 |  | **close** | WhatsApp as a second channel, decision only (claims ADR-442, taken). New channel, frozen. |
| `claude/affectionate-tesla-nqu0nj` | 2026-10-13 | `3d223a6c` | no (7 commits) | 306 |  | **close** | 13 Oct Render entry points and go-live runbook; replaced by `GO_LIVE_CHECKLIST.md` (ADR-500) and the current deployments. |
| `claude/adoring-ramanujan-n421km` | 2026-10-13 | `4102f557` | no (1 commit) | 198 |  | **close** | Mockup board for a site page; the site has moved on. |
| `claude/admiring-curie-bsuwv9-all` | 2026-10-13 | `79a89e24` | changes on main | 225 |  | **close** | Every commit's change is already on main (#76, #53, #56, #57, #58). |
| `claude/zealous-hopper-5ctdsc` | 2026-10-12 | `6f852650` | no (8 commits) | 321 | #71 | **close** | Moves the site to `doddy-nine.vercel.app`; the site is on www.doddy.lol now. |
| `claude/wizardly-planck-xmn06p` | 2026-10-12 | `1ecc8849` | no (4 commits) | 327 |  | **close** | ToolCatalog, ToolGate and stale-call dropping are on main under ADR-442 to 445 (#64, #65, #75). |
| `claude/nifty-knuth-qlcec0` | 2026-10-12 | `c9968259` | no (6 commits) | 327 |  | **close** | 12 Oct Vercel team addresses and a `/waitlist` redirect; superseded by the move to www.doddy.lol. |
| `claude/intelligent-albattani-fe7gdf` | 2026-10-12 | `2a7ef084` | no (1 commit) | 327 |  | **close** | Web search through OpenAI's own tool (claims ADR-442, taken). Web search is hidden in the beta. |
| `claude/blissful-davinci-3y2nfo` | 2026-10-12 | `dda8e29f` | no (7 commits) | 299 |  | **close** | 12 Oct integration branch. Its parts are on main or in `gifted-bardeen`, `affectionate-mayer` and `sleepy-bell`. |
| `claude/trusting-lamport-dw5asw` | 2026-10-11 | `e0bf2880` | no (1 commit) | 327 |  | **close** | A Mac menu bar app (ADR-450); the Mac app has been on main since #61. |
| `claude/trusting-dirac-o8ajzc` | 2026-10-11 | `76818f0f` | no (2 commits) | 327 |  | **close** | Voice screen with a sound wave (new UI, adds audio meters to the live session). Frozen, 327 commits behind; redo from main after the beta if wanted. |
| `claude/lucid-johnson-pmwwg4` | 2026-10-11 | `903da206` | no (4 commits) | 523 |  | **close** | "Unlock as you go" (claims ADR-324, taken). Contained in `hopeful-fermat`. |
| `claude/hopeful-fermat-1a63x0` | 2026-10-11 | `09044c85` | no (16 commits) | 340 |  | **close** | 11 Oct round 7: people pages, warranties, bills, parcel codes, leave-by, a Mac app, and an accessibility pass. Frozen, 340 commits behind, conflicts. If the device pass finds VoiceOver problems, look at `40eb8fc9` first. |
| `claude/epic-gauss-md6x9b` | 2026-10-11 | `193c0828` | no (1 commit) | 516 |  | **close** | 11 Oct everyday moments, 2,612 lines, ADR numbers taken. Frozen. |
| `claude/dismiss-ended-card` | 2026-10-11 | `3dae3d9b` | no (6 commits) | 327 |  | **close** | Its three changes were reverted on the branch; it changes nothing. |
| `claude/affectionate-mayer-aovol9` | 2026-10-11 | `4976a1d7` | no (1 commit) | 327 |  | **close** | Island face drawn pre-cut. Visual polish, frozen, 327 commits behind. |
| `claude/eloquent-hawking-pax4bq` | 2026-10-10 | `77bf1e26` | no (1 commit) | 1010 |  | **close** | 8-10 Oct work superseded on main (branch triage 11 Oct, class B). |
| `claude/confident-planck-0gf6qo` | 2026-10-10 | `ed56d352` | no (4 commits) | 1010 |  | **close** | 8-10 Oct work superseded on main (branch triage 11 Oct, class B). |
| `claude/admiring-bohr-0xn7fa` | 2026-10-10 | `1560d766` | no (1 commit) | 1010 |  | **close** | 8-10 Oct work superseded on main (branch triage 11 Oct, class B). |
| `claude/vibrant-pasteur-qroc3f` | 2026-10-09 | `070b7c7f` | no (1 commit) | 1010 |  | **close** | 8-10 Oct work superseded on main (branch triage 11 Oct, class B). |
| `claude/upbeat-brown-c4svzf` | 2026-10-09 | `1bb147b6` | no (3 commits) | 1010 |  | **close** | 8-10 Oct work superseded on main (branch triage 11 Oct, class B). |
| `claude/friendly-sagan-6odwsl` | 2026-10-09 | `e68fc1da` | no (5 commits) | 1010 |  | **close** | Superseded on main (triage class B), except a 401-file video asset library that isn't on main. The art rule allows only the numbered pack, so it's probably not needed: check before deleting. |
| `claude/busy-mendel-cckm8b` | 2026-10-09 | `193a0d87` | no (4 commits) | 1004 |  | **close** | 8-10 Oct work superseded on main (branch triage 11 Oct, class B). |
| `claude/busy-hawking-20w5ql` | 2026-10-08 | `4a95f1cd` | no (9 commits) | 1011 |  | **close** | 8-10 Oct work superseded on main (branch triage 11 Oct, class B). |

## Close: fully on main (78)

Nothing on these is missing from main. Safe to delete whenever you like; a session that still has one checked out can push it again.

| Branch | Last commit | Tip | On main | Behind | Open PR | Suggested | Why |
|---|---|---|---|---|---|---|---|
| `claude/loving-dirac-uuxoux` | 2026-10-19 | `01e7b345` | yes | 0 |  | **main** | The default branch. |
| `claude/fervent-edison-3gnqpq` | 2026-10-19 | `8667cb0f` | yes | 1 |  | **close** | Fully on main. |
| `claude/laughing-darwin-hqxa63` | 2026-10-18 | `70f064f3` | yes | 20 |  | **close** | Fully on main. |
| `claude/dreamy-cannon-gc33dj` | 2026-10-18 | `fc3e16fe` | yes | 39 |  | **close** | Fully on main. |
| `claude/wizardly-knuth-ewbsm7` | 2026-10-15 | `a7bae082` | yes | 73 |  | **close** | Fully on main. |
| `claude/inspiring-rubin-1agiui` | 2026-10-14 | `98b5d761` | yes | 68 |  | **close** | Fully on main. |
| `claude/hopeful-mccarthy-b6x1on` | 2026-10-14 | `6f510003` | yes | 115 |  | **close** | Fully on main. |
| `claude/compassionate-pascal-6c9wo6` | 2026-10-14 | `a8801593` | yes | 87 |  | **close** | Fully on main. |
| `claude/serene-meitner-5t79wn` | 2026-10-13 | `1a8a9d65` | yes | 259 |  | **close** | Fully on main. |
| `claude/relaxed-wright-fox4fe` | 2026-10-13 | `0bc621ec` | yes | 260 |  | **close** | Fully on main. |
| `claude/relaxed-meitner-0d4pky` | 2026-10-13 | `541f7868` | yes | 305 |  | **close** | Fully on main. |
| `claude/peaceful-hopper-v3gx75` | 2026-10-13 | `d8093480` | yes | 238 |  | **close** | Fully on main. |
| `claude/jolly-bell-mlwnqb` | 2026-10-13 | `50267bb7` | yes | 129 |  | **close** | Fully on main. |
| `claude/fervent-hamilton-cv19sj` | 2026-10-13 | `3d8609c4` | yes | 244 |  | **close** | Fully on main. |
| `claude/busy-sagan-oauh04-tool-catalog` | 2026-10-13 | `b2fb3b7f` | yes | 204 |  | **close** | Fully on main. |
| `claude/busy-sagan-oauh04-stale-tests` | 2026-10-13 | `5dba7e89` | yes | 199 |  | **close** | Fully on main. |
| `claude/busy-sagan-oauh04-privacy-rows` | 2026-10-13 | `06425162` | yes | 193 |  | **close** | Fully on main. |
| `claude/busy-sagan-oauh04-opening-test` | 2026-10-13 | `5ab32052` | yes | 195 |  | **close** | Fully on main. |
| `claude/busy-sagan-oauh04-oauth-late` | 2026-10-13 | `675fb4ed` | yes | 193 |  | **close** | Fully on main. |
| `claude/busy-sagan-oauh04-activity-privacy` | 2026-10-13 | `ad1e07f4` | yes | 192 |  | **close** | Fully on main. |
| `claude/busy-sagan-oauh04` | 2026-10-13 | `0846e4dc` | yes | 211 |  | **close** | Fully on main. |
| `claude/admiring-curie-bsuwv9-short-intro` | 2026-10-13 | `99722fba` | yes | 298 |  | **close** | Fully on main. |
| `claude/admiring-curie-bsuwv9-quick-access` | 2026-10-13 | `49fd346f` | yes | 219 |  | **close** | Fully on main. |
| `claude/admiring-curie-bsuwv9-onboarding` | 2026-10-13 | `b68db537` | yes | 298 |  | **close** | Fully on main. |
| `claude/admiring-curie-bsuwv9-home-first-visit` | 2026-10-13 | `b807be05` | yes | 289 |  | **close** | Fully on main. |
| `claude/admiring-curie-bsuwv9-hey-doddy-card` | 2026-10-13 | `d6ece5d2` | yes | 251 |  | **close** | Fully on main. |
| `claude/admiring-curie-bsuwv9-first-conversation` | 2026-10-13 | `eb208c35` | yes | 230 |  | **close** | Fully on main. |
| `claude/admiring-curie-bsuwv9-ask-about-note` | 2026-10-13 | `fb0f3535` | yes | 241 |  | **close** | Fully on main. |
| `claude/admiring-curie-bsuwv9` | 2026-10-13 | `141fa9a7` | yes | 290 |  | **close** | Fully on main. |
| `claude/zealous-lamport-hxt7lw` | 2026-10-12 | `e742449b` | yes | 324 |  | **close** | Fully on main. |
| `claude/jolly-bell-mlwnqb-uitests` | 2026-10-12 | `20a6e031` | yes | 313 |  | **close** | Fully on main. |
| `claude/admiring-curie-bsuwv9-news-test-fix` | 2026-10-12 | `bfdf6da5` | yes | 326 |  | **close** | Fully on main. |
| `claude/admiring-curie-bsuwv9-ios-build` | 2026-10-12 | `81fd5623` | yes | 325 |  | **close** | Fully on main. |
| `claude/sleepy-gates-f9najr` | 2026-10-11 | `fe5d6fa2` | yes | 569 |  | **close** | Fully on main. |
| `claude/eager-johnson-bu42em` | 2026-10-11 | `11fb8922` | yes | 544 |  | **close** | Fully on main. |
| `claude/dazzling-pascal-mr4zjn-db-timeout` | 2026-10-11 | `03b926af` | yes | 667 |  | **close** | Fully on main. |
| `claude/dazzling-pascal-mr4zjn` | 2026-10-11 | `984a24da` | yes | 665 |  | **close** | Fully on main. |
| `claude/cool-archimedes-9l8l1h` | 2026-10-11 | `94f56010` | yes | 328 |  | **close** | Fully on main. |
| `claude/camera-shortcut-button` | 2026-10-11 | `24a44f71` | yes | 547 |  | **close** | Fully on main. |
| `claude/busy-wozniak-15yzp7` | 2026-10-11 | `b8444359` | yes | 333 |  | **close** | Fully on main. |
| `claude/blissful-einstein-5msya4` | 2026-10-11 | `7feae154` | yes | 660 |  | **close** | Fully on main. |
| `claude/affectionate-edison-ktc6i6` | 2026-10-11 | `afc4a1e7` | yes | 496 |  | **close** | Fully on main. |
| `codex/doddy2-native-baseline` | 2026-10-10 | `d103726a` | yes | 993 |  | **close** | Fully on main. |
| `claude/youthful-fermi-qn62y0` | 2026-10-10 | `3439a193` | yes | 749 |  | **close** | Fully on main. |
| `claude/wonderful-cray-s5r90b` | 2026-10-10 | `153e8a79` | yes | 765 |  | **close** | Fully on main. |
| `claude/tender-lamport-08yl04` | 2026-10-10 | `123ccd69` | yes | 726 |  | **close** | Fully on main. |
| `claude/stoic-pasteur-sxkce7` | 2026-10-10 | `d20f4eee` | yes | 772 |  | **close** | Fully on main. |
| `claude/serene-johnson-0jz6ao` | 2026-10-10 | `756fcdcc` | yes | 840 |  | **close** | Fully on main. |
| `claude/serene-davinci-as4pyg` | 2026-10-10 | `6825a190` | yes | 752 |  | **close** | Fully on main. |
| `claude/magical-newton-ip0bx2` | 2026-10-10 | `c2aacc91` | yes | 896 |  | **close** | Fully on main. |
| `claude/lucid-sagan-mpwylm` | 2026-10-10 | `2d8b73aa` | yes | 763 |  | **close** | Fully on main. |
| `claude/inspiring-knuth-sgk8v0` | 2026-10-10 | `e08efdd7` | yes | 794 |  | **close** | Fully on main. |
| `claude/gallant-lamport-7x7k5w` | 2026-10-10 | `95cf65ad` | yes | 747 |  | **close** | Fully on main. |
| `claude/eloquent-pasteur-7ruafk` | 2026-10-10 | `cba47981` | yes | 1008 |  | **close** | Fully on main. |
| `claude/elegant-knuth-hc1aql` | 2026-10-10 | `de0cb8d1` | yes | 732 |  | **close** | Fully on main. |
| `claude/elegant-dijkstra-0r1bg5` | 2026-10-10 | `23bba4d4` | yes | 1009 |  | **close** | Fully on main. |
| `claude/compassionate-darwin-6wi1ba` | 2026-10-10 | `e262fb31` | yes | 864 |  | **close** | Fully on main. |
| `claude/clever-ritchie-f7w234` | 2026-10-10 | `7f93e65e` | yes | 901 |  | **close** | Fully on main. |
| `claude/clever-gates-b0mkhs` | 2026-10-10 | `6df70085` | yes | 772 |  | **close** | Fully on main. |
| `claude/busy-galileo-v68apl` | 2026-10-10 | `bb24a101` | yes | 917 |  | **close** | Fully on main. |
| `claude/brave-wright-k4jnu3` | 2026-10-10 | `4699db76` | yes | 858 |  | **close** | Fully on main. |
| `claude/blissful-thompson-72xwl1` | 2026-10-10 | `27343f10` | yes | 926 |  | **close** | Fully on main. |
| `claude/blissful-curie-ftam0y` | 2026-10-10 | `ca7a0261` | yes | 758 |  | **close** | Fully on main. |
| `claude/stoic-lamport-6iz5dw` | 2026-10-09 | `b535b284` | yes | 999 |  | **close** | Fully on main. |
| `claude/nifty-euler-w6vgdb` | 2026-10-09 | `3ff4dd7e` | yes | 1005 |  | **close** | Fully on main. |
| `claude/nice-thompson-6exq2t` | 2026-10-09 | `c1d822a5` | yes | 1009 |  | **close** | Fully on main. |
| `claude/nice-albattani-t1yan6` | 2026-10-09 | `1d9b6437` | yes | 994 |  | **close** | Fully on main. |
| `claude/kind-davinci-kfndaz` | 2026-10-09 | `f3726d6c` | yes | 1009 |  | **close** | Fully on main. |
| `claude/keen-cray-g4g5vj` | 2026-10-09 | `dae8a2ed` | yes | 1007 |  | **close** | Fully on main. |
| `claude/inspiring-einstein-j3lvjc` | 2026-10-09 | `585514c2` | yes | 995 |  | **close** | Fully on main. |
| `claude/gifted-hypatia-u6vwds` | 2026-10-09 | `6b67e827` | yes | 1009 |  | **close** | Fully on main. |
| `claude/dreamy-mayer-u3rtx4` | 2026-10-09 | `d7076da6` | yes | 998 |  | **close** | Fully on main. |
| `claude/determined-sagan-x34oz2` | 2026-10-09 | `d475fb12` | yes | 1004 |  | **close** | Fully on main. |
| `claude/cool-rubin-xywy2g` | 2026-10-09 | `2e500820` | yes | 1008 |  | **close** | Fully on main. |
| `claude/cool-euler-wu64g8` | 2026-10-09 | `354b950d` | yes | 1009 |  | **close** | Fully on main. |
| `claude/clever-davinci-6icfxq` | 2026-10-09 | `83bd8aca` | yes | 999 |  | **close** | Fully on main. |
| `claude/brave-keller-f8h6uq` | 2026-10-09 | `9a47e0d9` | yes | 935 |  | **close** | Fully on main. |
| `claude/lucid-rubin-h8mfmr` | 2026-10-08 | `c5b37092` | yes | 1015 |  | **close** | Fully on main. |


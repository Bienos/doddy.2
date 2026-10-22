# Remote branches against main

Measured 22 Oct 2026 against main at `8aa42c59` (`claude/loving-dirac-uuxoux`). **180 remote branches** besides main. Written by the `claude/release-0-1` cleanup. **Nothing has been deleted or closed**; this list is for the owner to confirm.

How to read it:
- **Ahead of main** is `git rev-list --count main..branch`. **Unique patches** is the number of those commits whose change is *not* already in main (`git cherry`, `+` lines), so a branch with 0 unique patches has nothing left to merge.
- **Tip SHA** is recorded so a deleted branch can be restored with `git branch <name> <sha>` while GitHub still has the commits.
- The recommendation is a **rule-based proposal, not a review**: open PR means see the PR table; committed in the last 48 hours means keep (another session may be using it); 0 ahead or 0 unique patches means delete; notes taken from `STATUS.md` (checked 19 to 20 Oct) where it names the branch; any other unmerged branch older than 7 days is a close candidate. Nobody has read the 100-odd old ones.
- Branches with a rule-based "CLOSE candidate" may still hold work the owner wants. Ask before deleting any with unique patches.

Counts: 35 fully merged into main, 1 more with no unique patches, 144 with unique unmerged work.

## Branches with commits not in main (145)

| Branch | Last commit | Ahead of main | Unique patches | Tip SHA | Recommendation |
|---|---|---|---|---|---|
| `claude/exciting-carson-08x2pk` | 2026-10-22 | 31 | 27 | `ea58caa01a` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/gifted-pascal-3e117c` | 2026-10-22 | 7 | 7 | `8971f0eb4f` | Open PR #124: see PR table |
| `claude/eloquent-brahmagupta-kxn9x3` | 2026-10-22 | 1 | 1 | `07d691d557` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/confident-shannon-wrux16` | 2026-10-22 | 5 | 5 | `66a910a23a` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/eloquent-brahmagupta-zw2bcx` | 2026-10-22 | 1 | 1 | `87b611052f` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/gracious-ptolemy-mybt3a` | 2026-10-20 | 1 | 1 | `bcefcece16` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/fix-ways-test-tap` | 2026-10-20 | 1 | 1 | `28cd3c107c` | Open PR #116: see PR table |
| `claude/probe-iphone-device` | 2026-10-20 | 1 | 1 | `1d317f86d6` | KEEP for now: committed in the last 48 h, a session may be using it. STATUS.md says: Throwaway probe; never merge (PR #116 text). Delete. |
| `claude/calm-home-eyes` | 2026-10-20 | 6 | 4 | `02bef9f226` | KEEP for now: committed in the last 48 h, a session may be using it. STATUS.md says: Superseded by #114 (eyes on the persistent Doddy). Close; the bottom-sheet part is optional. |
| `claude/wizardly-cannon-k0u1mv` | 2026-10-20 | 14 | 3 | `428e5626e9` | KEEP for now: committed in the last 48 h, a session may be using it. STATUS.md says: 20 Oct test build; not for main (STATUS.md). Delete. |
| `claude/ecstatic-allen-ptjm3u` | 2026-10-20 | 1 | 1 | `8b769ce203` | KEEP for now: committed in the last 48 h, a session may be using it. STATUS.md says: Docs only (Eleven Realtime Max); merges cleanly (STATUS.md). Merge if still true. |
| `claude/sweet-newton-2z7asj` | 2026-10-20 | 3 | 3 | `b1fbd72f93` | Duplicates #108; nothing left (STATUS.md). |
| `claude/busy-volta-qgwgz3` | 2026-10-20 | 5 | 3 | `b2ce2d1ff5` | Nothing left to merge (STATUS.md). |
| `claude/motion-probe-mv7` | 2026-10-20 | 1 | 1 | `0a2fc67371` | Throwaway probe, never merge (STATUS.md). Delete. |
| `claude/motion-probe` | 2026-10-19 | 5 | 2 | `3fe71c7d55` | Throwaway probe (STATUS.md). Delete. |
| `claude/payments-apple-pay-blik` | 2026-10-19 | 12 | 10 | `1d545b532d` | Open PR #89: see PR table |
| `claude/payments-diag-overlay` | 2026-10-19 | 11 | 9 | `dc7b5cf958` | KEEP/REVIEW: 11 unmerged commit(s), 3 days old, no PR |
| `claude/payments-diag-safari` | 2026-10-19 | 11 | 9 | `5530cebe12` | KEEP/REVIEW: 11 unmerged commit(s), 3 days old, no PR |
| `claude/payments-diag-passkit` | 2026-10-19 | 11 | 9 | `6a422a2382` | KEEP/REVIEW: 11 unmerged commit(s), 3 days old, no PR |
| `claude/bold-hawking-38iysy` | 2026-10-19 | 1 | 1 | `2cd4beed14` | Open PR #104: see PR table |
| `claude/payments-diag-control` | 2026-10-19 | 11 | 9 | `e1ebaef7c3` | KEEP/REVIEW: 11 unmerged commit(s), 3 days old, no PR |
| `claude/payments-diag-toolbar` | 2026-10-19 | 11 | 9 | `de164c777e` | KEEP/REVIEW: 11 unmerged commit(s), 3 days old, no PR |
| `claude/inspiring-volta-bkuat4` | 2026-10-19 | 8 | 8 | `ef7c85e8f5` | KEEP/REVIEW: 8 unmerged commit(s), 3 days old, no PR |
| `claude/elegant-hopper-6qrj3z` | 2026-10-19 | 1 | 1 | `54c08ee35d` | KEEP/REVIEW: 1 unmerged commit(s), 3 days old, no PR |
| `claude/bold-noether-gtd1l5` | 2026-10-19 | 11 | 10 | `77cf6f4ae0` | Open PR #96: see PR table |
| `claude/payments-ci-diagnose` | 2026-10-19 | 9 | 8 | `a9bd73ffac` | Throwaway diagnosis branch (PR #89 text). Delete. |
| `claude/epic-wright-vz93xh` | 2026-10-19 | 4 | 3 | `f4d372a6d4` | Superseded by #84 and #88 (STATUS.md). |
| `claude/voice-access-gate-import` | 2026-10-18 | 1 | 0 | `1e3b414a32` | DELETE: every commit's change is already in main (patch-identical) |
| `claude/awesome-cray-2lb9ia` | 2026-10-18 | 11 | 11 | `1a39a1b2b9` | Open PR #92: see PR table |
| `claude/trusting-sagan-7lky84` | 2026-10-18 | 1 | 1 | `58d05b076f` | KEEP/REVIEW: 1 unmerged commit(s), 4 days old, no PR |
| `claude/connect-in-conversation` | 2026-10-18 | 3 | 3 | `9e6eda442d` | Open PR #86: see PR table |
| `claude/sweet-albattani-shbi30` | 2026-10-18 | 3 | 1 | `010702fd82` | KEEP/REVIEW: 3 unmerged commit(s), 4 days old, no PR |
| `claude/upbeat-ride-5k7ldq` | 2026-10-18 | 3 | 3 | `2848467301` | KEEP/REVIEW: 3 unmerged commit(s), 4 days old, no PR |
| `claude/funny-clarke-hjo92e` | 2026-10-18 | 1 | 1 | `dc930bd79e` | KEEP/REVIEW: 1 unmerged commit(s), 4 days old, no PR |
| `claude/affectionate-lovelace-4qyfwm` | 2026-10-18 | 1 | 1 | `ee97d60656` | Open PR #93: see PR table |
| `claude/doddy-strategy-docs` | 2026-10-17 | 1 | 1 | `38161c11e2` | KEEP/REVIEW: 1 unmerged commit(s), 4 days old, no PR |
| `work` | 2026-10-16 | 5 | 4 | `0ba262d631` | KEEP/REVIEW: 5 unmerged commit(s), 6 days old, no PR |
| `codex/doddy-redesign-voice-timers` | 2026-10-16 | 3 | 3 | `d91ab9a312` | KEEP/REVIEW: 3 unmerged commit(s), 6 days old, no PR |
| `claude/affectionate-cray-1c7ftq` | 2026-10-14 | 1 | 1 | `0d62d16362` | CLOSE candidate: 1 unmerged commit(s), 7 days old, no PR. Owner to confirm |
| `claude/jolly-clarke-hclp82` | 2026-10-14 | 1 | 1 | `17a7fe8282` | CLOSE candidate: 1 unmerged commit(s), 7 days old, no PR. Owner to confirm |
| `claude/great-shannon-i93mh3` | 2026-10-14 | 228 | 149 | `fbddf473ba` | CLOSE candidate: 228 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/zealous-albattani-7ay32v` | 2026-10-14 | 290 | 180 | `9fb1316155` | CLOSE candidate: 290 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/quirky-allen-11ijel` | 2026-10-13 | 1 | 1 | `0a70ca2b1a` | CLOSE candidate: 1 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/friendly-bohr-gy15jv` | 2026-10-13 | 276 | 170 | `06b2be17e7` | CLOSE candidate: 276 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/adoring-ramanujan-n421km` | 2026-10-13 | 1 | 1 | `4102f557bf` | CLOSE candidate: 1 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/busy-sagan-oauh04-opening-test` | 2026-10-13 | 265 | 162 | `5ab3205235` | CLOSE candidate: 265 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/busy-sagan-oauh04-privacy-rows` | 2026-10-13 | 267 | 162 | `064251629f` | CLOSE candidate: 267 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/busy-sagan-oauh04-activity-privacy` | 2026-10-13 | 268 | 162 | `ad1e07f487` | CLOSE candidate: 268 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/busy-sagan-oauh04-oauth-late` | 2026-10-13 | 267 | 162 | `675fb4ed8b` | CLOSE candidate: 267 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/busy-sagan-oauh04-stale-tests` | 2026-10-13 | 322 | 177 | `5dba7e893d` | CLOSE candidate: 322 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/busy-sagan-oauh04-tool-catalog` | 2026-10-13 | 317 | 176 | `b2fb3b7ff2` | CLOSE candidate: 317 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/busy-sagan-oauh04` | 2026-10-13 | 310 | 175 | `0846e4dc89` | CLOSE candidate: 310 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/youthful-pasteur-25tuhv` | 2026-10-13 | 265 | 164 | `9f32347b2a` | Open PR #78: see PR table |
| `claude/admiring-curie-bsuwv9-quick-access` | 2026-10-13 | 302 | 173 | `49fd346fc5` | CLOSE candidate: 302 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/admiring-curie-bsuwv9-first-conversation` | 2026-10-13 | 291 | 171 | `eb208c35bc` | CLOSE candidate: 291 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/admiring-curie-bsuwv9-ask-about-note` | 2026-10-13 | 280 | 169 | `fb0f3535de` | CLOSE candidate: 280 unmerged commit(s), 8 days old, no PR. Owner to confirm |
| `claude/fervent-hamilton-cv19sj` | 2026-10-13 | 277 | 172 | `3d8609c4e6` | CLOSE candidate: 277 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/peaceful-hopper-v3gx75` | 2026-10-13 | 277 | 168 | `d809348088` | CLOSE candidate: 277 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `vercel/vercel-web-analytics-to-projec-6x9y6k` | 2026-10-13 | 201 | 128 | `d9d8162782` | Open PR #77: see PR table |
| `claude/admiring-curie-bsuwv9-all` | 2026-10-13 | 339 | 173 | `79a89e2474` | CLOSE candidate: 339 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/admiring-curie-bsuwv9-hey-doddy-card` | 2026-10-13 | 270 | 165 | `d6ece5d264` | CLOSE candidate: 270 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/serene-meitner-5t79wn` | 2026-10-13 | 262 | 161 | `1a8a9d6581` | CLOSE candidate: 262 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/relaxed-wright-fox4fe` | 2026-10-13 | 261 | 161 | `0bc621eced` | CLOSE candidate: 261 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/affectionate-tesla-nqu0nj` | 2026-10-13 | 222 | 144 | `3d223a6c66` | CLOSE candidate: 222 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/relaxed-meitner-0d4pky` | 2026-10-13 | 216 | 138 | `541f7868b4` | CLOSE candidate: 216 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/admiring-curie-bsuwv9-home-first-visit` | 2026-10-13 | 232 | 144 | `b807be05ef` | CLOSE candidate: 232 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/admiring-curie-bsuwv9` | 2026-10-13 | 231 | 147 | `141fa9a7bb` | CLOSE candidate: 231 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/admiring-curie-bsuwv9-short-intro` | 2026-10-13 | 223 | 142 | `99722fba8c` | CLOSE candidate: 223 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/elegant-bardeen-xgi7c9` | 2026-10-13 | 216 | 138 | `3e9c23515a` | CLOSE candidate: 216 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/admiring-curie-bsuwv9-onboarding` | 2026-10-13 | 223 | 140 | `b68db5378a` | CLOSE candidate: 223 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/zealous-hopper-5ctdsc` | 2026-10-12 | 209 | 132 | `6f8526505b` | Open PR #71: see PR table |
| `claude/jolly-bell-mlwnqb-uitests` | 2026-10-12 | 208 | 135 | `20a6e0318a` | CLOSE candidate: 208 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/determined-newton-tci3t6` | 2026-10-12 | 195 | 122 | `f2f03af5c9` | CLOSE candidate: 195 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/intelligent-albattani-fe7gdf` | 2026-10-12 | 195 | 122 | `2a7ef084b2` | CLOSE candidate: 195 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/youthful-pasteur-j4orlu` | 2026-10-12 | 197 | 124 | `936087a67c` | CLOSE candidate: 197 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/admiring-curie-bsuwv9-ios-build` | 2026-10-12 | 196 | 123 | `81fd5623cc` | CLOSE candidate: 196 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/admiring-curie-bsuwv9-news-test-fix` | 2026-10-12 | 195 | 122 | `bfdf6da52d` | CLOSE candidate: 195 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/fervent-hamilton-ot5z1f` | 2026-10-12 | 204 | 131 | `668f9b97d4` | CLOSE candidate: 204 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/wizardly-planck-xmn06p` | 2026-10-12 | 198 | 125 | `1ecc8849fb` | CLOSE candidate: 198 unmerged commit(s), 9 days old, no PR. Owner to confirm |
| `claude/nifty-knuth-qlcec0` | 2026-10-12 | 200 | 127 | `c9968259f5` | CLOSE candidate: 200 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/zealous-lamport-hxt7lw-xcode` | 2026-10-12 | 201 | 125 | `527f6858db` | Open PR #63: see PR table |
| `claude/zealous-lamport-hxt7lw` | 2026-10-12 | 197 | 123 | `e742449b9f` | CLOSE candidate: 197 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/blissful-davinci-3y2nfo` | 2026-10-12 | 247 | 143 | `dda8e29f86` | CLOSE candidate: 247 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/dismiss-ended-card` | 2026-10-11 | 200 | 127 | `3dae3d9bb3` | Its changes were reverted (STATUS.md). Delete. |
| `claude/affectionate-mayer-aovol9` | 2026-10-11 | 195 | 122 | `4976a1d7a3` | Island compact face; low risk (STATUS.md). Owner call. |
| `claude/trusting-dirac-o8ajzc` | 2026-10-11 | 196 | 123 | `76818f0ff8` | Voice screen with sound wave; medium risk to voice (STATUS.md). Owner call. |
| `claude/trusting-lamport-dw5asw` | 2026-10-11 | 195 | 122 | `e0bf288034` | CLOSE candidate: 195 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/gifted-bardeen-vmepof` | 2026-10-11 | 199 | 126 | `0a6754af94` | CLOSE candidate: 199 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/cool-archimedes-9l8l1h` | 2026-10-11 | 193 | 121 | `94f56010cf` | CLOSE candidate: 193 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/hopeful-fermat-1a63x0` | 2026-10-11 | 199 | 129 | `09044c8565` | CLOSE candidate: 199 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/busy-wozniak-15yzp7` | 2026-10-11 | 188 | 117 | `b844435998` | CLOSE candidate: 188 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/epic-gauss-md6x9b` | 2026-10-11 | 107 | 60 | `193c0828e0` | CLOSE candidate: 107 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/affectionate-edison-ktc6i6` | 2026-10-11 | 123 | 72 | `afc4a1e742` | CLOSE candidate: 123 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/lucid-johnson-pmwwg4` | 2026-10-11 | 103 | 58 | `903da2067c` | CLOSE candidate: 103 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/eager-johnson-bu42em` | 2026-10-11 | 82 | 44 | `11fb8922b0` | CLOSE candidate: 82 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/sleepy-bell-795a0u` | 2026-10-11 | 81 | 44 | `7f72925738` | CLOSE candidate: 81 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/camera-shortcut-button` | 2026-10-11 | 79 | 43 | `24a44f7183` | CLOSE candidate: 79 unmerged commit(s), 10 days old, no PR. Owner to confirm |
| `claude/sleepy-gates-f9najr` | 2026-10-11 | 64 | 35 | `fe5d6fa28a` | CLOSE candidate: 64 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/blissful-einstein-5msya4` | 2026-10-11 | 20 | 10 | `7feae1549d` | CLOSE candidate: 20 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/dazzling-pascal-mr4zjn-db-timeout` | 2026-10-11 | 14 | 8 | `03b926af7f` | CLOSE candidate: 14 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/dazzling-pascal-mr4zjn` | 2026-10-11 | 16 | 10 | `984a24dad4` | CLOSE candidate: 16 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/elegant-knuth-hc1aql` | 2026-10-10 | 286 | 221 | `de0cb8d1e6` | CLOSE candidate: 286 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/tender-lamport-08yl04` | 2026-10-10 | 292 | 223 | `123ccd6970` | CLOSE candidate: 292 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/youthful-fermi-qn62y0` | 2026-10-10 | 269 | 208 | `3439a193ed` | CLOSE candidate: 269 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/gallant-lamport-7x7k5w` | 2026-10-10 | 271 | 209 | `95cf65ad13` | CLOSE candidate: 271 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/serene-davinci-as4pyg` | 2026-10-10 | 266 | 206 | `6825a190e4` | CLOSE candidate: 266 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/blissful-curie-ftam0y` | 2026-10-10 | 260 | 201 | `ca7a0261d1` | CLOSE candidate: 260 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/wonderful-cray-s5r90b` | 2026-10-10 | 253 | 197 | `153e8a7937` | CLOSE candidate: 253 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/lucid-sagan-mpwylm` | 2026-10-10 | 255 | 198 | `2d8b73aa84` | CLOSE candidate: 255 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/stoic-pasteur-sxkce7` | 2026-10-10 | 246 | 192 | `d20f4eee17` | CLOSE candidate: 246 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/clever-gates-b0mkhs` | 2026-10-10 | 246 | 192 | `6df70085de` | CLOSE candidate: 246 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/compassionate-darwin-6wi1ba` | 2026-10-10 | 154 | 130 | `e262fb3153` | CLOSE candidate: 154 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/brave-wright-k4jnu3` | 2026-10-10 | 160 | 136 | `4699db76c4` | CLOSE candidate: 160 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/admiring-bohr-0xn7fa` | 2026-10-10 | 9 | 9 | `1560d766f1` | CLOSE candidate: 9 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/inspiring-knuth-sgk8v0` | 2026-10-10 | 224 | 177 | `e08efdd789` | CLOSE candidate: 224 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/elegant-dijkstra-0r1bg5` | 2026-10-10 | 9 | 9 | `23bba4d460` | CLOSE candidate: 9 unmerged commit(s), 11 days old, no PR. Owner to confirm |
| `claude/confident-planck-0gf6qo` | 2026-10-10 | 13 | 13 | `ed56d352a7` | CLOSE candidate: 13 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/serene-johnson-0jz6ao` | 2026-10-10 | 178 | 142 | `756fcdcc26` | CLOSE candidate: 178 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/busy-galileo-v68apl` | 2026-10-10 | 101 | 86 | `bb24a101f6` | CLOSE candidate: 101 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/clever-ritchie-f7w234` | 2026-10-10 | 117 | 99 | `7f93e65e12` | CLOSE candidate: 117 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/magical-newton-ip0bx2` | 2026-10-10 | 122 | 101 | `c2aacc9147` | CLOSE candidate: 122 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `codex/doddy2-native-baseline` | 2026-10-10 | 25 | 24 | `d103726a59` | CLOSE candidate: 25 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/eloquent-pasteur-7ruafk` | 2026-10-10 | 10 | 10 | `cba4798104` | CLOSE candidate: 10 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/blissful-thompson-72xwl1` | 2026-10-10 | 92 | 79 | `27343f106d` | CLOSE candidate: 92 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/eloquent-hawking-pax4bq` | 2026-10-10 | 9 | 9 | `77bf1e26ba` | CLOSE candidate: 9 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/friendly-sagan-6odwsl` | 2026-10-09 | 13 | 13 | `e68fc1daa3` | CLOSE candidate: 13 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/brave-keller-f8h6uq` | 2026-10-09 | 83 | 71 | `9a47e0d91c` | CLOSE candidate: 83 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/busy-mendel-cckm8b` | 2026-10-09 | 19 | 18 | `193a0d87a9` | CLOSE candidate: 19 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/determined-sagan-x34oz2` | 2026-10-09 | 14 | 14 | `d475fb12fd` | CLOSE candidate: 14 unmerged commit(s), 12 days old, no PR. Owner to confirm |
| `claude/kind-davinci-kfndaz` | 2026-10-09 | 9 | 9 | `f3726d6c20` | CLOSE candidate: 9 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/nice-albattani-t1yan6` | 2026-10-09 | 24 | 23 | `1d9b6437b6` | CLOSE candidate: 24 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/gifted-hypatia-u6vwds` | 2026-10-09 | 9 | 9 | `6b67e827f2` | CLOSE candidate: 9 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/dreamy-mayer-u3rtx4` | 2026-10-09 | 20 | 20 | `d7076da6b0` | CLOSE candidate: 20 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/keen-cray-g4g5vj` | 2026-10-09 | 11 | 11 | `dae8a2edd8` | CLOSE candidate: 11 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/clever-davinci-6icfxq` | 2026-10-09 | 19 | 19 | `83bd8aca62` | CLOSE candidate: 19 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/cool-rubin-xywy2g` | 2026-10-09 | 10 | 10 | `2e50082062` | CLOSE candidate: 10 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/cool-euler-wu64g8` | 2026-10-09 | 9 | 9 | `354b950d28` | CLOSE candidate: 9 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/nice-thompson-6exq2t` | 2026-10-09 | 9 | 9 | `c1d822a565` | CLOSE candidate: 9 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/nifty-euler-w6vgdb` | 2026-10-09 | 13 | 13 | `3ff4dd7ef1` | CLOSE candidate: 13 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/vibrant-pasteur-qroc3f` | 2026-10-09 | 9 | 9 | `070b7c7f95` | CLOSE candidate: 9 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/inspiring-einstein-j3lvjc` | 2026-10-09 | 23 | 22 | `585514c211` | CLOSE candidate: 23 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/upbeat-brown-c4svzf` | 2026-10-09 | 11 | 11 | `1bb147b627` | CLOSE candidate: 11 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/stoic-lamport-6iz5dw` | 2026-10-09 | 19 | 19 | `b535b284f1` | CLOSE candidate: 19 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/busy-hawking-20w5ql` | 2026-10-08 | 16 | 16 | `4a95f1cdd1` | CLOSE candidate: 16 unmerged commit(s), 13 days old, no PR. Owner to confirm |
| `claude/lucid-rubin-h8mfmr` | 2026-10-08 | 3 | 3 | `c5b37092cb` | CLOSE candidate: 3 unmerged commit(s), 13 days old, no PR. Owner to confirm |

## Branches fully merged into main (35)

| Branch | Last commit | Ahead of main | Unique patches | Tip SHA | Recommendation |
|---|---|---|---|---|---|
| `claude/vigilant-gates-uxg63p` | 2026-10-22 | 0 | 0 | `5ac9913379` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/doddy-sidekick-character-ofgjf5` | 2026-10-21 | 0 | 0 | `9ba394edaa` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/optimistic-pascal-rgmd47` | 2026-10-21 | 0 | 0 | `9ba394edaa` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/wonderful-newton-9mor30` | 2026-10-21 | 0 | 0 | `1f13a6c5cc` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/nice-shannon-9gxk6s` | 2026-10-21 | 0 | 0 | `8fb6914a9a` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/doddy-just-works` | 2026-10-21 | 0 | 0 | `2dfbeba718` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/fix-xcode-warnings` | 2026-10-20 | 0 | 0 | `d2bc32c69b` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/wizardly-ritchie-53ncqv` | 2026-10-20 | 0 | 0 | `a7babeaef4` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/optimistic-mendel-df84oe` | 2026-10-20 | 0 | 0 | `c8bbd76e44` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/friendly-volta-3recsi` | 2026-10-20 | 0 | 0 | `11620dca01` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/zen-noether-nykqbb` | 2026-10-20 | 0 | 0 | `f7e0193239` | KEEP for now: committed in the last 48 h, a session may be using it. |
| `claude/motion-mv7` | 2026-10-20 | 0 | 0 | `c2dfac776c` | DELETE: fully merged into main |
| `claude/calm-home-screen` | 2026-10-20 | 0 | 0 | `6014949a50` | DELETE: fully merged into main |
| `claude/motion-mv6` | 2026-10-20 | 0 | 0 | `e70bb5a7f4` | DELETE: fully merged into main |
| `claude/motion-mv5` | 2026-10-19 | 0 | 0 | `e93a340b2e` | DELETE: fully merged into main |
| `claude/motion-mv4` | 2026-10-19 | 0 | 0 | `f6e02b3909` | DELETE: fully merged into main |
| `claude/motion-mv3` | 2026-10-19 | 0 | 0 | `61a953d951` | DELETE: fully merged into main |
| `claude/happy-volta-trim-log` | 2026-10-19 | 0 | 0 | `ad35d08b7c` | DELETE: fully merged into main |
| `claude/happy-volta-redeploy` | 2026-10-19 | 0 | 0 | `b6d4deb4ea` | DELETE: fully merged into main |
| `claude/happy-volta-render-drift` | 2026-10-19 | 0 | 0 | `d9963a3235` | DELETE: fully merged into main |
| `claude/happy-volta-decisions` | 2026-10-19 | 0 | 0 | `e5b5b09e37` | DELETE: fully merged into main |
| `claude/happy-volta-9a11kw` | 2026-10-19 | 0 | 0 | `9712fd648b` | DELETE: fully merged into main |
| `claude/merge-train-status-19oct` | 2026-10-19 | 0 | 0 | `b6d6f9af01` | DELETE: fully merged into main |
| `claude/modest-pasteur-7jnwfd` | 2026-10-19 | 0 | 0 | `1d9c74b9e2` | DELETE: fully merged into main |
| `claude/motion-mv2` | 2026-10-19 | 0 | 0 | `0fd451e89c` | DELETE: fully merged into main |
| `claude/fervent-edison-3gnqpq` | 2026-10-19 | 0 | 0 | `8667cb0f50` | DELETE: fully merged into main |
| `claude/motion-mv1` | 2026-10-18 | 0 | 0 | `fd649a10b7` | DELETE: fully merged into main |
| `claude/laughing-darwin-hqxa63` | 2026-10-18 | 0 | 0 | `70f064f3c6` | DELETE: fully merged into main |
| `claude/dreamy-cannon-gc33dj` | 2026-10-18 | 0 | 0 | `fc3e16fe27` | DELETE: fully merged into main |
| `claude/motion-v2-plan` | 2026-10-18 | 0 | 0 | `44bbe2944f` | DELETE: fully merged into main |
| `claude/wizardly-knuth-ewbsm7` | 2026-10-15 | 0 | 0 | `a7bae0829f` | DELETE: fully merged into main |
| `claude/inspiring-rubin-1agiui` | 2026-10-14 | 0 | 0 | `98b5d7611d` | DELETE: fully merged into main |
| `claude/compassionate-pascal-6c9wo6` | 2026-10-14 | 0 | 0 | `a8801593e0` | DELETE: fully merged into main |
| `claude/hopeful-mccarthy-b6x1on` | 2026-10-14 | 0 | 0 | `6f510003fb` | DELETE: fully merged into main |
| `claude/jolly-bell-mlwnqb` | 2026-10-13 | 0 | 0 | `50267bb705` | DELETE: fully merged into main |

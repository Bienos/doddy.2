# Plans screens: describe the plans, buy on the website (ADR-585)

Owner, 22 Oct 2026: paid versions of Doddy are bought **on Doddy's website**, not through the App Store, "to avoid fees". The app gets screens that show what each plan includes and send the person to the website. They live **inside the app** (Settings and Studio), **not** on the intro or in the first conversation.

**Status: built as code and tests, not compiled in an app.** The pure logic (`DoddyCore/Plans.swift`) has 6 passing Linux tests. The SwiftUI screens (`DoddyApp/Features/Plans/PlansView.swift`) and the two entry rows are **not compiled** (no Xcode); the first Mac build is their first compile. Nothing here sells anything.

## What exists

| Piece | Where | What it does |
|---|---|---|
| `PlanTier`, `PlanCatalog`, `PlanOffer` | `Packages/DoddyCore/Sources/DoddyCore/Plans.swift` | Free, Plus, Pro; the owner's sketch of 2, 6 and 8 research briefs a month and simple, balanced, careful research (pinned by tests; **a sketch, not a decision**). Export, delete and backup are listed as never limited |
| `PlanLink` | same | Builds the website link from the build's address: only `https`, a host, no login in it; adds `plan`, `from=app` and `lang`; replaces any `plan`, `from` or `lang` already in the address; a bad language code is dropped. No address gives no link |
| `PlanStatus` | same | `unknown` or `known(tier)`. Always `unknown` until accounts exist: **no screen says "your plan is X"** |
| Plans screen | `PlansView` | The three plans as rows, an honest note that nothing is bought in the app, the "never behind a plan" footer, and a red note when the website address isn't set |
| Plan screen | `PlanDetailView` | What one plan includes; for Plus and Pro a "Get Plus/Pro on Doddy's website" link that opens the browser, with a footer saying what is sent; for Free, "nothing to buy" |
| Entry points | `SettingsView` (a "Plans" row above "About you"), `StudioView` ("More research briefs a month", last row) | Both push `PlansView`. `FirstHello`, the intro and onboarding are untouched |
| Website address | `Config/Doddy-Info.plist`, key `DoddyPlansURL` | **Empty in this build** (no domain decided), so no buy button shows and the screen says why |
| Polish | `l10n/pl.json` (24 new lines) | `build_strings_catalog.py --check` passes; the other languages stay English |

## What leaves the iPhone

Opening the link sends the browser to Doddy's website with only: which plan was looked at, that it came from the app, and the app's language. No account, device ID, memory or note (DOD-11). The screens say so in a footer. The website then sees whatever a browser normally sends it, which is the website's own privacy matter.

## Not built, and why (decisions or missing pieces)

1. **The website and checkout.** Nothing exists yet: no plans page, no payment provider, no price. Prices are deliberately **not in the app**; they live on the page.
2. **Accounts, and knowing the plan.** Doddy has no accounts. Without them the server cannot tie a web purchase to a person, so the app cannot show "Your plan" and Studio's `STUDIO_TIER` is one setting per server. Needs a sign-in the website and the app share, then a server answer like `GET /v1/plan`.
3. **Per-plan limits in the server** (monthly briefs per account, credits by length): not built; the daily cost cap exists.
4. **App Store rules: unverified, a real risk.** Apple restricts how an app points people to buy digital subscriptions elsewhere, and the rules differ by region (the first market is Poland, in the EU). **I have not checked Apple's current guidelines or any entitlement or disclosure the app may need before review, and nothing here claims the link is allowed.** The owner (or counsel) must read the current App Review Guidelines (3.1) and the EU external-link terms before submitting a build that contains the link. If the answer is "not allowed", remove the two entry rows and `PlansView`; nothing else depends on them.
5. **Plan names and numbers.** Free, Plus and Pro, and 2/6/8, are placeholders from the owner's sketch in this chat; `MONETIZATION_MODEL_V2.md` (10 Oct) uses other names (Best Mate, Crew, Pro) and a different structure. Reconcile before showing real people.
6. **V1_SCOPE says "no StoreKit and no paywall in the beta; the paywall decision comes at 1.0".** This ADR is that decision's direction for payments (web, not StoreKit), not a decision to charge in the beta.

## Tests and checks run

| Command | Result |
|---|---|
| `swift test --package-path Packages/DoddyCore … --filter PlansTests` (Swift 6.1.2, Linux) | 6 tests, 0 failures; the whole DoddyCore suite: 1,401 tests, 0 failures |
| `python3 -I tools/build_strings_catalog.py --check` | PASS (Polish 1,724 of 1,802) |
| `scripts/check_forbidden_capabilities.sh`, `python3 -I scripts/voice_agent_spec.py check` | PASS |

**Not run:** the SwiftUI views, any device or simulator, Apple's review, a real website.

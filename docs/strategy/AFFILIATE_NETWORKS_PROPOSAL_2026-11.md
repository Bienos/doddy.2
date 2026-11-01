# Affiliate networks: which to join, how Doddy proposes them, what can go wrong

Proposal, 1 Nov 2026. **Nothing here is built, applied for or signed.** It answers the owner's brief: use Admitad, Impact and similar networks; Temu, Shein and the like only as an optional "search further" for people who want them; think about the design and about how it could go wrong. Sources: the owner's research of 30 Oct (`docs/research/2026-10-30/`: report, programme master CSV, API comparison CSV), the 29 Oct research (`docs/research/2026-10-29/research_more_sources_and_affiliates.md`), and the code at `e0c755d` (ADR-612, ADR-666, ADR-668). Tags: [R] in the owner's research, [Repo] in earlier repo research, [Code] read in the code, [Memory] my recollection, **not checked**.

## 1. Verdict

- **Yes, but only in the forms below, and expect small money.** The owner's own model gives about 23 zł a month at 1,000 monthly users and about 2,300 zł at 100,000 (base case, every input an assumption) [R]. The value now is learning whether tracking survives the app, and a small income that does not bend what Doddy recommends.
- **Admitad is the network to start with; Impact is not.** Of the 322 programmes in the master CSV, Admitad has 13 Polish programmes (12 shops and Ceneo's click programme), all with deep links listed [R]. Impact has 5, and none is a Polish shop: Airalo (eSIM), Coursera, Logitech US, Walmart US, Skyscanner (technology partners excluded) [R]. For a Polish shopping assistant Impact adds nothing today; revisit it for travel later.
- **Only react, never push.** Doddy offers a partner link when the person asked to compare or buy. It never says "shop X has a promotion on what you usually buy": that is advertising built on remembered purchases, which the constitution's rules on dependency and sensitive inference argue against.
- **Best price stays first.** This is already enforced: the link is added after the picks and a test compares the answer with and without it [Code: `affiliate.ts`, `dealsPartnerOffers.test.ts`]. Every idea below keeps that.

## 2. The networks

| Network | Polish shops in the research | Fit | Notes |
|---|---|---|---|
| **Admitad** | x-kom, Decathlon, Carrefour, Castorama, Komputronik, Media Expert, Ceneo (CPC), Douglas, al.to, Acer, Baseus, Konesso, New Balance [R] | **Apply first** | Each shop approves you separately. Decathlon and Carrefour list "applications"; x-kom picks its publishers and bans price-comparison plugins; Media Expert limits traffic types [R]. Rates are mostly unknown until you are in the panel. |
| **Tradedoubler** | Allegro (0.21–3.55% by category, electronics 0.93%), RTV Euro AGD, Castorama, Empik [R, Repo] | **Apply first** | Allegro's listing allows apps, price comparison and deep links; its cookie says 24 h in one place and 30 days in another [R, Repo]. Euro forbids bots opening its links [R]. |
| **Awin** | Answear, MSI; Temu PL, CCC, Maxi Zoo, Douglas (Douglas is under Admitad in the CSV and Awin in the 29 Oct notes: check in the panel) [R, Repo] | Second | Refundable deposit [Repo]. Terms say materials "without modification" [Repo]. |
| **Ceneo, directly** | Ceneo | **Apply first** | About 0,35 zł per click-out, 90 days, private person or company, AI content must be labelled [Repo]. Pays per click, so it does not depend on a purchase guess. |
| **Impact** | none for Polish retail | Not now | See above. |
| TradeTracker | AliExpress [R] | Later | For the optional search-further list only. |
| webePartners | 275 listings, rates and app permission unknown for all [R] | Not now | Breadth without terms. Use it when a specific shop matters. |
| Link services (Sovrn, Skimlinks) | n/a | Backup | One contract wraps many shops, but Polish coverage is unverified and they keep a cut [R, Repo]. |

**The 35 "High" rows in the master CSV are the real shortlist.** The 322 count is mostly webePartners listings with no terms.

## 3. Where Doddy proposes a partner link

| # | Surface | Today | Trust risk | Proposal |
|---|---|---|---|---|
| S1 | "Buy at …" on a verified pick in Find me this | Built (ADR-612) | Low: the price is confirmed on the shop's page | Keep. Add rules as programmes are approved. |
| S2 | "Open in the shop" on a leaflet offer | Built (ADR-668) | Low, but only for shops that sell online what the leaflet shows | Keep; mark per surface (§4), never Lidl. |
| S3 | "Search further": Allegro, Ceneo | Built (ADR-666), server list of at most 4 | Low | Keep. |
| S4 | **My comparison shops**: the person adds Temu, AliExpress, Shein, Amazon.pl or x-kom to S3 in Settings | New | Low: the person chose it | Build after §6 gate B. The app sends shop **names** from a fixed list; templates stay on the server (a client-sent template would be an open redirect). |
| S5 | Voice | The tool reply tells the agent the list is in the app | Medium: a spoken partner offer is an "oral offer" (Amazon bans links in those) | No change. Voice never reads a link or a commission pitch. |
| S6 | Unprompted suggestions ("Decathlon has a sale") | none | **High** | **Do not build.** |

Temu, Shein and AliExpress: Doddy cannot read their prices, so they are only search links (S4), never picks. Temu's headline rate is a new-customer bounty [Repo]. Shein is not in the research: its programme, rate and network are unknown.

## 4. Design

1. **Rules with a lifetime.** Today a rule is `host → https template` and lives until someone edits the setting and redeploys [Code]. Add an object form, the old string form still working:
   `{"x-kom.pl": {"template": "https://…{sub}…{url}", "network": "admitad", "approved": "2026-11-20", "expires": "2027-05-20", "surfaces": ["pick", "offer"]}}`.
   After `expires` the rule is ignored, so a lapsed programme stops sending tracked links by itself. `approved` is the date of the written yes (§6 gate A). `surfaces` lets Carrefour be a pick but not a leaflet offer.
2. **A coarse sub-ID.** `{sub}` becomes the surface code (`pick`, `offer`, `further`), nothing else: no user, no device, no words. The network's report then says which surface earned, and the privacy page can say the link carries no personal data. The usual parameter names are `subid` (Admitad), `clickref` (Awin), `subId1` (Impact), `epi` (Tradedoubler) [Memory]; copy the real link from each network's generator.
3. **A visible switch.** Settings › Shopping › "Partner links" (default on, because the owner said yes in ADR-612). Off: every button opens the shop directly. Plus, on each partner button, a second action "Open without partner link". It costs a little commission and buys a lot of trust, and it is the way out when an ad blocker breaks the network's address.
4. **Clearer label.** Keep the sentence under the button (it is read before any tap). Add the short Polish label the report proposes, "Reklama · link afiliacyjny", on the button row. A lawyer should confirm the wording [R].
5. **No automatic anything.** A link opens only on a tap. A voice tool never opens one (RTV Euro and Allegro treat automatic opening as artificial traffic [R, Repo]).
6. **Fail soft in the server.** A bad rule today stops the whole messaging server at start [Code]. That is too harsh for a side feature: skip the bad rule, log `affiliateRulesSkipped`, and add a small script that parses the value before it is pasted into Render.
7. **Guard the invariant.** Add a check (like `scripts/check_forbidden_capabilities.sh`) that nothing in picking, ordering or ranking code imports the affiliate module. The existing "with and without" tests catch a change in output; this catches a change in intent.
8. **Measure by hand first.** Read each network's dashboard weekly and note clicks, credited sales and reversals per surface in a table. Build report ingestion only when volume justifies it.

## 5. How it can go wrong

| Risk | Why it matters | Mitigation | Detect |
|---|---|---|---|
| **A network or shop says the app or AI use is not allowed** | Commission is withheld or reversed, the account can be closed [R] | Gate A: no rule goes live before a written yes that names the iPhone app, the conversational flow and the voice. Apply per shop, with the text in §7. | Panel status; a rejection email |
| **Attribution is lost in the app** | The owner's model keeps 75% of purchases; the real number may be far lower. Safari, a shop's own app opening through a universal link, and cookies that last 24 hours (Allegro, x-kom) all leak. Tradedoubler suggests web over app redirects [R] | Gate B: one real cheap purchase per network, from the phone, and see it in the dashboard with the right sub-ID. Do not count on money before that. | Dashboard shows clicks but no sales |
| **The redirect lands on the wrong product** | A network redirect can drop a variant or size from the address, so the person sees a different price than Doddy quoted | Test one real address per shop by hand at sign-up; fall back to the plain link for any shop that fails | Complaint; manual check |
| **Ad blockers or Private Relay break the network's address** | The tap shows an error and the person blames Doddy | "Open without partner link"; the switch | Support reports |
| **Looks like an ad that moves recommendations** | Trust is Doddy's product | Ranking untouched and tested; a shop appears in a list because of fit, never because of a rule; the plain source link stays next to the partner button; no "recommended" next to a partner label | Review any change that touches `further.ts` or the pick code |
| **Hidden bias creeps in later** | A future feature "just prefers" partner shops | The import guard (§4.7); keep the owner's rule written in `doddy_rules.yaml` terms | CI |
| **A programme ends or its rate changes** | Links keep sending users through a dead tracker | `expires`; a monthly calendar check; a shared inbox for network emails | Dashboard; an email |
| **The "price comparison" label** | x-kom bans price-comparison plugins; Euro changes its rate; Kelkoo can forbid it [R, Repo] | Say what Doddy is in the application; accept a refusal; do not hide the use | Application answer |
| **Automatic link checks count as clicks** | A health check that calls the tracked link looks like fake traffic and pollutes the stats | Never fetch a tracked link from code. Check the shop's own host only. | Click spikes with no taps |
| **Money is stuck** | Payout minimum about 100 zł, a 2–4 month lag, refunds reverse commission [R, Repo]; at low volume you may never reach the minimum | Expect it; do not plan spending on it | Dashboard balance |
| **Who owns the account** | A network account usually cannot be handed from a person to a company later; Allegro direct needs a company with VAT; invoices and VAT differ [R] | Decide the publisher before the first application (§8) | n/a |
| **Digital goods and travel** | Apple treats software and eSIMs differently from physical goods (App Review 3.1.1 vs 3.1.3(e)) [R] | Keep Airalo, Coursera, Adobe and similar out of v1 | App Review |
| **Law and consent** | Hidden advertising rules (UOKiK), AI-content labels (Ceneo art. V.5), cookie rules when the network sets a cookie on the person's browser [R, Repo] | Label before the tap, no personal data in the link, name each network on the Terms and Privacy pages once signed (SHOPPING.md "Privacy"), ask a lawyer | Legal review |
| **Lidl-type exclusions** | A leaflet offer sold only in a physical shop must not carry a link that promotes it [Repo] | `surfaces`; never `lidl.pl` | Rule review |
| **Server setting typo** | Today it stops the whole server | §4.6 | Startup log `affiliateRules` count |

## 6. Order of work

- **Step 0, no code (the owner):** decide the publisher (§8). Apply to Admitad (x-kom, Decathlon, Carrefour, Castorama, Komputronik, Media Expert, Ceneo CPC), Tradedoubler (Allegro, RTV Euro AGD, Empik), Ceneo directly, then Awin. Use §7. Ask the seven questions in section 10 of the research.
- **Gate A, per shop:** a written yes for the iOS app, the AI flow and voice, saved with its date. Until then no rule goes live.
- **Step 1, code, small:** rule v2 with `expires`, `surfaces` and `{sub}`; fail-soft parse and its script; the Settings switch; "Open without partner link"; the label; the import guard; tests (TypeScript and DoddyCore). I can build this now; it needs no programme to be useful.
- **Gate B, per network:** one real cheap purchase from the phone is credited with the right sub-ID. Only then count the money.
- **Step 2:** S4, "My comparison shops" (Temu, AliExpress, Amazon.pl and so on), as search links.
- **Step 3, only with volume:** report ingestion; more networks.
- **Review at 90 days:** clicks, credited sales, rejections, complaints. If attribution never works from the app, stop wrapping links (they fall back to plain links) rather than keep a disclosure on something that earns nothing.

## 7. What to tell a network (draft for the application)

"Doddy is an iPhone voice and text assistant for people in Poland. When a person asks it to find or compare a product, it checks prices on shops' own pages and shows up to three options. A shop link opens only when the person taps it, in Safari. We would like to add your tracking link to the shop's own page after the options are chosen, so the order and the prices do not depend on the commission. Each link carries a surface code and no personal data. The link is labelled as an affiliate link before the tap, and the person can turn partner links off. No coupons, no search ads, no brand bidding, no automatic opening. Please confirm in writing that this iOS app, the conversational flow and spoken answers are an allowed traffic source, and tell us if price-comparison traffic is treated differently."

## 8. Decisions for the owner

1. **Publisher:** you as a person or a company with VAT. Hard to change later.
2. **Partner links on by default, with a visible switch** (recommended), or off until the person turns them on.
3. **Whether S4 (Temu, AliExpress, Shein, and so on as optional comparison shops) goes in**, and that the person adds them, not Doddy.
4. **Go for Step 1 in code** while the applications are pending.

## 9. What this document does not claim

No programme is approved, no link tracks, no network's link format was checked, no purchase was made, and nothing was run on a device. Every rate and cookie length is from the owner's research or earlier repo notes and must be rechecked when applying.

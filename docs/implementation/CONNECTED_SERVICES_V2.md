# Connected Services v2 — user-reviewed Vinted links and My services

**Status (11 Nov 2026): code proposed on a dependent PR; NOT yet shipped or physically tested.**
Depends on PR #329 (`feat/connected-services-v1-20261111`). This change adds **no automated Vinted scan, no private account integration, and no reservation action**.

## User experience

### Vinted: Share → Review → Compare
1. In Vinted, share an item URL with Doddy's existing `Save to Doddy` Share Sheet.
2. When the app receives the shared text, the existing capture screen offers **Review this Vinted listing** for a trusted HTTPS item URL.
3. A review sheet shows the original link, asks the person to type the item name and (optionally) its listed asking price, and displays verification cautions.
4. **Research comparable prices** prepares a text-only research task; the Vinted URL is deliberately removed. It opens the existing Tasks UI with the draft already filled in. The person must tap **Hand it to Doddy** and approve the exact task card before anything leaves the phone or runs.
5. It is a **generic research task**, not the verified-price Shopping Engine. The sheet must not promise an exact Vinted valuation, verified authenticity, true stock, seller safety, or a confirmed price. It does not use a Vinted catalogue API.

The capture note and research task remain separate: the user may save the shared link as a note through the existing capture process. There is no implicit note save or hidden request.

### Booksy and SimplyBook.me: Share → Save shortcut
1. Share a public HTTPS provider booking URL with Doddy.
2. The capture screen offers **Save this booking link in My services**.
3. The My services sheet pre-fills the link. The person supplies a label and taps **Add service provider**.
4. The bookmark is saved locally in `@AppStorage("connectedServices.bookingLinks")` as JSON; up to 24 unique validated links, with swipe-to-delete and a button that opens the original provider URL.
5. **Home › More › My services** also opens the saved list (behind the Shopping/Tasks release scope).
6. The provider handles availability, account sign-in, payment and reservation; Doddy cannot confirm an appointment.

## Code

- `Packages/DoddyCore/Sources/DoddyCore/ConnectedServices.swift`: trusted URL boundaries, validated bookmarks, JSON round trip, share URL extraction, text-only comparison draft.
- `DoddyApp/Features/Shopping/MyServicesView.swift`: local user-chosen service directory.
- `DoddyApp/Features/Shopping/VintedListingReviewView.swift`: transparent user-entered listing review and optional research hand-off.
- `DoddyApp/Features/Capture/CaptureView.swift`: contextual actions when a user-shared link is recognised.
- `DoddyApp/Features/Errands/ErrandsView.swift`: optional pre-filled words (no auto-send or auto-approval).
- `DoddyApp/Features/Home/HomeView.swift`: My services entry.
- `Packages/DoddyCore/Tests/DoddyCoreTests/ConnectedServicesTests.swift`: trusted/untrusted URL cases, JSON/dedup/max count, comparison task constraints.

## Security / privacy / constitution evidence

- **External writes:** none outside the phone; future booking requires an exact-payload user approval and provider confirmation.
- **Untrusted URLs:** only `https`, exact host or dot-bounded subdomain for Booksy and Vinted; a SimplyBook public booking page must be on a vendor subdomain. Username/password/port URL components disallowed. Nothing fetched automatically.
- **User data:** local bookmark labels/links stay on the iPhone. Research receives only the item description and asking price supplied by the user *after* task approval, never the Vinted URL.
- **Status:** opening a service page is not a booking; showing a Vinted link is not an authenticated seller or product.
- **Prompt risk:** product descriptions are user-entered and validated for size/control chars; external page text is never ingested into this stage.
- **Rollout:** no new secrets required for v2. Optional eBay keys remain governed by the stage-1 manifest and server environment.

## Verification checklist

- Review GitHub Actions **Core Swift tests / iOS build / messaging backend / Node tests** on the PR.
- On a signed iPhone build with App Groups, test Vinted Share Sheet → Capture → Review, including the opt-in research task; verify no request starts on opening.
- Share a Booksy and merchant SimplyBook URL; add a bookmark, reopen My services, quit/relaunch, open it in the provider, remove it. Confirm no claim of a completed booking.
- Check malicious/lookalike hosts, URL with credentials, unsupported sites, bad price/title, duplicate links, cancellation with unfinished notes.
- Check VoiceOver and Polish/English rendering on iOS. Xcode and device tests cannot be inferred from source alone.

## Next phase (not part of this PR)

- Business-approved SimplyBook.me read-only service and availability adapter with per-merchant token scope.
- Authorized Booksy partner APIs if granted (availability first, bookings later).
- Rich Vinted user-supplied images/description with on-device parsing/AI analysis and an opt-in competitor price comparison; never scrape Vinted's catalogue without permission.

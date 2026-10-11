# Round 8 report (2026-10-11, owner: "i want mac app too or even extension maybe as well")

Branch `claude/hopeful-fermat-1a63x0`, ADR-351 to ADR-354 (`DECISIONS.md`, Round 8). The owner chose a native macOS app, a Safari extension, a Share extension on the Mac and a menu bar quick note. **Nothing in this round has been compiled or run on a Mac.** There is no Xcode in this container and GitHub Actions still doesn't start jobs. Details: `MAC_APP_STATUS.md`.

## What was built (written, not run)
| Item | ADR | Where |
|---|---|---|
| Native Mac app: notes, lists, clips, search, export, Settings, ⌘N / ⌘1–3 | 351 | `DoddyMac/` |
| Clip inbox (App Group folder; max 20; 7 days; read-back) and the Mac Share extension | 352 | `Packages/DoddyCore/.../ClipInbox.swift`, `WebClip.swift`, `Shared/Mac/`, `DoddyMacShare/` |
| Safari web extension (MV3, `activeTab` + `scripting` + `nativeMessaging`, popup, native handler) | 353 | `DoddyMacSafari/` |
| Menu bar quick note; Mac in the capability guard; Polish (74 strings) | 354 | `DoddyMac/MenuBarQuickNote.swift`, `scripts/check_forbidden_capabilities.sh`, `l10n/pl.json` |
| Build wiring: three macOS targets, a `DoddyMac` scheme, `DODDY_MAC_APP_GROUP` | 351 | `project.yml`, `Config/DoddyMac*.{plist,entitlements}` |

## Tests actually run (Linux, this container)
`scripts/ci.sh --core-only`: **PASS for core-only scope; iOS app NOT verified.**
- DoddyCore: **912 tests, 0 failures** (Swift 6.2.1). Round 7 ended at 905; the 7 new are `ClipInboxTests`.
- Backend 188 of 188, gateway, voice-token, messaging and site tests unchanged and passing. Messaging DB tests **skipped** (no `TEST_DATABASE_URL`).
- Capability guard with the new Mac rules passes, **and each new rule was tried with a planted violation and fired**: `fetch` and a web address in the Safari JS, a `host_permissions` entry, a changed permission list, a network entitlement, `URLSession` in the Mac app, `import EventKit` in the Share extension.
- Polish catalog check passes (1395 of 1451 strings, 74 new).
- `swiftc -parse` passes on every Mac Swift file (12). The Mac files are not type-checked: Linux has no AppKit or SwiftUI.
- **NOT RUN:** the Mac, Share and Safari builds; any launch; Safari loading the extension; the Share menu; the menu bar item; VoiceOver; the App Group on a signed build; the Polish popup text in Safari (read by a native speaker).

## Manual checks still needed (a Mac)
- **Build and launch:** `make project`, build scheme `DoddyMac`; the app opens with an empty Notes list; no permission prompt appears.
- **Notes:** ⌘N, write, Save; quit and reopen: the note is still there. Correct it; change its type; delete it. A 5,001-character note is refused with the text kept.
- **Lists:** make a list, add, tick, clear ticked, rename, delete; adding the same item twice says it's already there.
- **Search:** words, `#tag`, `@Name`, the sidebar tag and people rows.
- **App Group:** Settings › Extensions says "Ready". If not, no clip can arrive (first-build guide).
- **Share extension:** Share › Doddy from Notes/Safari with text and with a link; "Ready in Doddy"; the 21st clip says the inbox is full; with the app closed, the clip is waiting next time it opens.
- **Safari extension:** enable it, click the button on a normal page with and without a selection, on a page Safari won't let it read, on a page with the selection in an iframe; Send; the clip appears under Clips; "Save as note" makes the note and clears the clip; a clip whose file can't be removed is hidden with a message.
- **Menu bar:** Save from the menu bar; the box clears; the main window shows the note; with the notes file unavailable it says so and keeps the text.
- **Polish:** switch macOS to Polish; read the Mac app, Share sheet and Safari popup.
- **VoiceOver:** walk the three columns, the sheet, the clip buttons and the quick note.

## Constitution evidence log
| Rule | Enforced by | Tests | Gap / claim to limit |
|---|---|---|---|
| Never claim memory saved without a verified storage operation | `MacStore.save/correct/setCategory` return only after the repository read back; the screens say "Saved." after that; a failure keeps the text. A clip leaves the inbox only after the note was saved (`saveClip`). `ClipInbox.add` reads the file back before "Ready in Doddy" / "sent". | `ClipInboxTests` (write/read-back, full, stale); repository behaviour is covered by the existing DoddyCore tests | The SwiftUI save path and the extensions are not run. `MacNoteDetail`'s "Saved." check compares the screen's text with the store after reload; not exercised. |
| "Unknown" is never success and never blindly retried | Share and Safari replies are one of sent / full / not_set_up / nothing / failed; only "sent" means kept. A failed send is not retried automatically; the person presses again. A failed clip removal after a saved note is shown, not hidden. | `ClipInboxTests` | Behaviour of macOS Share / Safari messaging unverified. |
| Tool, web, email and document content is data, not instructions | A page's title, address and selection, and Share-menu text, are cleaned, cut and stored as a clip's words; nothing parses or acts on them. Only `http`/`https` links are kept. | `ClipInboxTests` (cleaning, limits, only web links) | There is no model on the Mac; the iPhone agent never sees clips. |
| External writes need an exact payload and approval | No external write exists in this round: no network. The only writes are to the Mac's own notes file, on the person's Save. | Guard (no network entitlement, no `URLSession`, no fetch) tried with planted cases | |
| Privacy | The Mac app, Share extension and Safari extension have no network entitlement and no network code; the Safari manifest asks for activeTab, scripting and nativeMessaging only; nothing is read from a page before the click; Settings and the Privacy tab say the notes stay on this Mac and don't sync. | Guard (7 planted cases); `ClipInboxTests` | **Not "privacy guaranteed":** the guard checks the source; no one has looked at the signed app's real entitlements or traffic. Anyone using the Mac account can open the notes file and the clip folder; there is no lock and no encryption of the notes file beyond macOS's disk protection. |
| Character and wellbeing | The Mac app is plain: no Doddy voice, no streaks, no nudges, no art. | | The voice screen says talking isn't on the Mac yet; it does not pretend. |
| No proprietary assets or fonts; owner's Doddy art only | No art, icon or font added. The Mac app and Safari extension have **no icon** until the owner supplies one from the pack. | | Xcode will warn about the missing AppIcon. |

Do not say "implemented", "tested" or "privacy guaranteed" about the Mac app or the extensions. They are written and partly checked on Linux only.

## Security and privacy risks
- **A shared Mac account:** clips and notes are plain files readable by anyone who can open the account. The iPhone's Face ID lock and private notes have no Mac equivalent yet.
- **Clips hold whatever the person sent**, which can include a page's private text; they wait up to 7 days in the App Group folder before being dropped.
- **App Group mismatch:** a build signed without the group has no inbox (the extensions say so; nothing is lost, nothing arrives). A wrong group id on macOS 14 may fail silently; Settings › Extensions shows which.
- **Safari's "Always Allow":** if the person grants the extension access to all websites, `activeTab`/`scripting` still run only on the click, but the grant is wide. The popup says what is sent.
- **Unverified Safari messaging format** may make every send fail ("couldn't be handed to Doddy"); that is a usability risk, not a data one.

## Decisions needed from the owner
1. **Icon art** for the Mac app and the Safari toolbar from `DODDY-Numbered-Video-Assets-v01`.
2. **Sync** between the Mac and the iPhone (iCloud vs. encrypted export/import), or keep them separate.
3. **Voice on the Mac** as a new milestone.
4. **Register the Mac App Group** on the developer account (`group.<bundle id>.mac`) and decide the distribution route (direct or Mac App Store).
5. Still open from earlier: open the round 7 PR into `claude/loving-dirac-uuxoux`? Outlook Composio auth config; CarPlay entitlement request.

## Next recommended step
The first real build on a Mac (Way B in `FIRST_BUILD_GUIDE.md`; the Round 8 list starts with the App Group). Eight rounds of SwiftUI have not been compiled.

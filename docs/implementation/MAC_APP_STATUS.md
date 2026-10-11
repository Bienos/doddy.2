# Doddy for Mac: status (2026-10-11, ADR-351 to ADR-354)
Owner: "i want mac app too or even extension maybe as well". Chosen: a **native macOS app**, with a **Safari extension**, a **Share extension on the Mac** and a **menu bar quick note**.

**Nothing here has been compiled or run on a Mac.** There is no Xcode in the container. The Swift was parse-checked (`swiftc -parse`) on Linux, and the clip logic in `DoddyCore` is unit-tested; the SwiftUI, AppKit and Safari parts are not. Do not describe the Mac app or its extensions as built, working or tested.

## What it does (as written)
| Part | Where | What it does |
|---|---|---|
| Mac app | `DoddyMac/` | Notes (write, correct, refile, delete, search by words, `#tag`, `@person`), lists (make, tick, add, remove, clear ticked, rename, delete), Clips, plain-text export, Settings. Its own SQLite file. No sync, no network, no account, no voice. |
| Menu bar quick note | `DoddyMac/MenuBarQuickNote.swift` | A box and **Save** from the menu bar, a count of waiting clips, **Open Doddy**. |
| Share extension | `DoddyMacShare/` | "Save to Doddy" in the Mac Share menu: text and one web link become a clip. |
| Safari extension | `DoddyMacSafari/` | A toolbar popup that shows the page title, address and selected text, and on **Send to Doddy** leaves a clip. |
| Clip inbox | `DoddyCore` (`WebClip`, `ClipInbox`), `Shared/Mac/ClipInboxLocation.swift` | A folder in the Mac App Group. Max 20 waiting, 7 days, read-back on write, oldest first. A clip is not a note until **Save** in the Mac app. |

## Rules enforced in code
- A clip never becomes a note by itself; the Mac app saves it only on the person's Save, and removes it from the inbox only after the note was read back (`MacStore.saveClip`). A note that was saved but whose clip file couldn't be removed hides the clip for the session and says so.
- "Saved" (note, correction, quick note) is shown only after the store read the change back; on a failure the text stays in the box.
- No network of any kind in the Mac app or either extension: no network entitlement, no `URLSession`, and the Safari JS may not fetch, use WebSocket, inject markup or name a web address. The Safari manifest asks exactly for `activeTab`, `scripting`, `nativeMessaging`. `scripts/check_forbidden_capabilities.sh` fails the build otherwise (tried with seven planted violations).
- Page, tab and shared content is data: it is stored as note words and nothing acts on it.

## Tests actually run (Linux)
- `swift test` in `Packages/DoddyCore`: `ClipInboxTests` (7: queue order, full, stale and corrupt files dropped while other files are left alone, clip composition, only web links kept, message decoding limits) plus all earlier tests. Totals in the round report.
- `swiftc -parse` on every Mac Swift file; guard; Polish catalog check (1395 of 1451 strings).
- **NOT RUN:** the Mac, Share and Safari builds; any launch; Safari loading the extension; the Share menu; the menu bar item; VoiceOver; the App Group on a signed build.

## Not on the Mac (yet)
Talking to Doddy, reminders and notifications, calendar, contacts, photos and receipts, widgets, Face ID / private notes, Spotlight, tags beyond the sidebar, warranties, bills, diary, translator, Watch. No sync with the iPhone.

## Decisions needed from the owner
1. **App icon and Safari toolbar icon:** only your Doddy art may be used and none was supplied for the Mac. Which pose, and from the numbered pack?
2. **Sync with the iPhone:** the Mac keeps its own notes. Options: iCloud (CloudKit, needs a container and a design for conflicts), or an encrypted export/import like the iPhone backup. Neither is built.
3. **Voice on the Mac:** a new milestone (it sends audio to ElevenLabs; microphone permission; a different audio stack). Not started.
4. **App Group on macOS:** confirm the group id `group.<bundle id>.mac` is registered on your developer account (see the first-build guide).
5. **Distribution:** direct download or the Mac App Store. Safari extensions need the containing app signed either way.

## Next recommended step
The first real build on a Mac (`FIRST_BUILD_GUIDE.md`, Round 8 list), starting with the App Group check. Then use the Share menu and Safari on a real page, and look at what ends up in Clips.

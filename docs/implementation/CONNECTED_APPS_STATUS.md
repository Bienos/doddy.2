# Connected Apps and platform readiness audit

Audit date: 2026-10-16. Scope: current `codex/doddy-redesign-voice-timers` working branch.

## Connected Apps: what the code currently supports

| Surface | Implemented path | Important boundary |
|---|---|---|
| Apple Calendar, Reminders, Contacts, timers and alarms | Device-side integrations and permissions, initiated from the existing voice and Connections flows | iOS permission state is authoritative. No claim here that permission prompts or writes were exercised on a device in this environment. |
| Google Calendar | `ConnectedAppsView` plus the Doddy backend OAuth/read flow | Read-only in this integration. Needs a configured Doddy server and bound session token. The server can return explicitly labeled mock data; that is not a real Google connection. |
| Gmail, Google Drive, Notion, Todoist, Outlook | `OnlineAccountsView` receives the toolkit catalog from the Doddy server; individual tools start off and the server gates each run | Availability depends on server/provider configuration and real account grants. Writes remain behind app confirmation cards. The integration docs report mock-provider tests, not live provider verification. |
| Web search | Server-side toolkit with an explicit per-tool switch | Uses a configured paid Monid provider in live mode; mock responses are labeled. No live provider check was performed in this audit. |
| Messages | In-app reviewed draft handed to the native Messages composer | No Messages read/send API is used. The user must tap Send in Messages. |

The app does not infer a connected account from a local toggle: status is returned by the server. Demo mode is explicitly called out in the Google Calendar and Online Accounts screens. Do not describe an account as live without checking the server's returned mode and a real provider operation.

## Apple platform scope

- **Apple Watch:** companion code supports snapshots, reminders, lists, item ticks, adding a list item, and saving a note through the iPhone. It has no full voice conversation and no local database/network. A 15-second unanswered-response timeout was added in this branch so a missing WatchConnectivity callback cannot leave an action waiting indefinitely. No Xcode build, paired simulator run, or Watch device run was available for this audit.
- **“Hey Doddy”:** opt-in Picovoice listener/setup code exists. The bundled `DoddyApp/Resources/WakeWord/hey-doddy.ppn` file is absent; no AccessKey is committed (as required). A user's own file/key or correctly configured owner token service is required. iOS does not provide third-party always-on wake while the app is closed. The app must start listening in the foreground and may be stopped by iOS. The file picker now treats user cancellation as cancellation, not a read failure. No wake-word runtime test was possible.
- **iPad:** the iPhone target has a sidebar layout and device-specific behavior, but the status doc records no Xcode or iPad Simulator verification.
- **Mac:** a separate menu-bar/local-capture prototype exists. It has no iPhone sync, voice, or network and has never been compiled, per `docs/platforms/mac.md`.

## Checks and limits

- Source review only for this audit. This environment is Linux and has no Xcode or Apple simulators.
- The repo's prior `scripts/ci.sh --core-only` run covers core/server logic, not SwiftUI, WidgetKit, WatchKit, ActivityKit, App Intents, or device permission behavior.
- Connected Apps live OAuth/provider behavior, WatchConnectivity delivery, wake-word detection, Dynamic Island rendering, notifications, and AlarmKit behavior still require the documented Mac/device checks.

## Next verification order

1. On Mac, build the Watch-only and shipping iPhone-plus-Watch schemes; then test reachable/unreachable Watch requests, stale snapshots, list ticks/adds, note save, complications, and notification actions on a paired simulator/device.
2. Only after the owner supplies an approved iOS English `.ppn` and Picovoice setup, build and test opt-in wake listening, background interruptions, handoff to the voice session, battery behavior, and visible microphone/island states.
3. Check real Connected Apps mode and account status against the configured server; verify one read and confirmation-gated write per selected integration. Keep mock-mode results explicitly marked.
4. Build and inspect iPad, then Mac, using their platform docs before claiming those targets work.

# iPhone feature follow-up: timer, wake word, voice access, and notes sync

Checked 2026-10-16 against the current `work` checkout (`754e5d6a`) and the feature sources.

## Current implementation and remaining work

| Feature | Current code | Remaining work / gate |
|---|---|---|
| Kitchen timer Live Activity | General timers are scheduled as verified local notifications in `DeviceConnections.scheduleTimer`. The existing ActivityKit activity is for Focus sessions, breathing and read-aloud; alarm countdowns cover AlarmKit snooze only. | Add a separate timer activity, associate it with the confirmed timer notification, support more than one active timer, cancel/dismiss safely, and add widgets/tests. Build and test with Xcode before shipping. If Live Activities are disabled or unavailable, the local timer notification remains authoritative. |
| “Hey Doddy” | `WakeWordListener`, opt-in Settings, Live Activity/Lock Screen state, interruption handling and recovery are implemented. Audio detection is on-device. | `DoddyApp/Resources/WakeWord/hey-doddy.ppn` is absent. The owner must provide an iOS/English Picovoice keyword file and configure `PICOVOICE_ACCESS_KEY` on the owner-controlled voice-token service for one-tap setup. No key or model was created. Test background resume, audio interruptions, battery and false wakes on a physical iPhone. iOS does not allow a third-party wake word when its app has been fully stopped. |
| No-code voice access | The app has Sign in with Apple, a Keychain refresh session, separate provider consent, and requests short-lived provider credentials from `server/voice-token`. Server handlers and tests exist. | Configure the Apple sign-in capability and owner-held server variables listed in `server/voice-token/README.md`, deploy the code through the owner’s approved host, then test both providers on a device. This task did not create accounts, configure credentials, deploy services, or make provider calls. |
| Notes across devices | Notes remain local to the iPhone. CloudKit code exists for explicitly shared lists, not notes. | Design and implement private iCloud note sync with explicit opt-in, conflict/deletion propagation, retry, disable behavior, and exact privacy disclosure. The repository documents a paid Apple Developer team/iCloud container requirement for its CloudKit setup. No container or schema was configured. Do not report notes as synced. |

## Validation boundary

This cloud environment has no `xcodebuild`, `swift`, or Simulator. Repository instructions require native app changes to be built and verified with Xcode; therefore this pass did not add uncompiled ActivityKit or CloudKit code. The timer and notes-sync implementations remain outstanding native work. Existing voice and wake-word source code also remains unverified on the current build and physical device.

The capability guard was updated to recognize the existing Sign in with Apple networking and AuthenticationServices calls in the voice-auth files. A negative probe confirmed unrelated networking and authentication remain rejected.

## DODDY trust evidence

- **DOD-07 scoped user approval:** provider sharing remains separate from Apple sign-in and microphone access; sync must remain opt-in.
- **DOD-08 verified status:** a timer Live Activity must never be treated as proof that a timer notification was scheduled; the existing read-back receipt remains authoritative.
- **DOD-09 correction and recovery:** the future sync must preserve local notes through conflicts, offline failures and opt-out.
- **DOD-11 observable privacy:** wake-word audio stays on-device; note sync must disclose exactly which note fields leave the device.

No provider credentials, user content, Apple account, CloudKit container, Picovoice asset, or paid service was added or changed.

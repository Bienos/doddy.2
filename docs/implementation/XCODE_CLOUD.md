# TestFlight builds by themselves: Xcode Cloud (ADR-697)

Owner, 2 Nov 2026: "ok do 3", to "automatic TestFlight builds, so new versions reach your phone
without Xcode". After the one-time setup below, every merge into the default branch
(`main`; called `claude/loving-dirac-uuxoux` until 7 Nov 2026) becomes a TestFlight build on your iPhone. You don't need Xcode.

**Why Xcode Cloud and not GitHub Actions:** Apple's build service signs with your team's
certificates, kept by Apple. No signing key or App Store Connect key goes into GitHub, and this
repository is public. It's part of the Apple Developer Program: 25 compute hours a month. One
archive takes roughly 15 to 25 minutes, so that's about 60 to 100 builds a month, and only merges
start one.

**This is the one TestFlight path.** A manual GitHub workflow (ADR-694) was merged by mistake on
2 Nov 2026 and removed on 3 Nov at the owner's say-so; the branch `claude/testflight-workflow`
keeps it. Two paths would number their builds differently (the workflow's run number against Xcode
Cloud's own counter), and TestFlight refuses a build number it has already seen for a version.

**What this repository adds:** `ci_scripts/ci_post_clone.sh`. Xcode Cloud runs it on its Mac
after it downloads the code and before it builds. It does five things:
1. Generates `Doddy.xcodeproj` from `project.yml`, as `make project` does. The project isn't
   committed.
2. Gives the app and its three extensions (widgets, share, notification content) Xcode Cloud's
   build number. TestFlight needs a higher one for every upload, the same in all four.
3. Writes the commit the build is made from (`CI_COMMIT`) into the `DODDY_GIT_COMMIT` build
   setting. Info.plist carries it as `DoddyGitCommit`, and Settings › About shows its first seven
   characters next to the version, for example "0.1.0 (12, 8f3c2a1)". A build made anywhere else
   says `local` and shows only the version and build number (7 Nov 2026 audit).
4. Sets a team or a bundle ID, but only if the workflow names one (below).
5. Resolves the Swift packages. Xcode Cloud won't do that itself without `Package.resolved`, which
   a generated project doesn't have.

It never signs, uploads or reads a key. `scripts/test_xcode_cloud_post_clone.sh` checks it on
Linux, and `scripts/ci.sh` runs that test.

## Before the first build

1. **The TestFlight validation fixes are merged** (#174, ADR-693, 2 Nov 2026). App Store Connect
   rejected the first release archive without the Health "update" permission text; it's in
   `Config/Doddy-Info.plist` now, so Xcode Cloud's builds carry it.
2. **Export compliance is answered.** Owner, 2 Nov 2026: "Exempt: set it to NO".
   `Config/Doddy-Info.plist` now says `ITSAppUsesNonExemptEncryption` = `false` (go-live checklist
   B9). Doddy uses only standard encryption: HTTPS, and Apple's CryptoKit (AES-256-GCM) for its
   local backup file. So builds don't wait as "Missing Compliance". If Doddy ever adds its own or
   non-standard encryption, the key has to change.

3. **Push notifications are on the App ID** (ADR-701). Xcode Cloud's builds carry the push
   entitlements by default (`ci_post_clone.sh`, `DODDY_PUSH`), so developer.apple.com › Identifiers
   › the app's ID must have **Push Notifications** ticked, or signing fails with "doesn't include
   the aps-environment entitlement". Not ready yet? Set `DODDY_PUSH` = `0` in the workflow for now
   (no notification then reaches that build). The server side is already on: `doddy-messaging`
   started with `push: true` on 3 Nov 2026.

4. **Every bundle ID is registered on your Apple Developer account.** Xcode Cloud's automatic
   signing builds and signs the app, but it cannot register a bundle ID with Apple. Build 8
   (8 Nov 2026) archived fine and then all three exports failed with exit code 70 and
   `Automatic signing cannot register bundle identifier "com.bienos.doddy2.dev.notificationcontent"`:
   the notification content extension (ADR-786) was newer than the IDs registered by hand.
   Register each one at developer.apple.com › Certificates, Identifiers & Profiles › Identifiers
   › + › App IDs › App, with an **explicit** bundle ID:

   | Bundle ID | Capabilities |
   |---|---|
   | `com.bienos.doddy2.dev` (the app) | what `Config/Doddy-Push-AppGroup.entitlements` asks for: Sign in with Apple, Push Notifications, Time Sensitive Notifications, App Groups, HealthKit, HomeKit |
   | `com.bienos.doddy2.dev.widgets` | App Groups (`group.com.bienos.doddy2.dev`) |
   | `com.bienos.doddy2.dev.share` | App Groups (same group) |
   | `com.bienos.doddy2.dev.notificationcontent` | none (no App Group, no network, no permissions) |

   The App Group `group.com.bienos.doddy2.dev` must exist under Identifiers › App Groups. The same
   goes for any extension added later: register its ID before the next Xcode Cloud build. (On
   8 Nov 2026 the account had the app, widgets and share IDs, not the notification content one;
   what capabilities those three carry was not in the log.)

## The setup (once, on your Mac, about 15 minutes)

1. Get the default branch, run `make project`, and open `Doddy.xcodeproj` in Xcode.
2. **Create the workflow.** In Xcode: Integrate › Create Workflow (on older Xcode: Product › Xcode
   Cloud › Create Workflow), or the Report navigator › Cloud › Get Started. Pick the product
   **Doddy** (the app, not an extension).
3. **Give Xcode Cloud the repository.** Xcode opens App Store Connect to grant access to GitHub.
   Install the "Xcode Cloud" GitHub app for `Bienos/doddy.2` only.
4. **The app record.** Pick the App Store Connect app you uploaded to by hand. Its bundle ID must
   be the one the build uses: `com.bienos.doddy2.dev` unless you set `DODDY_BUNDLE_ID` (step 5).
   That record is **Doddy Beta** (ADR-812); the production app "Doddy" gets its own ID and record
   later, with its own workflow.
5. **Edit the workflow:**
   - **General:** name it "TestFlight on merge".
   - **Start condition:** Branch Changes, branch `main` (a workflow set up before 7 Nov 2026 names `claude/loving-dirac-uuxoux`: change it). Delete any "Pull
     Request Changes" condition: GitHub already checks pull requests, and it would use up the 25
     hours.
   - **Environment:** the latest released Xcode. Environment variables only if needed:
     `DODDY_TEAM_ID` = your team ID (developer.apple.com › Account › Membership) if the first
     build says signing needs a team; `DODDY_BUNDLE_ID` only if you choose another bundle ID than
     the app record's (checklist C1); `DODDY_PUSH` = `0` only to leave push out (see above).
   - **Actions:** one **Archive** action, platform iOS, scheme **Doddy**, distribution preparation
     **TestFlight (Internal Testing Only)**. Delete the default Build and Test actions: GitHub runs
     the tests.
   - **Post-actions:** **TestFlight Internal Testing**, with a group that has you in it.
6. **Build numbers.** App Store Connect › Apps › Doddy › Xcode Cloud › Settings › Build Number:
   set the next build number above any build you uploaded by hand. TestFlight refuses a number it
   has already seen.
7. **Start the first build** (Start Build in the workflow), then install TestFlight on the iPhone
   and accept the invitation.

## When it's set up

- Merge into the default branch → about 20 to 30 minutes later the build is in TestFlight
  (archive, then Apple's processing) → TestFlight on the iPhone offers the update.
- To build without a merge: Start Build in App Store Connect › Xcode Cloud.
- If a build fails, App Store Connect › Xcode Cloud › the build shows the log. The script's own
  lines start with `ci_post_clone:`.
- An **export** step that ends "Command exited with non-zero exit-code: 70" doesn't show its reason
  in that view. Download the build's Artifacts (the logs for the archive), open
  `app-store-export-archive-logs/xcodebuild-export-archive.log` (or the `ad-hoc` or `development`
  folder) and look for lines starting `error: exportArchive`. Build 8's said a bundle ID wasn't
  registered (step 4 above).

## Not checked

- Xcode Cloud hasn't run this script yet. The first build on your account is the check:
  - XcodeGen from Homebrew on Xcode Cloud's Mac;
  - whether signing needs `DODDY_TEAM_ID`;
  - the packages resolving there.
- Apple's guidance is that a script in `ci_scripts/` next to the project runs after the clone.
  Projects generated with XcodeGen commonly use it this way. The stand-in test covers the
  substitutions, not XcodeGen's real output on that Mac, and XcodeGen changing its output would
  stop the build with a `ci_post_clone:` line, never ship build 1.
- The LiveKit debug-symbols warning (ADR-693) doesn't block an upload. `scripts/copy_binary_dsyms.sh`
  is for archives made by hand; adding it to Xcode Cloud (`ci_scripts/ci_post_xcodebuild.sh`) is a
  later step, if the warning matters.

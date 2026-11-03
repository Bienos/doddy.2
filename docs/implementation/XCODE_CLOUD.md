# TestFlight builds by themselves: Xcode Cloud (ADR-697)

Owner, 2 Nov 2026: "ok do 3", to "automatic TestFlight builds, so new versions reach your phone
without Xcode". After the one-time setup below, every merge into the default branch
(`claude/loving-dirac-uuxoux`) becomes a TestFlight build on your iPhone. You don't need Xcode.

**Why Xcode Cloud and not GitHub Actions:** Apple's build service signs with your team's
certificates, kept by Apple. No signing key or App Store Connect key goes into GitHub, and this
repository is public. It's part of the Apple Developer Program: 25 compute hours a month. One
archive takes roughly 15 to 25 minutes, so that's about 60 to 100 builds a month, and only merges
start one.

**A second path exists: the manual GitHub workflow (ADR-694, `docs/implementation/TESTFLIGHT_WORKFLOW.md`).**
It was merged on 2 Nov 2026, after the owner chose Xcode Cloud only (#178 was closed, then merged
again by someone using the owner's account). It starts only by hand and needs an App Store Connect
admin key stored in GitHub. **Use one path.** Its build number is the workflow's run number and
Xcode Cloud's is its own counter, and TestFlight refuses a build number it has already seen for a
version, so mixing them can fail an upload. If both are ever used, set Xcode Cloud's next build
number above the last one the manual workflow uploaded (step 6 below).

**What this repository adds:** `ci_scripts/ci_post_clone.sh`. Xcode Cloud runs it on its Mac
after it downloads the code and before it builds. It does four things:
1. Generates `Doddy.xcodeproj` from `project.yml`, as `make project` does. The project isn't
   committed.
2. Gives the app and its two extensions Xcode Cloud's build number. TestFlight needs a higher one
   for every upload, the same in all three.
3. Sets a team or a bundle ID, but only if the workflow names one (below).
4. Resolves the Swift packages. Xcode Cloud won't do that itself without `Package.resolved`, which
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

## The setup (once, on your Mac, about 15 minutes)

1. Get the default branch, run `make project`, and open `Doddy.xcodeproj` in Xcode.
2. **Create the workflow.** In Xcode: Integrate › Create Workflow (on older Xcode: Product › Xcode
   Cloud › Create Workflow), or the Report navigator › Cloud › Get Started. Pick the product
   **Doddy** (the app, not an extension).
3. **Give Xcode Cloud the repository.** Xcode opens App Store Connect to grant access to GitHub.
   Install the "Xcode Cloud" GitHub app for `Bienos/doddy.2` only.
4. **The app record.** Pick the App Store Connect app you uploaded to by hand. Its bundle ID must
   be the one the build uses: `com.bienos.doddy2.dev` unless you set `DODDY_BUNDLE_ID` (step 5).
5. **Edit the workflow:**
   - **General:** name it "TestFlight on merge".
   - **Start condition:** Branch Changes, branch `claude/loving-dirac-uuxoux`. Delete any "Pull
     Request Changes" condition: GitHub already checks pull requests, and it would use up the 25
     hours.
   - **Environment:** the latest released Xcode. Environment variables only if needed:
     `DODDY_TEAM_ID` = your team ID (developer.apple.com › Account › Membership) if the first
     build says signing needs a team; `DODDY_BUNDLE_ID` only if you choose another bundle ID than
     the app record's (checklist C1).
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

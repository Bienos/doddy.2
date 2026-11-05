# TestFlight validation: what failed, what changed, what to do on the Mac

Status, 2 Nov 2026 (ADR-693). The first Release archive built, but App Store Connect validation failed. Nothing here was run with Xcode: the session was on Linux. **Do not upload until the steps below pass on your Mac.**

## 1. `NSHealthUpdateUsageDescription` missing (blocking) — fixed in code, not yet validated
- Doddy does use HealthKit, read only (`DoddyApp/Infrastructure/Health/HealthReader.swift`, sport mode). It asks through `requestAuthorization(toShare: [], read: …)`. Apple wants both purpose strings whenever that call is in the binary, even when nothing is written.
- Added to `Config/Doddy-Info.plist` with an honest text: Doddy never writes to Health. The read string (`NSHealthShareUsageDescription`) was already in `project.yml`.
- HealthKit was not removed. Removing it would mean cutting sport mode (ADR-620 to 626), which you did not ask for.
- The capability guard still forbids any write, and now also fails if either string disappears.

## 2. `LiveKitWebRTC.framework` dSYM warning (not blocking) — script added, not yet run on a real archive
- The vendor ships the symbols: release 150.7871.05 has `ios-arm64/dSYMs/LiveKitWebRTC.framework.dSYM`, and its UUID equals the framework's. The archive just doesn't contain them.
- Which WebRTC release **your** archive used is not recorded in the repository (the Xcode project is generated and not committed). `scripts/copy_binary_dsyms.sh` therefore compares UUIDs against your archive's real framework and copies only on a match.
- Run it after the archive and before the export or upload:
  ```
  xcodebuild archive … -archivePath build/Doddy.xcarchive -clonedSourcePackagesDirPath build/SourcePackages
  scripts/copy_binary_dsyms.sh build/Doddy.xcarchive build/SourcePackages
  ```
  (Without `-clonedSourcePackagesDirPath`, the folder is `~/Library/Developer/Xcode/DerivedData/<project>-…/SourcePackages`.) It prints `copied`, `present`, `skip` or `UNMATCHED` for each package framework.
- If it says `UNMATCHED`, the dSYM in the package is for another build of the framework, and the warning cannot be fixed from this side; it is a warning, and the upload still goes through. Voice does not depend on it.

## 3. Which bundle ID is in App Store Connect? — your check, nothing changed
The archive uses `com.bienos.doddy2.dev` (`DODDY_APP_BUNDLE_IDENTIFIER` in `project.yml`; ADR-023 calls it a development placeholder). Compare it with the bundle ID of the app record in App Store Connect (App Information → Bundle ID). A record's bundle ID cannot be changed after creation.
- **If they match:** nothing to do.
- **If you want a different shipping ID** (for example without `.dev`), these all follow the ID, and each must be changed together:
  1. Build setting `DODDY_APP_BUNDLE_IDENTIFIER` (the widgets, share extension, tests and the App Group `group.<id>` derive from it).
  2. App IDs at developer.apple.com for the app, `.widgets` and `.share`, with Sign in with Apple, Push Notifications, App Groups and HealthKit.
  3. `APPLE_BUNDLE_ID` on the voice-token server (Vercel) and `APNS_BUNDLE_ID` on both messaging services (Render).
  4. `CFBundleURLName` in `Config/Doddy-Info.plist` (cosmetic) and the `Logger` subsystem strings (cosmetic).
  A phone with the old ID installed keeps its data under the old ID; a new ID is a new app to iOS.

## Re-run on the Mac
```
make project
xcodebuild archive -project Doddy.xcodeproj -scheme Doddy -configuration Release \
  -archivePath build/Doddy.xcarchive -clonedSourcePackagesDirPath build/SourcePackages \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=<your team id> \
  DODDY_APP_ENTITLEMENTS=Config/Doddy-Push-AppGroup.entitlements
scripts/copy_binary_dsyms.sh build/Doddy.xcarchive build/SourcePackages
```
Then Validate App in Xcode's Organizer (Distribute App → App Store Connect → Validate). Upload only when validation shows no error. Report what it says, including any warning left.

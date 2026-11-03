# TestFlight workflow (ADR-694)

**Status, 2 Nov 2026: written and unit-tested on Linux against stand-ins for Xcode. Never run on a Mac, never run against App Store Connect. Nothing has been uploaded.** The first real run is the test; expect to fix something.

## What it does
`.github/workflows/testflight.yml` runs `scripts/testflight.sh` on a hosted Mac. **Only by hand** (Actions → TestFlight → Run workflow): nothing else starts it.

| `action` | Does | Uploads? |
|---|---|---|
| `validate` (default) | generates the project, archives Release, copies the binary packages' dSYMs (ADR-693), exports an `.ipa`, runs `xcrun altool --validate-app` | **No** |
| `upload` | the same archive, then exports with `destination: upload` | **Yes**, to App Store Connect; TestFlight then processes it |

Run `validate` first, read the log (`testflight-logs-validate-N`, kept a week), and run `upload` only when it shows no error. The run refuses a commit with no green "iOS build and tests" run unless `skip_ci_check` is ticked.

Build number: the workflow's run number, so every run is higher than the last. Version: `marketing_version`, or the project's `0.0.1`.

## One-time setup (yours; nothing here can be done from a Claude session)
1. **Merge this to the default branch.** GitHub lists a manually started workflow only when its file is on the default branch.
2. **An App Store Connect API key.** App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → **+**. Role **Admin**: Xcode's cloud signing needs it to create the distribution certificate and profiles. Download the `.p8` once. Note the **Key ID** and the **Issuer ID** at the top of the page.
3. **The app record.** App Store Connect → Apps → **+** → New App, with the bundle ID you are shipping (check it: `docs/implementation/TESTFLIGHT_VALIDATION.md`, section 3). Without a record there is nothing to upload to.
4. **The App ID's capabilities** at developer.apple.com → Identifiers: Sign in with Apple, Push Notifications, App Groups and HealthKit on the app's ID; the `.widgets` and `.share` IDs need App Groups. Automatic signing with an Admin key can register them, but check.
5. **GitHub → Settings → Environments → New environment `testflight`.** Add:
   - secrets `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY` (the whole text of the `.p8` file);
   - variable `APPLE_TEAM_ID` (Membership → Team ID; not a secret);
   - **Required reviewers**: yourself. Every run then waits for your approval before it can read the secrets.
   Keep the `.p8` in 1Password as well (`docs/security/SECRETS_1PASSWORD.md`); never paste it in a chat or commit it.

## What can go wrong
- **Signing fails** (no profile, no certificate): the key's role is below Admin, or an App ID lacks a capability. The error is in `archive.log` or `export.log`.
- **"Build number already used"**: another upload for this version has a higher number (for example one made from your Mac). Run again; the run number only goes up.
- **altool refuses the key**: altool reads the `.p8` from a folder the script sets (`API_PRIVATE_KEYS_DIR`); if Apple changed altool, validate in Xcode's Organizer instead and tell me what the log said.
- **Hosted Mac minutes:** the repository is public, so hosted runners cost nothing (ADR-543). Each run takes roughly the build time of the Mac CI job.
- **Validation passes here but fails in review:** validation checks the package, not Apple's review.

## What this does not do
No external TestFlight groups, no release notes, no App Store submission, no change to the app's code or signing settings in the repository. Nothing in the repository holds a certificate, a profile or a key.

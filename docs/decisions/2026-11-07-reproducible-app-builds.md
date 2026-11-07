# App builds use pinned package versions, CI compiles Release, and the privacy manifest declares every required-reason API

- **Date:** 2026-11-07
- **Decided by:** owner, 7 Nov 2026: "do all", for PR 3 of the engineering audit (`docs/engineering/AUDIT_2026-11-07.md`)
- **Status:** applied in this pull request; the pins themselves land in a second commit, after this pull request's first hosted run produces them

## Why
- **No pinned versions.** The app had no committed `Package.resolved`, and `project.yml` said LiveKit `from: 2.10.0`; on 7 Nov CI resolved 2.19.0. Every CI run and every Xcode Cloud archive could build different dependency versions. Xcode Cloud's first real runs failed on package resolution (draft #200).
- **No Release compile before Xcode Cloud.** CI compiled only a Debug simulator build, so the first Release compile was Xcode Cloud's archive.
- **Incomplete privacy manifest.** It declared only UserDefaults, while the app reads the system uptime (`AgentVoiceMeter`, `DoddyDirector`, `HomeView`), file dates (`RecordingFiles`, `PresentationFiles`) and free disk space (`RecordingFiles`). App Store Connect flags or refuses such uploads (ITMS-91053).

## Decision
1. LiveKit is `exactVersion: 2.19.0`. `Config/Package.resolved` pins every package the app resolves.
   - `scripts/install_package_resolved.sh` installs it into the generated project; `make project` and `make project-iphone` use it, and so does `scripts/ci.sh`. `ci_scripts/ci_post_clone.sh` does the same in its own lines.
   - CI fails when resolution changes the pins, and keeps what it resolved as an artifact.
   - `make update-packages` moves the pins on a Mac.
2. Pushes to `main` compile Release for a generic iOS device, unsigned (`DODDY_RELEASE_BUILD=1`).
3. The manifest declares System Boot Time `35F9.1`, File Timestamp `C617.1` and Disk Space `E174.1`. `scripts/check_privacy_manifest.sh`, tested in the `checks` group, fails when the app's code uses a required-reason API whose category the manifest doesn't declare.

## Consequences
- GitHub CI and TestFlight build the same versions.
- A dependency update becomes a deliberate pull request that changes `Config/Package.resolved`, either by Dependabot or by `make update-packages`.
- A push to `main` takes a few minutes longer.
- Not covered: Xcode Cloud's "only use versions from the resolved file" setting and its first archive with the pins. Draft #200 (another session's) changes the same script; it should be rebased on this one, and the owner's next Xcode Cloud run is the check. The widget and share extensions use none of these APIs today; if one starts to, it needs its own manifest.

## Evidence
- `scripts/test_check_privacy_manifest.sh` passes. The check fails on the old manifest, with all three categories missing.
- `scripts/test_xcode_cloud_post_clone.sh` passes, including the new pins cases.
- A dry run of `scripts/ci.sh --only ios` with stand-in Xcode tools covered three cases: no pins (skipped, file kept), pins equal (pass) and pins changed (fail). The Release step ran only when asked.
- Not run: a real Xcode build or archive.

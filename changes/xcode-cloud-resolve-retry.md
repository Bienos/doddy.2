# Xcode Cloud: retry Swift package resolution

Build 25 (commit 8f0f5ab, 8 Nov 2026) stopped in `ci_post_clone.sh` because GitHub answered 504 when
Xcode downloaded LiveKit's binary frameworks (`RustLiveKitFFI`, `LiveKitWebRTC`). No app was built.

`ci_scripts/ci_post_clone.sh` now runs `xcodebuild -resolvePackageDependencies` up to four times,
waiting 20 s, 40 s and 60 s between tries (`DODDY_RESOLVE_ATTEMPTS` changes the count). A resolution
that still fails after the last try stops the build as before.

Tests: `bash scripts/test_xcode_cloud_post_clone.sh` passes; the retry loop was run on Linux with a
stand-in `xcodebuild` (fails twice then succeeds: build continues; always fails: stops after 4 tries).
Not run on Xcode Cloud yet.

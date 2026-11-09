# Xcode Cloud: retry Swift package resolution

Builds 25 and 26 (commits 8f0f5ab and 2efae64) stopped in `ci_post_clone.sh` because GitHub answered 504 when
Xcode downloaded LiveKit's binary frameworks (`RustLiveKitFFI`, `LiveKitWebRTC`). No app was built.

`ci_scripts/ci_post_clone.sh` now runs `xcodebuild -resolvePackageDependencies` up to six times,
waiting 30, 60, 90, 120 and 150 s between tries (about 7.5 minutes; GitHub's 504s on 9 Nov came and went for hours) (`DODDY_RESOLVE_ATTEMPTS` changes the count). A resolution
that still fails after the last try stops the build as before.

Tests: `bash scripts/test_xcode_cloud_post_clone.sh` passes; the retry loop was run on Linux with a
stand-in `xcodebuild` (fails four times then succeeds: build continues; always fails: stops after 6 tries).
Not run on Xcode Cloud yet.

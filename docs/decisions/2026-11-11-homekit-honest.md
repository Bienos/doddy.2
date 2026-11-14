# HomeKit says at once when this build can't use it

Date: 2026-11-11. Owner: "Tak popraw HomeKit".

**Problem.** A build without the HomeKit entitlement (a free Apple team can't sign one) never gets a prompt or an answer from iOS. `HomeKitClient.request()` waited up to a minute and then reported "not determined".

**Decision.** `HomeKitEntitlement.isMissing(profile:)` (DoddyCore) reads the build's embedded provisioning profile text. A profile without `com.apple.developer.homekit` means the build can't use HomeKit; no profile (App Store, TestFlight) means nothing says it can't. `HomeKitClient.request()` returns `.denied` at once, and `control_home` answers `VoiceToolReply.homeUnavailable` so Doddy tells the user in one sentence.

**Limits.** SwiftUI/Swift app files not compiled here (no Xcode); the hosted Mac job is the first compile. Not run on a device.

# Which UI test classes run in which hosted Mac job (ADR-687). Sourced by scripts/ci.sh and
# scripts/check_ui_test_shards.sh; defines no behaviour of its own.
#
# The UI tests take about 40 minutes on one simulator, and two simulators on one hosted Mac were
# slower and flaky (ADR-680), so the hosted run uses one Mac per part, each with one simulator:
#   unit   the Swift package tests and the unit tests (no UI tests)
#   ui-a   the classes in UI_SHARD_A
#   ui-b   the classes in UI_SHARD_B
#   ui-c   every other class in DoddyUITests (a class added later lands here, so it always runs)
# The lists balance measured times (run 41509605799, one simulator, seconds): A 670, B 702, C 744.
# Re-balance them here when a class gets much slower or faster. A name that matches no class in
# DoddyUITests fails scripts/check_ui_test_shards.sh, so a typo can't silently drop a test.
#
# Order matters too: xcodebuild runs the classes of a part in alphabetical order, and the classes
# that drive the real Live Activity in SpringBoard (a cold widget-extension launch) fail as the first
# test on a freshly booted Mac. MemoryBaselineTests.testNativeIslandOfflineFixtureCanStartMuteAndEnd
# failed twice there (PR #172, run 41527213219 attempts 1 and 2) and IslandPolishTests.
# testTheNativeIslandSpeaksPolish once (run 41601274305, attempt 3); both pass once other tests
# have run first, as on the single-simulator run. So no part may start with a class in
# UI_SPRINGBOARD_CLASSES, and scripts/check_ui_test_shards.sh finds every DoddyUITests class that
# uses SpringBoard and fails if it is missing from that list.
UI_SPRINGBOARD_CLASSES="IslandPolishTests MemoryBaselineTests"
UI_SHARD_A="LaunchSmokeTests LegalAcceptanceUITests MemoryBaselineTests MotionBehaviourUITests"
UI_SHARD_B="MemoryJourneyTests MotionHopTests PolishSmokeTests WelcomeUITests"
#
# Warm-up (ADR-687): the cold-start failures were not only the SpringBoard tests. On a freshly booted
# Mac the first tests of a part can be slow or fail while the simulator, SpringBoard and the app's first
# launch settle (run 41619070789: LaunchSmokeTests.testFirstLaunchOpeningCanBeSkippedAndNeverStartsVoice
# took 204 s and failed as the first test of ui-a; ui-a failed the same way in the run before). So each UI
# part first runs this one quick test on its own, in a separate xcodebuild run whose result is ignored,
# and then runs its real tests on a settled simulator. Every real test still runs and must pass; the
# warm-up only absorbs the cold start. It must name a real, quick test (the shard check verifies it exists).
UI_WARMUP_TEST="LaunchSmokeTests/testOpeningOffShowsHomeStraightAway"

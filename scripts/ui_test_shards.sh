# Which UI test classes run in which hosted Mac job (ADR-687). Sourced by scripts/ci.sh and
# scripts/check_ui_test_shards.sh; defines no behaviour of its own.
#
# The UI tests take about 40 minutes on one simulator, and two simulators on one hosted Mac were
# slower and flaky (ADR-680), so the hosted run uses one Mac per part, each with one simulator:
#   unit   the Swift package tests and the unit tests (no UI tests)
#   ui-a   the classes in UI_SHARD_A
#   ui-b   the classes in UI_SHARD_B
#   ui-c   every other class in DoddyUITests (a class added later lands here, so it always runs)
# The lists balance measured times (run 41509605799, one simulator, seconds): A 697, B 702, C 717.
# Re-balance them here when a class gets much slower or faster. A name that matches no class in
# DoddyUITests fails scripts/check_ui_test_shards.sh, so a typo can't silently drop a test.
#
# Order matters too: xcodebuild runs the classes of a part in alphabetical order, and
# MemoryBaselineTests.testNativeIslandOfflineFixtureCanStartMuteAndEnd waits for the real Live
# Activity to render in SpringBoard (a cold widget-extension launch). As the first test on a freshly
# booted Mac it failed twice (PR #172, runs 41527213219 attempts 1 and 2); it passes once other tests
# have run first, as on the single-simulator run. So MemoryBaselineTests is in ui-a, after
# IslandPolishTests, LaunchSmokeTests and LegalAcceptanceUITests (about 9 minutes of tests), and no
# part may start with it.
UI_SHARD_A="IslandPolishTests LaunchSmokeTests LegalAcceptanceUITests MemoryBaselineTests MotionBehaviourUITests"
UI_SHARD_B="MemoryJourneyTests MotionHopTests PolishSmokeTests WelcomeUITests"

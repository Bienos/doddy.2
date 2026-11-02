# Which UI test classes run in which hosted Mac job (ADR-687). Sourced by scripts/ci.sh and
# scripts/check_ui_test_shards.sh; defines no behaviour of its own.
#
# The UI tests take about 40 minutes on one simulator, and two simulators on one hosted Mac were
# slower and flaky (ADR-680), so the hosted run uses one Mac per part, each with one simulator:
#   unit   the Swift package tests and the unit tests (no UI tests)
#   ui-a   the classes in UI_SHARD_A
#   ui-b   the classes in UI_SHARD_B
#   ui-c   every other class in DoddyUITests (a class added later lands here, so it always runs)
# The lists balance measured times (run 41509605799, one simulator, seconds): A 672, B 727, C 717.
# Re-balance them here when a class gets much slower or faster. A name that matches no class in
# DoddyUITests fails scripts/check_ui_test_shards.sh, so a typo can't silently drop a test.
UI_SHARD_A="LaunchSmokeTests WelcomeUITests LegalAcceptanceUITests PolishSmokeTests IslandPolishTests MotionBehaviourUITests"
UI_SHARD_B="MemoryJourneyTests MotionHopTests MemoryBaselineTests"

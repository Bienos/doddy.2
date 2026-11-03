#!/usr/bin/env bash
# Tests ci_scripts/ci_post_clone.sh (ADR-697) without Xcode: a stand-in project.pbxproj with the
# lines XcodeGen writes for project.yml (three targets, so each setting appears three times), the
# generator and package resolution switched off, and each environment variable checked for what it
# changes and what it refuses.
set -uo pipefail
cd "$(dirname "$0")/.."
script=$PWD/ci_scripts/ci_post_clone.sh
[ -x "$script" ] || { echo "FAIL: $script is missing or not executable (Xcode Cloud skips it)"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

fresh() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo/Doddy.xcodeproj" "$work/repo/Config"
  : > "$work/repo/Config/Doddy-Push-AppGroup.entitlements"
  local block='				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				DODDY_APP_BUNDLE_IDENTIFIER = com.bienos.doddy2.dev;
				DODDY_APP_ENTITLEMENTS = Config/Doddy-AppGroup.entitlements;
				MARKETING_VERSION = 0.0.1;'
  printf '%s\n%s\n%s\n' "$block" "$block" "$block" > "$work/repo/Doddy.xcodeproj/project.pbxproj"
}
run() {  # env assignments..., then runs the script against the stand-in repository
  env -i PATH="$PATH" CI_PRIMARY_REPOSITORY_PATH="$work/repo" DODDY_SKIP_XCODEGEN=1 DODDY_SKIP_RESOLVE=1 \
    "$@" sh "$script" > "$work/out" 2>&1
}
count() { grep -cF "$1" "$work/repo/Doddy.xcodeproj/project.pbxproj"; }

# Nothing set: nothing changes.
fresh; run
[ $? -eq 0 ] || fail "with no variables it should succeed"
[ "$(count 'CURRENT_PROJECT_VERSION = 1;')" = 3 ] || fail "with no build number the project keeps build 1"

# Xcode Cloud's build number reaches all three targets.
fresh; run CI_BUILD_NUMBER=42
[ $? -eq 0 ] || fail "build number 42 should succeed: $(cat "$work/out")"
[ "$(count 'CURRENT_PROJECT_VERSION = 42;')" = 3 ] || fail "the app and both extensions get build 42"
[ "$(count 'CURRENT_PROJECT_VERSION = 1;')" = 0 ] || fail "no target keeps build 1"
[ "$(count 'MARKETING_VERSION = 0.0.1;')" = 3 ] || fail "the version itself is untouched"

# A team and a bundle ID, when the workflow names them.
fresh; run CI_BUILD_NUMBER=7 DODDY_TEAM_ID=ABCDE12345 DODDY_BUNDLE_ID=com.bienos.doddy
[ $? -eq 0 ] || fail "team and bundle ID should succeed: $(cat "$work/out")"
[ "$(count 'DEVELOPMENT_TEAM = ABCDE12345;')" = 3 ] || fail "the team reaches all three targets"
[ "$(count 'DODDY_APP_BUNDLE_IDENTIFIER = com.bienos.doddy;')" = 3 ] || fail "the bundle ID reaches all three targets"
[ "$(count 'com.bienos.doddy2.dev')" = 0 ] || fail "the placeholder bundle ID is gone"

# Push notifications (ADR-701): on unless the workflow says DODDY_PUSH=0.
fresh; run
[ "$(count 'DODDY_APP_ENTITLEMENTS = Config/Doddy-Push-AppGroup.entitlements;')" = 3 ] || fail "by default every target gets the push entitlements"
[ "$(count 'Doddy-AppGroup.entitlements')" = 0 ] || fail "and none keeps the entitlements without push"
fresh; run DODDY_PUSH=1
[ "$(count 'Doddy-Push-AppGroup.entitlements')" = 3 ] || fail "DODDY_PUSH=1 is the same as the default"
fresh; run DODDY_PUSH=0
[ $? -eq 0 ] || fail "DODDY_PUSH=0 should succeed: $(cat "$work/out")"
[ "$(count 'DODDY_APP_ENTITLEMENTS = Config/Doddy-AppGroup.entitlements;')" = 3 ] || fail "DODDY_PUSH=0 keeps the entitlements without push"
fresh; run DODDY_PUSH=no
[ "$(count 'Doddy-Push-AppGroup.entitlements')" = 3 ] || fail "only the exact value 0 turns push off, so a typo can't ship a build without it"
fresh; rm "$work/repo/Config/Doddy-Push-AppGroup.entitlements"; run
[ $? -ne 0 ] || fail "with the push entitlements file missing the build must stop"
grep -q "Doddy-Push-AppGroup.entitlements is missing" "$work/out" || fail "and say which file"
fresh; sed 's|DODDY_APP_ENTITLEMENTS = Config/Doddy-AppGroup.entitlements;|DODDY_APP_ENTITLEMENTS = "";|' "$work/repo/Doddy.xcodeproj/project.pbxproj" > "$work/p" \
  && mv "$work/p" "$work/repo/Doddy.xcodeproj/project.pbxproj"
run
[ $? -ne 0 ] || fail "when the entitlements line isn't found the build must stop, not ship without push"
grep -q "couldn't set push notifications" "$work/out" || fail "and say what it couldn't set"

# Refusals: a build number, team or bundle ID that isn't one stops the build.
fresh; run CI_BUILD_NUMBER=4a
[ $? -ne 0 ] || fail "a build number with a letter must stop the build"
fresh; run DODDY_TEAM_ID='abc; rm -rf /'
[ $? -ne 0 ] || fail "a team ID with other characters must stop the build"
[ "$(count 'DEVELOPMENT_TEAM = "";')" = 3 ] || fail "a refused team ID changes nothing"
fresh; run DODDY_BUNDLE_ID='com.x|y'
[ $? -ne 0 ] || fail "a bundle ID with | must stop the build"

# XcodeGen's output changed (no build 1 to replace): stop, don't ship build 1.
fresh; sed 's/CURRENT_PROJECT_VERSION = 1;/CURRENT_PROJECT_VERSION = "1";/' "$work/repo/Doddy.xcodeproj/project.pbxproj" > "$work/p" \
  && mv "$work/p" "$work/repo/Doddy.xcodeproj/project.pbxproj"
run CI_BUILD_NUMBER=9
[ $? -ne 0 ] || fail "when the build number line isn't found the build must stop"
grep -q "couldn't set build number" "$work/out" || fail "and say what it couldn't set"

# No generated project at all.
rm -rf "$work/repo"; mkdir -p "$work/repo"; run
[ $? -ne 0 ] || fail "with no Doddy.xcodeproj the build must stop"

if [ "$failures" -ne 0 ]; then echo "FAIL: $failures check(s)"; exit 1; fi
echo "PASS: ci_post_clone.sh sets the build number, team, bundle ID and push entitlements and refuses bad values"

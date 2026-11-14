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
				DODDY_APP_ENTITLEMENTS = "Config/Doddy-AppGroup.entitlements";
				DODDY_GIT_COMMIT = local;
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
[ "$(count 'DODDY_APP_ENTITLEMENTS = "Config/Doddy-Push-AppGroup.entitlements";')" = 3 ] || fail "by default every target gets the push entitlements, quotes kept (XcodeGen quotes a path with a slash)"
[ "$(count 'Doddy-AppGroup.entitlements')" = 0 ] || fail "and none keeps the entitlements without push"
fresh; run DODDY_PUSH=1
[ "$(count 'Doddy-Push-AppGroup.entitlements')" = 3 ] || fail "DODDY_PUSH=1 is the same as the default"
fresh; run DODDY_PUSH=0
[ $? -eq 0 ] || fail "DODDY_PUSH=0 should succeed: $(cat "$work/out")"
[ "$(count 'DODDY_APP_ENTITLEMENTS = "Config/Doddy-AppGroup.entitlements";')" = 3 ] || fail "DODDY_PUSH=0 keeps the entitlements without push"
# The same when a future XcodeGen writes the path without quotes.
fresh; sed 's|"Config/Doddy-AppGroup.entitlements"|Config/Doddy-AppGroup.entitlements|' "$work/repo/Doddy.xcodeproj/project.pbxproj" > "$work/p" \
  && mv "$work/p" "$work/repo/Doddy.xcodeproj/project.pbxproj"
run
[ $? -eq 0 ] || fail "an unquoted entitlements path should work too: $(cat "$work/out")"
[ "$(count 'DODDY_APP_ENTITLEMENTS = Config/Doddy-Push-AppGroup.entitlements;')" = 3 ] || fail "and be replaced without adding quotes"
# And a quoted bundle ID.
fresh; sed 's|= com.bienos.doddy2.dev;|= "com.bienos.doddy2.dev";|' "$work/repo/Doddy.xcodeproj/project.pbxproj" > "$work/p" \
  && mv "$work/p" "$work/repo/Doddy.xcodeproj/project.pbxproj"
run DODDY_BUNDLE_ID=com.bienos.doddy
[ $? -eq 0 ] || fail "a quoted bundle ID should work too: $(cat "$work/out")"
[ "$(count 'DODDY_APP_BUNDLE_IDENTIFIER = "com.bienos.doddy";')" = 3 ] || fail "and keep its quotes"
fresh; run DODDY_PUSH=no
[ "$(count 'Doddy-Push-AppGroup.entitlements')" = 3 ] || fail "only the exact value 0 turns push off, so a typo can't ship a build without it"
fresh; rm "$work/repo/Config/Doddy-Push-AppGroup.entitlements"; run
[ $? -ne 0 ] || fail "with the push entitlements file missing the build must stop"
grep -q "Doddy-Push-AppGroup.entitlements is missing" "$work/out" || fail "and say which file"
fresh; sed 's|DODDY_APP_ENTITLEMENTS = "Config/Doddy-AppGroup.entitlements";|DODDY_APP_ENTITLEMENTS = "";|' "$work/repo/Doddy.xcodeproj/project.pbxproj" > "$work/p" \
  && mv "$work/p" "$work/repo/Doddy.xcodeproj/project.pbxproj"
run
[ $? -ne 0 ] || fail "when the entitlements line isn't found the build must stop, not ship without push"
grep -q "couldn't set push notifications" "$work/out" || fail "and say what it couldn't set"

# The commit (7 Nov 2026 audit): Xcode Cloud's CI_COMMIT replaces `local`; without it, and outside a
# repository (this stand-in), `local` stays.
fresh; run
[ "$(count 'DODDY_GIT_COMMIT = local;')" = 3 ] || fail "with no CI_COMMIT and no repository the project keeps 'local'"
fresh; run CI_COMMIT=8f3c2a1d9b7e6f5a4c3b2a1908f7e6d5c4b3a291
[ $? -eq 0 ] || fail "a 40-character commit should succeed: $(cat "$work/out")"
[ "$(count 'DODDY_GIT_COMMIT = 8f3c2a1d9b7e6f5a4c3b2a1908f7e6d5c4b3a291;')" = 3 ] || fail "the commit reaches every target"
[ "$(count 'DODDY_GIT_COMMIT = local;')" = 0 ] || fail "and no target keeps 'local'"
grep -q "commit 8f3c2a1 set" "$work/out" || fail "and the log names its short form"
fresh; run CI_COMMIT='8f3c2a1; rm -rf /'
[ $? -ne 0 ] || fail "a commit with other characters must stop the build"
[ "$(count 'DODDY_GIT_COMMIT = local;')" = 3 ] || fail "a refused commit changes nothing"
fresh; run CI_COMMIT=8f3c2a
[ $? -ne 0 ] || fail "a commit shorter than 7 characters must stop the build"
fresh; run CI_COMMIT=8F3C2A1D
[ $? -ne 0 ] || fail "git writes commits in lowercase; anything else isn't one"
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

# The committed package pins reach the generated project; without them nothing is created.
pins="$work/repo/Doddy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
fresh; run
[ ! -e "$pins" ] || fail "with no Config/Package.resolved no resolved file should appear in the project"
fresh; printf '{ "pins" : [], "version" : 3 }\n' > "$work/repo/Config/Package.resolved"; run
[ $? -eq 0 ] || fail "installing the pins should succeed: $(cat "$work/out")"
cmp -s "$work/repo/Config/Package.resolved" "$pins" || fail "Config/Package.resolved should be copied into the project unchanged"

# Stand-ins for the tools step 1 and step 6 call, so nothing is downloaded, generated or resolved (and a
# Mac running this test doesn't change its own Xcode defaults or install anything from Homebrew).
mkdir -p "$work/fakebin"
printf '#!/bin/sh\necho "$@" >> "%s/xcodebuild-calls"\n' "$work" > "$work/fakebin/xcodebuild"
printf '#!/bin/sh\necho "$@" >> "%s/defaults-calls"\n' "$work" > "$work/fakebin/defaults"
printf '#!/bin/sh\necho "$@" >> "%s/brew-calls"\nexit 1\n' "$work" > "$work/fakebin/brew"
chmod +x "$work/fakebin/xcodebuild" "$work/fakebin/defaults" "$work/fakebin/brew"
# A stand-in scripts/install_xcodegen.sh (exit code $1; 0 prints the folder of a stand-in `xcodegen`).
fake_install() {
  mkdir -p "$work/repo/scripts" "$work/xg"
  printf '#!/bin/sh\n[ "%s" = 0 ] || { echo "stand-in: the download failed" >&2; exit %s; }\necho "%s/xg"\n' "$1" "$1" "$work" \
    > "$work/repo/scripts/install_xcodegen.sh"
  printf '#!/bin/sh\necho "$@" >> "%s/xcodegen-calls"\n' "$work" > "$work/xg/xcodegen"
  chmod +x "$work/xg/xcodegen"
  rm -f "$work/xcodegen-calls" "$work/brew-calls"
}
run_tools() {  # env assignments..., with the stand-ins first on PATH; XcodeGen is not skipped
  env -i PATH="$work/fakebin:$PATH" CI_PRIMARY_REPOSITORY_PATH="$work/repo" DODDY_SKIP_RESOLVE=1 \
    "$@" sh "$script" > "$work/out" 2>&1
}

# XcodeGen: the installer's folder goes first on PATH, and nothing is installed from Homebrew.
fresh; fake_install 0; run_tools
[ $? -eq 0 ] || fail "with the pinned XcodeGen installed the script should succeed: $(cat "$work/out")"
grep -qx 'generate --spec project.yml' "$work/xcodegen-calls" 2>/dev/null || fail "the project should be generated with the installer's XcodeGen (calls: $(cat "$work/xcodegen-calls" 2>/dev/null))"
[ ! -e "$work/brew-calls" ] || fail "XcodeGen must not come from Homebrew (the version would not be pinned)"
fresh; fake_install 1; run_tools
[ $? -ne 0 ] || fail "when the pinned XcodeGen can't be installed the build must stop"
grep -q "couldn't install the pinned XcodeGen" "$work/out" || fail "and say so"
[ ! -e "$work/xcodegen-calls" ] || fail "and never fall back to another XcodeGen"
[ ! -e "$work/brew-calls" ] || fail "and never fall back to Homebrew"

# Package resolution (step 6): with the committed pins in the project it may only use the pinned versions.
only_flag=-onlyUsePackageVersionsFromResolvedFile
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
run_resolve() {  # env assignments..., with the stand-ins first on PATH; resolution is not skipped
  rm -f "$work/xcodebuild-calls"
  env -i PATH="$work/fakebin:$PATH" CI_PRIMARY_REPOSITORY_PATH="$work/repo" DODDY_SKIP_XCODEGEN=1 \
    "$@" sh "$script" > "$work/out" 2>&1
  status=$?
  calls=$(cat "$work/xcodebuild-calls" 2>/dev/null || true)
}
with_pins() { fresh; printf '{ "pins" : [], "version" : 3 }\n' > "$work/repo/Config/Package.resolved"; }
with_pins; run_resolve
[ $status -eq 0 ] || fail "resolving with the pins installed should succeed: $(cat "$work/out")"
has "$calls" "-resolvePackageDependencies" || fail "packages should be resolved (calls: $calls)"
has "$calls" "$only_flag" || fail "with pins installed only the pinned versions may be used (calls: $calls)"
[ "$(printf '%s\n' "$calls" | wc -l | tr -d ' ')" = 1 ] || fail "one resolve call expected (calls: $calls)"
fresh; run_resolve
[ $status -eq 0 ] || fail "resolving without pins should succeed: $(cat "$work/out")"
has "$calls" "-resolvePackageDependencies" || fail "without pins packages are still resolved (calls: $calls)"
! has "$calls" "$only_flag" || fail "without pins there is nothing to hold the resolver to, so no restriction (calls: $calls)"
with_pins; run_resolve DODDY_PACKAGES_FREE=1
[ $status -eq 0 ] || fail "DODDY_PACKAGES_FREE=1 should succeed: $(cat "$work/out")"
! has "$calls" "$only_flag" || fail "DODDY_PACKAGES_FREE=1 lets the resolver move versions (calls: $calls)"
with_pins; run_resolve DODDY_PACKAGES_FREE=0
has "$calls" "$only_flag" || fail "only the exact value 1 frees the resolver, so a typo can't loosen the pins (calls: $calls)"

if [ "$failures" -ne 0 ]; then echo "FAIL: $failures check(s)"; exit 1; fi
echo "PASS: ci_post_clone.sh sets the build number, commit, team, bundle ID and push entitlements and refuses bad values"

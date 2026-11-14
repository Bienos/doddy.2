#!/bin/sh
# Xcode Cloud runs this after it clones the repository and before it resolves packages and builds
# (ADR-697, docs/implementation/XCODE_CLOUD.md). It must sit in `ci_scripts/` next to the project,
# be executable, and finish without error, or the build stops.
#
# Why it is needed:
#   1. `Doddy.xcodeproj` is not committed; XcodeGen makes it from `project.yml` (as `make project`),
#      at the one version pinned in scripts/install_xcodegen.sh.
#   2. Every upload to TestFlight needs a build number higher than the last. The app and its two
#      extensions must have the same one. Xcode Cloud numbers its builds (CI_BUILD_NUMBER).
#   3. Xcode Cloud does not resolve Swift packages by itself: it needs `Package.resolved` in the
#      project, which a generated project doesn't have. Resolving here writes it.
#   4. Which commit a TestFlight build was made from (7 Nov 2026 audit): Xcode Cloud's CI_COMMIT goes
#      into the DODDY_GIT_COMMIT build setting, which Info.plist and Settings › About carry.
#   5. Push notifications (ADR-701). The project's default entitlements have no `aps-environment`,
#      so a build from them can never receive a push, however the server is set up. Xcode Cloud's
#      builds are the ones testers install, so they get Config/Doddy-Push-AppGroup.entitlements.
#
# Optional environment variables, set in the workflow (App Store Connect › Xcode Cloud › the
# workflow › Environment). None is a secret:
#   DODDY_TEAM_ID    the Apple Developer team ID, when Xcode Cloud asks for a team (the spec
#                    commits none: `DEVELOPMENT_TEAM: ""`).
#   DODDY_BUNDLE_ID  another bundle ID than `com.bienos.doddy2.dev` (go-live checklist C1).
#   DODDY_PUSH       `0` builds without push notifications (for example while Push Notifications
#                    isn't enabled on the App ID, which makes signing fail). Anything else, or not
#                    set: push on. The App ID needs the Push Notifications capability either way
#                    it is on.
#   DODDY_PACKAGES_FREE  `1` lets package resolution move versions again. By default, with the
#                    committed pins in the project, it uses only the pinned versions and fails when
#                    the pins file is out of date (step 6). For one build, if that ever blocks a
#                    TestFlight build; then refresh the pins (`make update-packages`).
#
# Nothing here signs, uploads or reads a key: Xcode Cloud signs with the team's cloud-managed
# certificates and uploads to TestFlight as the workflow says.
set -eu

repo=${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}
cd "$repo"
pbx=Doddy.xcodeproj/project.pbxproj

# Replaces every `from` with `to` in the generated project and fails if `from` wasn't there, so a
# change in XcodeGen's output can't silently ship build 1 or no team. Plain sed to a temporary file:
# the same on macOS (Xcode Cloud) and Linux (where scripts/test_xcode_cloud_post_clone.sh runs it).
set_in_project() {
  from=$1 to=$2 what=$3
  if ! grep -qF "$from" "$pbx"; then
    echo "ci_post_clone: couldn't set $what: '$from' isn't in $pbx" >&2
    exit 1
  fi
  sed "s|$from|$to|g" "$pbx" > "$pbx.tmp" && mv "$pbx.tmp" "$pbx"
  echo "ci_post_clone: $what set"
}

# Like set_in_project, for `KEY = value;` where XcodeGen may or may not put the value in quotes (it
# quotes a path with a slash: DODDY_APP_ENTITLEMENTS = "Config/Doddy-AppGroup.entitlements";, as
# Xcode Cloud's first real run showed). The quotes, if any, are kept.
set_setting() {
  key=$1 old=$2 new=$3 what=$4
  esc=$(printf '%s' "$old" | sed 's/[.]/\\./g')
  if ! grep -Eq "$key = \"?$esc\"?;" "$pbx"; then
    echo "ci_post_clone: couldn't set $what: '$key = $old;' (with or without quotes) isn't in $pbx" >&2
    exit 1
  fi
  sed -E "s|$key = (\"?)$esc(\"?);|$key = \\1$new\\2;|g" "$pbx" > "$pbx.tmp" && mv "$pbx.tmp" "$pbx"
  echo "ci_post_clone: $what set"
}

# 1. The project, as `make project` makes it (the shipping build, with the App Group). XcodeGen is
# the one version GitHub's CI uses, installed from its release file after a SHA-256 check
# (scripts/install_xcodegen.sh) instead of whatever Homebrew has on the day.
if [ -z "${DODDY_SKIP_XCODEGEN:-}" ]; then
  xcodegen_bin=$(sh "$repo/scripts/install_xcodegen.sh") || { echo "ci_post_clone: couldn't install the pinned XcodeGen" >&2; exit 1; }
  PATH="$xcodegen_bin:$PATH"
  export PATH
  xcodegen --version || true
  xcodegen generate --spec project.yml
fi
[ -f "$pbx" ] || { echo "ci_post_clone: $pbx wasn't generated" >&2; exit 1; }

# 1b. The app's pinned package versions (Config/Package.resolved, 7 Nov 2026 audit), as `make project`
# and scripts/ci.sh install them, so TestFlight gets exactly the versions GitHub's CI built and
# tested. Before step 6, which resolves from them and nothing newer (pins_installed).
pins_installed=0
if [ -f Config/Package.resolved ]; then
  mkdir -p Doddy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
  cp Config/Package.resolved Doddy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
  pins_installed=1
  echo "ci_post_clone: pinned package versions installed"
fi

# 2. One build number for the app and all its extensions: Xcode Cloud's.
if [ -n "${CI_BUILD_NUMBER:-}" ]; then
  case $CI_BUILD_NUMBER in
    *[!0-9]*) echo "ci_post_clone: CI_BUILD_NUMBER '$CI_BUILD_NUMBER' isn't a whole number" >&2; exit 1 ;;
  esac
  set_in_project "CURRENT_PROJECT_VERSION = 1;" "CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;" \
    "build number $CI_BUILD_NUMBER"
fi

# 2b. The commit this build is made from: Xcode Cloud's CI_COMMIT, or the checkout's own. Without
# either (a test run outside a repository) the project keeps `local`. A value that isn't a commit
# stops the build rather than ship a wrong one.
commit=${CI_COMMIT:-$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)}
if [ -n "$commit" ]; then
  case $commit in
    *[!0-9a-f]*) echo "ci_post_clone: '$commit' isn't a commit (lowercase hex)" >&2; exit 1 ;;
  esac
  if [ ${#commit} -lt 7 ] || [ ${#commit} -gt 40 ]; then
    echo "ci_post_clone: '$commit' isn't a commit (7 to 40 characters)" >&2
    exit 1
  fi
  set_setting DODDY_GIT_COMMIT local "$commit" "commit $(printf '%s' "$commit" | cut -c1-7)"
fi
# 3. The team, when the workflow names one (10 letters and digits).
if [ -n "${DODDY_TEAM_ID:-}" ]; then
  case $DODDY_TEAM_ID in
    *[!A-Z0-9]*) echo "ci_post_clone: DODDY_TEAM_ID isn't a team ID (capital letters and digits)" >&2; exit 1 ;;
  esac
  set_in_project 'DEVELOPMENT_TEAM = "";' "DEVELOPMENT_TEAM = $DODDY_TEAM_ID;" "team"
fi

# 4. Another bundle ID, when the workflow names one. The App Group and the extensions' IDs follow it.
if [ -n "${DODDY_BUNDLE_ID:-}" ]; then
  case $DODDY_BUNDLE_ID in
    *[!A-Za-z0-9.-]*) echo "ci_post_clone: DODDY_BUNDLE_ID has characters a bundle ID can't" >&2; exit 1 ;;
  esac
  set_setting DODDY_APP_BUNDLE_IDENTIFIER com.bienos.doddy2.dev "$DODDY_BUNDLE_ID" "bundle ID $DODDY_BUNDLE_ID"
fi

# 5. Push notifications: the entitlements file with `aps-environment` (and the same App Group, Sign in
# with Apple and Health entries as the default), unless the workflow says DODDY_PUSH=0. Xcode
# replaces the file's `development` with `production` when it signs for TestFlight. The line it
# replaces must be there: a build that quietly ships without push is the failure this step exists
# to stop.
if [ "${DODDY_PUSH:-1}" != "0" ]; then
  [ -f Config/Doddy-Push-AppGroup.entitlements ] || { echo "ci_post_clone: Config/Doddy-Push-AppGroup.entitlements is missing" >&2; exit 1; }
  set_setting DODDY_APP_ENTITLEMENTS Config/Doddy-AppGroup.entitlements \
    Config/Doddy-Push-AppGroup.entitlements "push notifications"
fi

# 6. The Swift packages, so Package.resolved exists before Xcode Cloud builds.
if [ -z "${DODDY_SKIP_RESOLVE:-}" ]; then
  # Xcode Cloud turns automatic package resolution off and refuses an out-of-date Package.resolved
  # (its first build failed with "an out-of-date resolved file was detected"). The project is
  # generated here, and when that build failed it had no resolved file of its own: allow the resolver
  # to run. With the pins installed (step 1b) the resolver is held to them just below.
  if command -v defaults >/dev/null 2>&1; then
    defaults write com.apple.dt.Xcode IDEDisableAutomaticPackageResolution -bool NO
    defaults write com.apple.dt.Xcode IDEPackageOnlyUseVersionsFromResolvedFile -bool NO
  fi
  # DoddyCore's own Package.resolved pins only its dependencies, not the app's (ElevenLabs, LiveKit),
  # so Xcode Cloud calls it out of date. It is only a copy of this fresh checkout: drop it here
  # (the repository keeps it for the package's own tests) and let the resolver write a complete one.
  rm -f Packages/DoddyCore/Package.resolved
  # LiveKit's binary frameworks download from GitHub release assets, which answer 504 to anonymous
  # downloads during GitHub incidents (builds 25 and 26, 8 to 9 Nov 2026: GitHub's "surge in
  # anonymous users" incident, which came and went for hours). Try up to six times, waiting 30 s,
  # 60 s, 90 s, 120 s and 150 s (about 7.5 minutes in all); a real resolution error still stops the
  # build after the last try.
  #
  # With the committed pins in the project (step 1b), resolve only to the versions in that file:
  # -onlyUsePackageVersionsFromResolvedFile fails when the file is out of date instead of quietly
  # moving a package to a newer version, so TestFlight can't get versions GitHub's CI didn't test
  # (CI fails when resolution would change the pins). Without pins there is nothing to hold it to.
  # DODDY_PACKAGES_FREE=1, set in the workflow's environment, lets the resolver move versions again
  # (for one build, if a stale pins file ever blocks TestFlight; then run `make update-packages`).
  resolve_flags=""
  if [ "$pins_installed" = 1 ] && [ "${DODDY_PACKAGES_FREE:-}" != "1" ]; then
    resolve_flags="-onlyUsePackageVersionsFromResolvedFile"
    echo "ci_post_clone: resolving only the pinned package versions"
  fi
  attempt=1
  # shellcheck disable=SC2086
  until xcodebuild -resolvePackageDependencies -project Doddy.xcodeproj -scheme Doddy $resolve_flags; do
    if [ "$attempt" -ge "${DODDY_RESOLVE_ATTEMPTS:-6}" ]; then
      echo "ci_post_clone: package resolution failed $attempt times" >&2
      exit 1
    fi
    wait=$((attempt * 30))
    echo "ci_post_clone: package resolution failed (try $attempt); trying again in ${wait}s" >&2
    sleep "$wait"
    attempt=$((attempt + 1))
  done
  echo "ci_post_clone: resolved files:"
  find . -name Package.resolved -not -path "./.build/*" 2>/dev/null | head
fi
echo "ci_post_clone: ready"

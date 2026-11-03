#!/bin/sh
# Xcode Cloud runs this after it clones the repository and before it resolves packages and builds
# (ADR-697, docs/implementation/XCODE_CLOUD.md). It must sit in `ci_scripts/` next to the project,
# be executable, and finish without error, or the build stops.
#
# Why it is needed:
#   1. `Doddy.xcodeproj` is not committed; XcodeGen makes it from `project.yml` (as `make project`).
#   2. Every upload to TestFlight needs a build number higher than the last. The app and its two
#      extensions must have the same one. Xcode Cloud numbers its builds (CI_BUILD_NUMBER).
#   3. Xcode Cloud does not resolve Swift packages by itself: it needs `Package.resolved` in the
#      project, which a generated project doesn't have. Resolving here writes it.
#   4. Push notifications (ADR-701). The project's default entitlements have no `aps-environment`,
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

# 1. The project, as `make project` makes it (the shipping build, with the App Group).
if [ -z "${DODDY_SKIP_XCODEGEN:-}" ]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
  fi
  xcodegen generate --spec project.yml
fi
[ -f "$pbx" ] || { echo "ci_post_clone: $pbx wasn't generated" >&2; exit 1; }

# 2. One build number for the app, the widgets and the share extension: Xcode Cloud's.
if [ -n "${CI_BUILD_NUMBER:-}" ]; then
  case $CI_BUILD_NUMBER in
    *[!0-9]*) echo "ci_post_clone: CI_BUILD_NUMBER '$CI_BUILD_NUMBER' isn't a whole number" >&2; exit 1 ;;
  esac
  set_in_project "CURRENT_PROJECT_VERSION = 1;" "CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;" \
    "build number $CI_BUILD_NUMBER"
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
  set_in_project "DODDY_APP_BUNDLE_IDENTIFIER = com.bienos.doddy2.dev;" \
    "DODDY_APP_BUNDLE_IDENTIFIER = $DODDY_BUNDLE_ID;" "bundle ID $DODDY_BUNDLE_ID"
fi

# 5. Push notifications: the entitlements file with `aps-environment` (and the same App Group, Sign in
# with Apple and Health entries as the default), unless the workflow says DODDY_PUSH=0. Xcode
# replaces the file's `development` with `production` when it signs for TestFlight. The line it
# replaces must be there: a build that quietly ships without push is the failure this step exists
# to stop.
if [ "${DODDY_PUSH:-1}" != "0" ]; then
  [ -f Config/Doddy-Push-AppGroup.entitlements ] || { echo "ci_post_clone: Config/Doddy-Push-AppGroup.entitlements is missing" >&2; exit 1; }
  set_in_project "DODDY_APP_ENTITLEMENTS = Config/Doddy-AppGroup.entitlements;" \
    "DODDY_APP_ENTITLEMENTS = Config/Doddy-Push-AppGroup.entitlements;" "push notifications"
fi

# 6. The Swift packages, so Package.resolved exists before Xcode Cloud builds.
if [ -z "${DODDY_SKIP_RESOLVE:-}" ]; then
  xcodebuild -resolvePackageDependencies -project Doddy.xcodeproj -scheme Doddy
fi
echo "ci_post_clone: ready"

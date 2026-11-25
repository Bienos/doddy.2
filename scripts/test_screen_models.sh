#!/usr/bin/env bash
# Run the five Foundation-only screen models together so Swift compiles their test target once.
# The individual scripts remain available for focused local runs.
#
#   scripts/test_screen_models.sh             copy them into a temporary test folder, test, remove it
#   scripts/test_screen_models.sh --prepare   (hosted CI, 25 Nov 2026) copy them into the fixed folder
#       Packages/DoddyCore/Tests/DoddyCoreTests/_ScreenModels.ci with content-based file times and stop, so
#       the package tests that follow compile them once with everything else and the cached build stays
#       valid; `--run-prepared` then runs just their suites without building again.
set -euo pipefail
cd "$(dirname "$0")/.."
suites='CallCasesModelTests|MessagesModelTests|WatchModelTests|OpenLoopsModelTests|TrainingLogModelTests'
flags=()
[ "$(uname)" = "Linux" ] && flags=(-Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined)

copy_into() {  # DIR
  local work=$1
  cp DoddyApp/Features/CallCases/CallCasesModel.swift DoddyTests/CallCasesModelTests.swift "$work/"
  cp DoddyApp/Features/Messages/MessagesModel.swift DoddyApp/Features/Messages/FilesShownSinceStore.swift DoddyTests/MessagesModelTests.swift "$work/"
  cp DoddyApp/Features/Shopping/WatchModel.swift DoddyTests/WatchModelTests.swift "$work/"
  cp DoddyApp/Features/OpenLoops/OpenLoopsModel.swift DoddyTests/OpenLoopsModelTests.swift "$work/"
  cp DoddyApp/Features/Sport/TrainingLogModel.swift DoddyTests/TrainingLogModelTests.swift "$work/"
  cat > "$work/AppStandIns.swift" <<'SWIFT'
import DoddyCore
enum ServerConfig {
    static func client() -> DoddyServerClient? { nil }
}
@MainActor
enum WatchPush {
    static func register() async {}
}
SWIFT
}

prepared=Packages/DoddyCore/Tests/DoddyCoreTests/_ScreenModels.ci
case "${1:-}" in
  --prepare)
    rm -rf "$prepared"; mkdir -p "$prepared"
    copy_into "$prepared"
    # The same times scripts/ci_content_mtimes.sh gives tracked files: from each file's git blob hash.
    for f in "$prepared"/*.swift; do
      sha=$(git -c safe.directory='*' hash-object "$f")
      touch -m -d "@$((1000000000 + 16#${sha:0:7} % 300000000))" "$f"
    done
    echo "Screen models prepared in $prepared; the package tests compile them."
    exit 0 ;;
  --run-prepared)
    command -v swift >/dev/null 2>&1 || { echo "NOT RUN: swift not found on PATH"; exit 2; }
    [ -d "$prepared" ] || { echo "FAIL: $prepared is missing; run with --prepare before the package tests"; exit 1; }
    swift test --package-path Packages/DoddyCore ${flags[@]+"${flags[@]}"} --skip-build --filter "$suites"
    exit $? ;;
  "") ;;
  *) echo "unknown argument: $1" >&2; exit 64 ;;
esac

command -v swift >/dev/null 2>&1 || { echo "NOT RUN: swift not found on PATH"; exit 2; }
work=$(mktemp -d Packages/DoddyCore/Tests/DoddyCoreTests/_ScreenModels.XXXXXX)
trap 'rm -rf "$work"' EXIT
copy_into "$work"
swift test --package-path Packages/DoddyCore ${flags[@]+"${flags[@]}"} --filter "$suites"

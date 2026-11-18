#!/usr/bin/env bash
# Run the five Foundation-only screen models together so Swift compiles their test target once.
# The individual scripts remain available for focused local runs.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v swift >/dev/null 2>&1 || { echo "NOT RUN: swift not found on PATH"; exit 2; }
work=$(mktemp -d Packages/DoddyCore/Tests/DoddyCoreTests/_ScreenModels.XXXXXX)
trap 'rm -rf "$work"' EXIT
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
flags=()
[ "$(uname)" = "Linux" ] && flags=(-Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined)
swift test --package-path Packages/DoddyCore ${flags[@]+"${flags[@]}"} --filter 'CallCasesModelTests|MessagesModelTests|WatchModelTests|OpenLoopsModelTests|TrainingLogModelTests'

#!/usr/bin/env bash
# Runs the price watch's state tests (DoddyTests/WatchModelTests.swift, SHOPPING_WATCH.md, ADR-614) on Linux:
# the model file and its tests are linked into the DoddyCore test target for one run, then removed.
# The model imports only Foundation, Observation and DoddyCore, so no Xcode is needed; the two app types it
# names (ServerConfig, which builds a URLSession transport, and WatchPush, which asks iOS for the push
# token) get one-line stand-ins for this run only, as in scripts/typecheck_app_logic.sh. The same test
# file runs in Xcode as part of DoddyTests, against the real ones.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v swift >/dev/null 2>&1 || { echo "NOT RUN: swift not found on PATH"; exit 2; }
tmp=Packages/DoddyCore/Tests/DoddyCoreTests/_WatchModel
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT
cp DoddyApp/Features/Shopping/WatchModel.swift DoddyTests/WatchModelTests.swift "$tmp/"
cat > "$tmp/AppStandIns.swift" <<'SWIFT'
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
swift test --package-path Packages/DoddyCore ${flags[@]+"${flags[@]}"} --filter WatchModelTests

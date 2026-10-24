#!/usr/bin/env bash
# Runs the training log's state tests (DoddyTests/TrainingLogModelTests.swift, ADR-632) on Linux:
# the model file and its tests are linked into the DoddyCore test target for one run, then removed.
# The model imports only Foundation, Observation and DoddyCore, so no Xcode is needed. The same test
# file runs in Xcode as part of DoddyTests.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v swift >/dev/null 2>&1 || { echo "NOT RUN: swift not found on PATH"; exit 2; }
tmp=Packages/DoddyCore/Tests/DoddyCoreTests/_TrainingLogModel
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT
cp DoddyApp/Features/Sport/TrainingLogModel.swift DoddyTests/TrainingLogModelTests.swift "$tmp/"
flags=()
[ "$(uname)" = "Linux" ] && flags=(-Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined)
swift test --package-path Packages/DoddyCore ${flags[@]+"${flags[@]}"} --filter TrainingLogModelTests

#!/usr/bin/env bash
# Training plan (ADR-625): builds the app's TrainingPlanStore with the core plan engine and runs it
# against real files: kept and read back, read after a "restart", an edited file not shown as
# Doddy's plan, an unreadable file kept, a new plan replacing it, delete, a failed write reported.
# Foundation only, so it runs on Linux; the app's own build is still needed for the screens.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v swiftc >/dev/null 2>&1 || { echo "NOT RUN: swiftc not found on PATH"; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed 's/^import DoddyCore$//' DoddyApp/Features/Sport/TrainingPlanStore.swift > "$work/Store.swift"
# Only the plan engine's own files. The rest of Sport/ (the triage, the interview, the log, the
# review) needs more of DoddyCore than this check compiles, and the store does not use it.
for f in TrainingPlan PlanEngine PlanRules SavedPlan; do cp "Packages/DoddyCore/Sources/DoddyCore/Sport/$f.swift" "$work/"; done
cp scripts/checks/training_plan_store_main.swift "$work/main.swift"
swiftc -swift-version 6 -parse-as-library -o "$work/run" "$work"/*.swift
"$work/run"

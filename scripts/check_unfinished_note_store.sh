#!/usr/bin/env bash
# Unfinished notes (ADR-340): builds the app's UnfinishedNoteStore with the core draft rules and
# runs it against real files: written after the delay, read back after a "restart", removed on
# save, an unreadable file set aside, Delete all, a failed write reported. Foundation only, so it
# runs on Linux; the app's own build is still needed for the screens.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed 's/^import DoddyCore$//' DoddyApp/Infrastructure/UnfinishedNoteStore.swift > "$work/Store.swift"
cp Packages/DoddyCore/Sources/DoddyCore/UnfinishedNotes.swift "$work/"
# The one core type the draft needs, as declared in MemoryTypes.swift (cases used here only).
echo 'public enum MemoryCategory: String, Codable, CaseIterable, Sendable { case fact, place, other }' > "$work/Category.swift"
cp scripts/checks/unfinished_note_store_main.swift "$work/main.swift"
swiftc -swift-version 6 -parse-as-library -o "$work/run" "$work/main.swift" "$work/Store.swift" "$work/UnfinishedNotes.swift" "$work/Category.swift"
"$work/run"

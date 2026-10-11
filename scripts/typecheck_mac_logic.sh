#!/usr/bin/env bash
# Type-checks DoddyMac/MacModel.swift (the Mac menu-bar app's memory model, ADR-450) against the
# real DoddyCore and DoddyPersistence modules, in Swift 6 mode, on Linux. It imports only
# Foundation, Observation and the two packages, so this is a real compile of that file.
# It does NOT cover the SwiftUI/AppKit files in DoddyMac (menu, windows, icon); those need Xcode on
# a Mac (docs/implementation/MAC_MENUBAR_STATUS.md).
set -euo pipefail
cd "$(dirname "$0")/.."

command -v swift >/dev/null 2>&1 || { echo "NOT RUN: swift not found on PATH"; exit 2; }

package=Packages/DoddyCore
flags=()
[ "$(uname)" = "Linux" ] && flags=(-Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined)

swift build --package-path "$package" ${flags[@]+"${flags[@]}"} >/dev/null
modules="$(swift build --package-path "$package" ${flags[@]+"${flags[@]}"} --show-bin-path)/Modules"
[ -d "$modules" ] || { echo "FAIL: DoddyCore module directory not found at $modules"; exit 1; }
# GRDB's SQLite shim module is not on the default search path for a bare swiftc.
modulemap=$(find "$package/.build" -path '*GRDBSQLite*' -name module.modulemap | head -1)
[ -n "$modulemap" ] || { echo "FAIL: GRDBSQLite module map not found under $package/.build"; exit 1; }

swiftc -typecheck -swift-version 6 -I "$modules" \
  -Xcc -fmodule-map-file="$PWD/$modulemap" -Xcc -DSQLITE_DISABLE_SNAPSHOT \
  DoddyMac/MacModel.swift
echo "PASS: DoddyMac/MacModel.swift type-checks in Swift 6 mode"

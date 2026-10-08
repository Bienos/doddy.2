#!/usr/bin/env bash
# DODDY V2 — M0 check script. Fails honestly: a step that cannot run is reported NOT RUN and
# makes the script exit non-zero, so "green" always means everything ran and passed.
#
#   scripts/ci.sh              full run (needs Swift AND Xcode/xcodebuild)
#   scripts/ci.sh --core-only  pack integrity + guards + Swift package tests only;
#                              the iOS app build and tests are reported NOT RUN (exit 0
#                              only if everything that was requested passed)
set -uo pipefail
cd "$(dirname "$0")/.."

core_only=0
[ "${1:-}" = "--core-only" ] && core_only=1

declare -a results=()
failed=0 blocked=0
record() { results+=("$1|$2|$3"); }
run_step() {  # name, command...
  local name=$1; shift
  echo; echo "=== $name"; echo "\$ $*"
  if "$@"; then record "$name" PASS ""; else record "$name" FAIL "exit $?"; failed=1; fi
}
not_run() { record "$1" "NOT RUN" "$2"; blocked=1; echo; echo "=== $1"; echo "NOT RUN: $2"; }

run_step "Imported pack integrity" python3 -I scripts/verify_imported_pack.py
run_step "Forbidden-capability guard" scripts/check_forbidden_capabilities.sh

if command -v swift >/dev/null 2>&1; then
  swift --version
  # Ubuntu's system SQLite lacks the snapshot API GRDB enables by default; Doddy does not use it.
  extra=(); [ "$(uname)" = "Linux" ] && extra=(-Xswiftc -DSQLITE_DISABLE_SNAPSHOT)
  run_step "Swift package tests (DoddyCore)" swift test --package-path Packages/DoddyCore "${extra[@]}"
else
  not_run "Swift package tests (DoddyCore)" "swift not found on PATH"
fi

if [ "$core_only" -eq 1 ]; then
  record "iOS app build + tests" "NOT RUN" "--core-only requested"
elif ! command -v xcodebuild >/dev/null 2>&1; then
  not_run "iOS app build + tests" "xcodebuild not found (needs macOS with Xcode)"
elif ! command -v xcodegen >/dev/null 2>&1; then
  not_run "iOS app build + tests" "xcodegen not found (brew install xcodegen)"
else
  run_step "Generate Xcode project" xcodegen generate --spec project.yml
  dest=${DODDY_DESTINATION:-"platform=iOS Simulator,name=iPhone 16"}
  run_step "xcodebuild -list" xcodebuild -list -project Doddy.xcodeproj
  run_step "xcodebuild test (unit + UI)" xcodebuild test -project Doddy.xcodeproj -scheme Doddy -destination "$dest"
fi

echo; echo "================ SUMMARY"
for r in "${results[@]}"; do IFS='|' read -r n s d <<<"$r"; printf '%-8s %s %s\n' "$s" "$n" "${d:+($d)}"; done
if [ "$failed" -ne 0 ]; then echo "RESULT: FAIL"; exit 1; fi
if [ "$blocked" -ne 0 ]; then echo "RESULT: BLOCKED (a required step could not run)"; exit 2; fi
if [ "$core_only" -eq 1 ]; then echo "RESULT: PASS for core-only scope; iOS app NOT verified"; exit 0; fi
echo "RESULT: PASS"

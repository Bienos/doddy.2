#!/usr/bin/env bash
# DODDY V2 — M0 check script. Fails honestly: a step that cannot run is reported NOT RUN and
# makes the script exit non-zero, so "green" always means everything ran and passed.
#
#   scripts/ci.sh              full run (needs Swift AND Xcode/xcodebuild)
#   scripts/ci.sh --core-only  pack integrity + guards + Swift package tests + Node services only
#                              (on Linux also a type-check of the non-UI app files);
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
run_step "Voice agent spec" python3 -I scripts/voice_agent_spec.py check
run_step "Phone agent spec" python3 -I scripts/voice_agent_spec.py check --agent phone
run_step "Blog pages up to date" python3 -I tools/build_blog.py --check
run_step "Polish string catalog up to date" python3 -I tools/build_strings_catalog.py --check
if python3 -I -c "import yaml" 2>/dev/null; then
  run_step "Per-platform Xcode specs in step" python3 -I scripts/check_platform_specs.py
else
  not_run "Per-platform Xcode specs in step" "PyYAML not installed (apt install python3-yaml or pip install pyyaml)"
fi

if command -v swift >/dev/null 2>&1; then
  swift --version
  # Ubuntu's system SQLite lacks the snapshot API GRDB enables by default; Doddy does not use it.
  # (No arrays: macOS ships bash 3.2, where an empty "${arr[@]}" fails under `set -u`.)
  if [ "$(uname)" = "Linux" ]; then
    # --allow-shlib-undefined: once swift-crypto's C code is in the test link (ADR-222), the Swift
    # 6.2 Linux linker checks libswiftObservation.so's own undefined symbols and fails; Linux only.
    run_step "Swift package tests (DoddyCore)" swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined
    # A real compile of the app files that need no Apple UI framework (ADR-200). On a Mac the
    # full xcodebuild below compiles everything, so this step is Linux-only.
    run_step "App logic type-check (non-UI app files)" scripts/typecheck_app_logic.sh
  else
    run_step "Swift package tests (DoddyCore)" swift test --package-path Packages/DoddyCore
  fi
  # Island drawing data matches the owner's SVGs, parses, and maps states correctly (ADR-239).
  run_step "Dynamic Island art and scenes" scripts/check_island_art.sh
else
  not_run "Swift package tests (DoddyCore)" "swift not found on PATH"
fi

if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  run_step "Voice token server tests" npm test --prefix server/voice-token
else
  not_run "Voice token server tests" "node/npm not found on PATH"
fi
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  node --version
  if [ ! -d backend/node_modules ]; then run_step "Backend install (npm ci)" npm ci --prefix backend; fi
  run_step "Backend type-check" npm run --prefix backend typecheck
  run_step "Backend tests (offline, mock + fake Composio)" npm test --prefix backend
else
  not_run "Backend type-check + tests" "node/npm not found on PATH"
fi
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  if [ ! -d gateway/node_modules ]; then run_step "Gateway install (npm ci)" npm ci --prefix gateway; fi
  run_step "Gateway typecheck" npm run typecheck --prefix gateway
  run_step "Gateway tests (node)" npm test --prefix gateway
else
  not_run "Gateway tests (node)" "node/npm not found on PATH"
fi

# Messaging server (server/messaging, Node 22 + Postgres). Its database tests need a disposable
# database in TEST_DATABASE_URL; without one they are skipped and listed as SKIPPED, never PASS.
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  if [ ! -d server/messaging/node_modules ]; then run_step "Messaging server install (npm ci)" npm ci --prefix server/messaging --no-audit --no-fund; fi
  run_step "Messaging server typecheck + tests" npm test --prefix server/messaging
  [ -z "${TEST_DATABASE_URL:-}" ] && record "Messaging server database tests" "SKIPPED" "TEST_DATABASE_URL not set"
else
  not_run "Messaging server tests" "node/npm not found on PATH"
fi

# Landing page waitlist functions (site/api), against an in-memory @vercel/blob stand-in; no network.
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  if [ ! -d site/node_modules ]; then run_step "Site install (npm ci)" npm ci --prefix site --no-audit --no-fund; fi
  run_step "Site waitlist function tests" npm test --prefix site
else
  not_run "Site waitlist function tests" "node/npm not found on PATH"
fi

if [ "$core_only" -eq 1 ]; then
  record "iOS app build + tests" "NOT RUN" "--core-only requested"
elif ! command -v xcodebuild >/dev/null 2>&1; then
  not_run "iOS app build + tests" "xcodebuild not found (needs macOS with Xcode)"
elif ! command -v xcodegen >/dev/null 2>&1; then
  not_run "iOS app build + tests" "xcodegen not found (brew install xcodegen)"
else
  run_step "Generate Xcode project" xcodegen generate --spec project.yml
  # Default: first available iPhone simulator; override with DODDY_DESTINATION.
  if [ -n "${DODDY_DESTINATION:-}" ]; then
    dest=$DODDY_DESTINATION
  else
    sim_id=$(xcrun simctl list devices available | grep -E '^ +iPhone' | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
    dest="platform=iOS Simulator,id=${sim_id}"
  fi
  if [ "$dest" = "platform=iOS Simulator,id=" ]; then
    not_run "iOS app build + tests" "no available iPhone simulator; install one or set DODDY_DESTINATION"
  else
    echo "Destination: $dest"
    run_step "xcodebuild -list" xcodebuild -list -project Doddy.xcodeproj
    run_step "xcodebuild test (unit + UI)" xcodebuild test -project Doddy.xcodeproj -scheme Doddy -destination "$dest"
  fi
fi

echo; echo "================ SUMMARY"
for r in "${results[@]}"; do IFS='|' read -r n s d <<<"$r"; printf '%-8s %s %s\n' "$s" "$n" "${d:+($d)}"; done
if [ "$failed" -ne 0 ]; then echo "RESULT: FAIL"; exit 1; fi
if [ "$blocked" -ne 0 ]; then echo "RESULT: BLOCKED (a required step could not run)"; exit 2; fi
if [ "$core_only" -eq 1 ]; then echo "RESULT: PASS for core-only scope; iOS app NOT verified"; exit 0; fi
echo "RESULT: PASS"

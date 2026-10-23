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
  if "$@"; then record "$name" PASS ""; else record "$name" FAIL "exit $?"; failed=1; return 1; fi
}
not_run() { record "$1" "NOT RUN" "$2"; blocked=1; echo; echo "=== $1"; echo "NOT RUN: $2"; }
# Shut a simulator down and boot it again, waiting until it has finished booting (ADR-561).
restart_simulator() {
  xcrun simctl shutdown "$1" 2>/dev/null || true  # fails harmlessly if it is already shut down
  xcrun simctl bootstatus "$1" -b                 # -b boots it first, then waits for the boot
}

run_step "Imported pack integrity" python3 -I scripts/verify_imported_pack.py
run_step "Forbidden-capability guard" scripts/check_forbidden_capabilities.sh
run_step "Voice agent spec" python3 -I scripts/voice_agent_spec.py check
run_step "Phone agent spec" python3 -I scripts/voice_agent_spec.py check --agent phone
run_step "Task-call agent spec" python3 -I scripts/voice_agent_spec.py check --agent task-call
run_step "Blog pages up to date" python3 -I tools/build_blog.py --check
run_step "Site pages in every language up to date" python3 -I tools/build_site_i18n.py --check
run_step "String catalogs up to date" python3 -I tools/build_strings_catalog.py --check
run_step "What-can-doddy-do page up to date" python3 -I tools/build_day.py --check
run_step "Web app tokens and brand files match the app (ADR-600)" python3 -I tools/gen_web_assets.py --check
run_step "Which pull requests need the macOS build (ADR-497)" scripts/test_ci_needs_mac.sh
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
    # The call screens' state, run with fakes for the server and the store (ADR-500).
    run_step "Call screens' state tests" scripts/test_call_cases_model.sh
    # The Messages screen's state, run with fakes for the store and the server (ADR-585).
    run_step "Messages screen's state tests" scripts/test_messages_model.sh
    run_step "Unfinished notes on real files" scripts/check_unfinished_note_store.sh
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

# Doddy Web (web/, ADR-600): type-check, unit tests against the server's own fixtures, and the
# production build. The end-to-end run (real backend + Chromium) needs a Playwright Chromium; where
# there is none it is listed as SKIPPED, never PASS.
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  if [ ! -d web/node_modules ]; then run_step "Web app install (npm ci)" npm ci --prefix web --no-audit --no-fund; fi
  run_step "Web app type-check" npm run typecheck --prefix web
  run_step "Web app unit tests" npm test --prefix web
  run_step "Web app build" npm run build --prefix web
  if [ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ] && ls "${PLAYWRIGHT_BROWSERS_PATH}"/chromium-* >/dev/null 2>&1; then
    run_step "Backend build for the web end-to-end run" npm run build --prefix backend
    run_step "Web end-to-end (backend + Chromium)" npm run e2e --prefix web
  else
    record "Web end-to-end (backend + Chromium)" "SKIPPED" "no Playwright Chromium (PLAYWRIGHT_BROWSERS_PATH)"
  fi
else
  not_run "Web app tests" "node/npm not found on PATH"
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

# Project secrets in 1Password (ADR-493): the manifest, the generated .env.op templates (references
# only) and the sync tool, against a fake `op` and fake Vercel/Render APIs. No network, no values.
if command -v node >/dev/null 2>&1; then
  run_step "Secrets manifest and .env.op templates" node tools/secrets/sync.mjs check
  run_step "Secrets sync tool tests (fake op and hosts)" node --test "tools/secrets/test/*.test.mjs"
else
  not_run "Secrets manifest and sync tool" "node not found on PATH"
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
    # Build once, then run the unit tests and the UI tests as two passes, with the simulator
    # restarted in between (ADR-561). The unit tests run inside the app on the simulator; right
    # after them its first launches are slow, and on 20 Oct (run 39496321722) XCTest could not take
    # hold of the app for three minutes, so the first 12 UI tests failed before any test code ran.
    # Keep compiling the other targets after the first error, so one run lists every compile
    # error instead of stopping at the first target that fails (owner request, 2026-10-12).
    if run_step "xcodebuild build-for-testing" xcodebuild build-for-testing -project Doddy.xcodeproj -scheme Doddy \
      -destination "$dest" -IDEBuildingContinueBuildingAfterErrors=YES; then
      run_step "xcodebuild test: unit tests" xcodebuild test-without-building -project Doddy.xcodeproj -scheme Doddy \
        -destination "$dest" -only-testing:DoddyTests
      # Only when this script picked the simulator: a DODDY_DESTINATION may name one by name.
      if [ -n "${sim_id:-}" ]; then
        run_step "Restart the simulator before the UI tests" restart_simulator "$sim_id"
      fi
      run_step "xcodebuild test: UI tests" xcodebuild test-without-building -project Doddy.xcodeproj -scheme Doddy \
        -destination "$dest" -only-testing:DoddyUITests
    else
      not_run "xcodebuild test (unit + UI)" "the build for testing failed"
    fi
  fi
fi

echo; echo "================ SUMMARY"
for r in "${results[@]}"; do IFS='|' read -r n s d <<<"$r"; printf '%-8s %s %s\n' "$s" "$n" "${d:+($d)}"; done
if [ "$failed" -ne 0 ]; then echo "RESULT: FAIL"; exit 1; fi
if [ "$blocked" -ne 0 ]; then echo "RESULT: BLOCKED (a required step could not run)"; exit 2; fi
if [ "$core_only" -eq 1 ]; then echo "RESULT: PASS for core-only scope; iOS app NOT verified"; exit 0; fi
echo "RESULT: PASS"

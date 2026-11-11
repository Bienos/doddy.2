#!/usr/bin/env bash
# DODDY V2 — M0 check script. Fails honestly: a step that cannot run is reported NOT RUN and
# makes the script exit non-zero, so "green" always means everything ran and passed.
#
#   scripts/ci.sh              full run (needs Swift AND Xcode/xcodebuild)
#   scripts/ci.sh --core-only  pack integrity + guards + Swift package tests + Node services only
#                              (on Linux also a type-check of the non-UI app files);
#                              the iOS app build and tests are reported NOT RUN (exit 0
#                              only if everything that was requested passed)
#   scripts/ci.sh --app-only   Swift package and iOS build/unit/UI tests; Linux checks SKIPPED (ADR-680)
#   scripts/ci.sh --only a,b   only these groups (hosted Linux jobs run one group each, in parallel):
#                              checks swift backend node messaging ios
#                              `ios` is the Xcode build and tests; --only never includes it unless listed.
set -uo pipefail
cd "$(dirname "$0")/.."

core_only=0 app_only=0 only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --core-only) core_only=1 ;;
    --app-only) app_only=1 ;;
    --only)
      [ -n "${2:-}" ] || { echo "--only needs a comma-separated list of groups" >&2; exit 64; }
      only=$2; shift ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
  shift
done
if [ "$app_only" -eq 1 ] && { [ "$core_only" -eq 1 ] || [ -n "$only" ]; }; then
  echo "--app-only cannot be combined with other scope flags" >&2; exit 64
fi
if [ "$core_only" -eq 1 ] && [ -n "$only" ]; then
  echo "--core-only cannot be combined with --only" >&2; exit 64
fi
if [ -n "$only" ]; then
  case ",$only," in *,ios,*) ;; *) core_only=1 ;; esac
  case "$only" in ,*|*,|*,,*|*[!a-z,]*) echo "empty group in --only" >&2; exit 64 ;; esac
  for g in $(echo "$only" | tr ',' ' '); do
    case "$g" in checks|swift|backend|node|messaging|ios) ;; *) echo "unknown group: $g" >&2; exit 64 ;; esac
  done
fi
# want GROUP: does this run include the group? (bash 3.2: no associative arrays)
want() {
  if [ "$app_only" -eq 1 ]; then
    case "$1" in swift|ios) ;; *) return 1 ;; esac
  fi
  [ -z "$only" ] && return 0
  case ",$only," in *",$1,"*) return 0 ;; esac
  return 1
}

declare -a results=()
failed=0 blocked=0
record() { results+=("$1|$2|$3"); }
run_step() {  # name, command...
  local name=$1; shift
  echo; echo "=== $name"; echo "\$ $*"
  if "$@"; then record "$name" PASS ""; else record "$name" FAIL "exit $?"; failed=1; return 1; fi
}
not_run() { record "$1" "NOT RUN" "$2"; blocked=1; echo; echo "=== $1"; echo "NOT RUN: $2"; }
# The app's package pins (Config/Package.resolved, 7 Nov 2026 audit). Xcode writes this file when it
# resolves packages; `xcodebuild -list` does not (run 42409624440: "wrote no Package.resolved", and the
# step logged NOT RUN, which blocked an otherwise green job). After `-resolvePackageDependencies` it
# still wrote nothing in the project's own folder (Xcode 26.6, run 42416065085), though the log listed
# every resolved package, so look in the other places too and take the first file that names LiveKit
# (DoddyCore's own Package.resolved doesn't). Every file found is printed, so the next run says where.
resolved_in_project=Doddy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
derived_data=${DODDY_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}
find_resolved_pins() {
  local f
  if [ -f "$resolved_in_project" ]; then echo "$resolved_in_project"; return 0; fi
  while IFS= read -r f; do
    echo "Package.resolved candidate: $f" >&2
    if grep -qi 'livekit' "$f" 2>/dev/null; then echo "$f"; return 0; fi
  done < <(find Doddy.xcodeproj "$derived_data" -name Package.resolved -not -path '*/checkouts/*' 2>/dev/null)
  return 1
}
# Copies the file Xcode resolved to build/Package.resolved (hosted CI keeps it, so pinning or moving
# versions is one download). With pins committed, any difference fails: the build would not be the one
# TestFlight gets. Returns 1, recording nothing, when Xcode has not written the file (yet).
check_package_pins() {
  local src
  src=$(find_resolved_pins) || return 1
  echo "App packages were pinned in: $src"
  mkdir -p build
  cp "$src" build/Package.resolved
  if [ ! -f Config/Package.resolved ]; then
    record "App package versions match Config/Package.resolved" "SKIPPED" \
      "no pins committed yet: commit build/Package.resolved from this run as Config/Package.resolved"
  elif cmp -s Config/Package.resolved "$src"; then
    record "App package versions match Config/Package.resolved" PASS ""
  else
    diff -u Config/Package.resolved "$src" || true
    record "App package versions match Config/Package.resolved" FAIL \
      "resolution changed the pins; if that was meant, run make update-packages on a Mac and commit it"
    failed=1
  fi
}
# Nothing to check or copy after Xcode resolved. With pins committed the guard could not run, which
# blocks. Without pins there is nothing to guard and nothing to block on: say so and carry on.
pins_not_found() {
  if [ -f Config/Package.resolved ]; then
    not_run "App package versions match Config/Package.resolved" "no Package.resolved naming LiveKit in $resolved_in_project, Doddy.xcodeproj or DerivedData, so the pins could not be checked"
  else
    record "App package versions match Config/Package.resolved" "SKIPPED" \
      "no pins committed yet, and no Package.resolved naming LiveKit was found in $resolved_in_project, Doddy.xcodeproj or DerivedData to copy"
  fi
}
# Shut a simulator down and boot it again, waiting until it has finished booting (ADR-561).
restart_simulator() {
  xcrun simctl shutdown "$1" 2>/dev/null || true  # fails harmlessly if it is already shut down
  xcrun simctl bootstatus "$1" -b                 # -b boots it first, then waits for the boot
}
# Runs a command again when it failed because a download failed (8 Nov 2026: github.com release
# downloads of the LiveKit binary frameworks answered 504 on hosted runs 42465092351 and others, so
# `xcodebuild` could not resolve packages and exited 74). It retries only when the output names a failed
# download or connection, never for any other error, and still fails with the last exit code once
# CI_FETCH_TRIES (default 4) attempts are used; between attempts it waits CI_FETCH_WAIT s (default 30)
# times the attempt number. Nothing is skipped and nothing is treated as passed that did not pass.
with_fetch_retries() {  # command...
  local tries=${CI_FETCH_TRIES:-4} wait_s=${CI_FETCH_WAIT:-30} n=1 rc out
  out=$(mktemp)
  while :; do
    "$@" 2>&1 | tee "$out"
    rc=${PIPESTATUS[0]}
    [ "$rc" -eq 0 ] && break
    [ "$n" -ge "$tries" ] && break
    grep -qE 'failed downloading|badResponseStatusCode|Could not connect|timed out|connection was lost|Internet connection appears to be offline|Could not resolve host' "$out" || break
    echo "A download failed (attempt $n of $tries); trying again in $((wait_s * n)) s."
    sleep $((wait_s * n))
    n=$((n + 1))
  done
  rm -f "$out"
  return "$rc"
}
# Runs a command and stops it if it is still running after $1 seconds (ADR-764). For a simulator
# whose drawing has frozen: xcodebuild then waits for ever on an app launch that never returns.
with_watchdog() {  # seconds, command...
  local limit=$1; shift
  "$@" &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
      echo "WATCHDOG: still running after ${limit} s, stopping it (the simulator has most likely frozen, ADR-764)"
      kill -TERM "$pid" 2>/dev/null || true
      sleep 15
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 5
    waited=$((waited + 5))
  done
  wait "$pid"
}

if [ "$app_only" -eq 1 ]; then
  record "Pack, guard, agent spec, page and catalog checks" "SKIPPED" "--app-only: Linux core runs them"
  record "Token server, backend, gateway, web, messaging, site and secrets checks" "SKIPPED" "--app-only: Linux core runs them"
fi

if want checks; then
run_step "Imported pack integrity" python3 -I scripts/verify_imported_pack.py
run_step "Forbidden-capability guard" scripts/check_forbidden_capabilities.sh
run_step "Voice agent spec" python3 -I scripts/voice_agent_spec.py check
run_step "Phone agent spec" python3 -I scripts/voice_agent_spec.py check --agent phone
run_step "Task-call agent spec" python3 -I scripts/voice_agent_spec.py check --agent task-call
run_step "Blog pages up to date" python3 -I tools/build_blog.py --check
run_step "Site pages in every language up to date" python3 -I tools/build_site_i18n.py --check
run_step "String catalogs up to date" python3 -I tools/build_strings_catalog.py --check
run_step "What-can-doddy-do page up to date" python3 -I tools/build_day.py --check
# Doddy Studio's skills (STUDIO.md): frontmatter limits and no unlisted font or image files (plain
# Python), then both renderers on the samples with every output checked the way the server checks it.
run_step "Studio skills: frontmatter and files" scripts/studio_skills.sh check-files
if python3 -I -c "import reportlab, matplotlib" 2>/dev/null; then
  run_step "Studio skills: renderers on samples" scripts/studio_skills.sh check
else
  not_run "Studio skills: renderers on samples" "python3 needs reportlab and matplotlib (apt python3-reportlab python3-matplotlib, or pip)"
fi
run_step "Screen fixture data up to date (ADR-821)" python3 -I scripts/gen_screen_fixture_data.py --check
run_step "Web app tokens and brand files match the app (ADR-600)" python3 -I tools/gen_web_assets.py --check
run_step "Site colour tokens match the app" python3 -I tools/gen_site_tokens.py --check
run_step "One scripts/regen.sh run brings every generated file up to date" scripts/test_regen.sh
run_step "Which pull requests need the macOS build (ADR-497)" scripts/test_ci_needs_mac.sh
run_step "Binary packages' dSYMs into the archive (ADR-693)" scripts/test_copy_binary_dsyms.sh
run_step "Xcode Cloud post-clone script (ADR-697)" scripts/test_xcode_cloud_post_clone.sh
run_step "Which pull requests need which Linux groups (ADR-684)" scripts/test_ci_groups.sh
run_step "Ubuntu CI dependency mirror fallback" scripts/test_ci_install_ubuntu_packages.sh
run_step "Which pull requests need the owner's label (ADR-811)" scripts/test_check_sensitive_paths.sh
run_step "Vercel builds a project whenever it can't tell nothing changed (9 Nov 2026)" scripts/test_vercel_ignore_command.sh
run_step "Which Vercel statuses are replaced on pull requests (decision 2026-11-09-vercel-blocked-status)" scripts/test_vercel_blocked_status.sh
run_step "Privacy manifest declares every required-reason API (7 Nov audit)" scripts/test_check_privacy_manifest.sh
run_step "The Mac job's package-pin step never blocks without pins (7 Nov audit)" scripts/test_ci_package_pins.sh
if python3 -I -c "import yaml" 2>/dev/null; then
  run_step "Per-platform Xcode specs in step" python3 -I scripts/check_platform_specs.py
else
  not_run "Per-platform Xcode specs in step" "PyYAML not installed (apt install python3-yaml or pip install pyyaml)"
fi
fi  # checks

if ! want swift; then :
elif command -v swift >/dev/null 2>&1; then
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
    # The price watch's state, run with a fake for Doddy's server (SHOPPING_WATCH.md).
    run_step "Price watch state tests" scripts/test_watch_model.sh
    # The "Na oku" page's state, run with a fake provider (ADR-756).
    run_step "Open loops page state tests" scripts/test_open_loops_model.sh
    run_step "Unfinished notes on real files" scripts/check_unfinished_note_store.sh
    # The kept training plan (ADR-625): read back, edited and unreadable files, delete.
    run_step "Training plan on real files" scripts/check_training_plan_store.sh
    # The training log's state (ADR-642), run with a fake store.
    run_step "Training log screen's state tests" scripts/test_training_log_model.sh
  else
    run_step "Swift package tests (DoddyCore)" swift test --package-path Packages/DoddyCore
  fi
  # Island drawing data matches the owner's SVGs, parses, and maps states correctly (ADR-239).
  if [ "$app_only" -eq 1 ]; then
    record "Dynamic Island art and scenes" "SKIPPED" "--app-only: Linux core runs them"
  else
    run_step "Dynamic Island art and scenes" scripts/check_island_art.sh
  fi
else
  not_run "Swift package tests (DoddyCore)" "swift not found on PATH"
fi

if ! want node; then :
elif command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  run_step "Voice token server tests" npm test --prefix server/voice-token
else
  not_run "Voice token server tests" "node/npm not found on PATH"
fi
if ! want backend; then :
elif command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  node --version
  if [ ! -d backend/node_modules ]; then run_step "Backend install (npm ci)" npm ci --prefix backend; fi
  run_step "Backend type-check" npm run --prefix backend typecheck
  run_step "Backend tests (offline, mock + fake Composio)" npm test --prefix backend
else
  not_run "Backend type-check + tests" "node/npm not found on PATH"
fi
if ! want node; then :
elif command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  if [ ! -d gateway/node_modules ]; then run_step "Gateway install (npm ci)" npm ci --prefix gateway; fi
  run_step "Gateway typecheck" npm run typecheck --prefix gateway
  run_step "Gateway tests (node)" npm test --prefix gateway
else
  not_run "Gateway tests (node)" "node/npm not found on PATH"
fi

# Doddy Web (web/, ADR-600): type-check, unit tests against the server's own fixtures, and the
# production build. The end-to-end run (real backend + Chromium) needs a Playwright Chromium; where
# there is none it is listed as SKIPPED, never PASS.
if ! want node; then :
elif command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  if [ ! -d web/node_modules ]; then run_step "Web app install (npm ci)" npm ci --prefix web --no-audit --no-fund; fi
  run_step "Web app type-check" npm run typecheck --prefix web
  run_step "Web app unit tests" npm test --prefix web
  run_step "Web app build" npm run build --prefix web
  if [ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ] && [ -d backend/node_modules ] && ls "${PLAYWRIGHT_BROWSERS_PATH}"/chromium-* >/dev/null 2>&1; then
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
if ! want messaging; then :
elif command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  if [ ! -d server/messaging/node_modules ]; then run_step "Messaging server install (npm ci)" npm ci --prefix server/messaging --no-audit --no-fund; fi
  run_step "Messaging server typecheck + tests" npm test --prefix server/messaging
  # Studio (ADR-740): the server's checks on files the real renderers make (needs the build above).
  if python3 -I -c "import reportlab, matplotlib" 2>/dev/null; then
    run_step "Studio: server checks on rendered samples" scripts/check_studio_crosscheck.sh
  else
    not_run "Studio: server checks on rendered samples" "python3 needs reportlab and matplotlib"
  fi
  [ -z "${TEST_DATABASE_URL:-}" ] && record "Messaging server database tests" "SKIPPED" "TEST_DATABASE_URL not set"
else
  not_run "Messaging server tests" "node/npm not found on PATH"
fi

# Landing page waitlist functions (site/api), against an in-memory @vercel/blob stand-in; no network.
if ! want node; then :
elif command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  if [ ! -d site/node_modules ]; then run_step "Site install (npm ci)" npm ci --prefix site --no-audit --no-fund; fi
  run_step "Site waitlist function tests" npm test --prefix site
else
  not_run "Site waitlist function tests" "node/npm not found on PATH"
fi

# Project secrets in 1Password (ADR-493): the manifest, the generated .env.op templates (references
# only) and the sync tool, against a fake `op` and fake Vercel/Render APIs. No network, no values.
if ! want node; then :
elif command -v node >/dev/null 2>&1; then
  run_step "Secrets manifest and .env.op templates" node tools/secrets/sync.mjs check
  run_step "Secrets sync tool tests (fake op and hosts)" node --test "tools/secrets/test/*.test.mjs"
else
  not_run "Secrets manifest and sync tool" "node not found on PATH"
fi

if ! want ios; then :
elif [ "$core_only" -eq 1 ]; then
  record "iOS app build + tests" "NOT RUN" "--core-only requested"
elif ! command -v xcodebuild >/dev/null 2>&1; then
  not_run "iOS app build + tests" "xcodebuild not found (needs macOS with Xcode)"
elif ! command -v xcodegen >/dev/null 2>&1; then
  not_run "iOS app build + tests" "xcodegen not found (brew install xcodegen)"
else
  run_step "Generate Xcode project" xcodegen generate --spec project.yml
  # The app's pinned package versions (Config/Package.resolved, 7 Nov 2026 audit): installed into the
  # generated project before anything resolves, and checked once Xcode has resolved (check_package_pins).
  run_step "Install the pinned package versions" scripts/install_package_resolved.sh Doddy.xcodeproj
  pins_checked=0
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
    # Resolve the packages first, and again when a download fails (with_fetch_retries): `-list` also
    # resolves, so before this a single failed download failed all three steps. A failure to fetch
    # a package still stops the run before the long build, and the pins can be checked now. If Xcode
    # still wrote no file, the check is tried again after the build, which resolves too.
    # build/packages-ok: every package resolved and downloaded, so hosted CI may save them as its cache.
    mkdir -p build; rm -f build/packages-ok
    if run_step "Resolve the app's packages" with_fetch_retries xcodebuild -resolvePackageDependencies -project Doddy.xcodeproj -scheme Doddy; then
      touch build/packages-ok
    fi
    run_step "xcodebuild -list" xcodebuild -list -project Doddy.xcodeproj
    if check_package_pins; then pins_checked=1; fi
    # Build once, then run the unit tests and the UI tests as two passes, with the simulator
    # restarted in between (ADR-561). The unit tests run inside the app on the simulator; right
    # after them its first launches are slow, and on 20 Oct (run 39496321722) XCTest could not take
    # hold of the app for three minutes, so the first 12 UI tests failed before any test code ran.
    # Keep compiling the other targets after the first error, so one run lists every compile
    # error instead of stopping at the first target that fails (owner request, 2026-10-12).
    if run_step "xcodebuild build-for-testing" xcodebuild build-for-testing -project Doddy.xcodeproj -scheme Doddy \
      -destination "$dest" -IDEBuildingContinueBuildingAfterErrors=YES; then
      # A per-test time limit (ADR-680): a test that hangs fails after 10 minutes instead of using
      # up the job (on 2 Nov one waited 49 minutes for the app to close, run 41368047283). The
      # longest UI test takes about 290 s, so 600 s only ends a test that is stuck.
      test_limits="-test-timeouts-enabled YES -default-test-execution-time-allowance 600"
      # shellcheck disable=SC2086
      run_step "xcodebuild test: unit tests" xcodebuild test-without-building -project Doddy.xcodeproj -scheme Doddy \
        -destination "$dest" -only-testing:DoddyTests $test_limits
      # Only when this script picked the simulator: a DODDY_DESTINATION may name one by name.
      if [ -n "${sim_id:-}" ]; then
        run_step "Restart the simulator before the UI tests" restart_simulator "$sim_id"
      fi
      # The native island test runs on its own, last (ADR-764). Twice (2 Nov, run 41368047283; 7 Nov,
      # run 42381695855) the hosted simulator's drawing froze right after it tapped a button on the
      # system's island: backboardd waited on a GPU command that never finished, SpringBoard waited
      # on backboardd, the tap never reached the app, and every later test failed to launch the app
      # until the job's 75 minutes ran out. On its own, a freeze costs only this test.
      island_test="DoddyUITests/MemoryBaselineTests/testNativeIslandOfflineFixtureCanStartMuteAndEnd"
      # DODDY_UI_TESTS=smoke (ADR-811; hosted CI sets it on pull requests): only the smoke classes,
      # about 8 of the full suite's 27 minutes on 7 Nov 2026 (run 42370455942: the motion, art and
      # memory-journey classes took about 20). Every push to main runs the whole suite and the native
      # island test, so a pull request learns of those a merge later. Anything else, or unset: all.
      if [ "${DODDY_UI_TESTS:-all}" = "smoke" ]; then
        ui_scope="smoke"
        ui_tests="-only-testing:DoddyUITests/LaunchSmokeTests -only-testing:DoddyUITests/WelcomeUITests"
        ui_tests="$ui_tests -only-testing:DoddyUITests/LegalAcceptanceUITests -only-testing:DoddyUITests/PolishSmokeTests"
        ui_label="UI smoke tests"
      else
        ui_scope="all"
        ui_tests="-only-testing:DoddyUITests -skip-testing:$island_test"
        ui_label="UI tests"
      fi
      # DODDY_UI_TEST_WORKERS > 1 (ADR-680): xcodebuild clones the simulator and hands each clone
      # whole test classes, so the UI tests run side by side. Each clone starts fresh, as ADR-561
      # wants. Every test still runs once. Not used in CI: the hosted Mac was too small for two.
      ui_workers=${DODDY_UI_TEST_WORKERS:-1}
      if [ "$ui_workers" -gt 1 ] 2>/dev/null; then
        # shellcheck disable=SC2086
        run_step "xcodebuild test: $ui_label ($ui_workers simulators)" xcodebuild test-without-building \
          -project Doddy.xcodeproj -scheme Doddy -destination "$dest" $ui_tests \
          -parallel-testing-enabled YES -parallel-testing-worker-count "$ui_workers" $test_limits
      else
        # shellcheck disable=SC2086
        run_step "xcodebuild test: $ui_label" xcodebuild test-without-building -project Doddy.xcodeproj -scheme Doddy \
          -destination "$dest" $ui_tests $test_limits
      fi
      if [ "$ui_scope" = "smoke" ]; then
        record "xcodebuild test: native island test" "SKIPPED" "UI smoke run (DODDY_UI_TESTS=smoke); every push to main runs it"
      else
        if [ -n "${sim_id:-}" ]; then
          run_step "Restart the simulator before the native island test" restart_simulator "$sim_id"
        fi
        # The test takes under a minute; 3 minutes ends it if it hangs. The watchdog ends the whole
        # pass after 8 (runner start about 70 s, the test, and the spindump XCTest takes on a hang),
        # where a frozen simulator would otherwise hold xcodebuild until the job's limit.
        run_step "xcodebuild test: native island test (alone, 8-minute watchdog)" with_watchdog 480 \
          xcodebuild test-without-building -project Doddy.xcodeproj -scheme Doddy -destination "$dest" \
          -only-testing:"$island_test" -test-timeouts-enabled YES -default-test-execution-time-allowance 180
      fi
    else
      not_run "xcodebuild test (unit + UI)" "the build for testing failed"
    fi
    if [ "$pins_checked" -eq 0 ]; then check_package_pins || pins_not_found; fi
    # DODDY_RELEASE_BUILD=1 (hosted CI on pushes to main): compile the Release configuration for
    # devices, unsigned. Everything above is a Debug simulator build; without this, Xcode Cloud's
    # archive was the first Release compile, where a failure costs build hours and a TestFlight build.
    if [ "${DODDY_RELEASE_BUILD:-0}" = "1" ]; then
      run_step "xcodebuild build: Release, generic iOS device, unsigned" xcodebuild build -project Doddy.xcodeproj \
        -scheme Doddy -configuration Release -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO \
        -IDEBuildingContinueBuildingAfterErrors=YES
    fi
  fi
fi

echo; echo "================ SUMMARY"
for r in "${results[@]}"; do IFS='|' read -r n s d <<<"$r"; printf '%-8s %s %s\n' "$s" "$n" "${d:+($d)}"; done
if [ "$failed" -ne 0 ]; then echo "RESULT: FAIL"; exit 1; fi
if [ "$blocked" -ne 0 ]; then echo "RESULT: BLOCKED (a required step could not run)"; exit 2; fi
if [ -n "$only" ]; then
  case ",$only," in
    *,ios,*) echo "RESULT: PASS for groups: $only" ;;
    *) echo "RESULT: PASS for groups: $only; iOS app NOT verified" ;;
  esac
  exit 0
fi
if [ "$core_only" -eq 1 ]; then echo "RESULT: PASS for core-only scope; iOS app NOT verified"; exit 0; fi
if [ "$app_only" -eq 1 ]; then echo "RESULT: PASS for app-only scope; the Linux job (core) runs the other checks"; exit 0; fi
echo "RESULT: PASS"

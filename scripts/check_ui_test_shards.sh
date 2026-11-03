#!/usr/bin/env bash
# Checks the UI test split in scripts/ui_test_shards.sh (ADR-687): every listed class exists in
# DoddyUITests, none is listed twice, and the classes left for the `ui-c` catch-all are printed.
# Runs on Linux (no Xcode): it reads the Swift sources.
set -uo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/ui_test_shards.sh
. scripts/ui_test_shards.sh

fail=0
all=$(grep -hoE '^(final )?class [A-Za-z0-9_]+: XCTestCase' DoddyUITests/*.swift | sed -E 's/^(final )?class ([A-Za-z0-9_]+):.*/\2/' | sort)
[ -n "$all" ] || { echo "FAIL: found no XCTestCase classes in DoddyUITests"; exit 1; }

listed=""
for c in $UI_SHARD_A $UI_SHARD_B; do
  if ! printf '%s\n' "$all" | grep -qx "$c"; then echo "FAIL: $c is in a shard list but is not a class in DoddyUITests"; fail=1; fi
  case " $listed " in *" $c "*) echo "FAIL: $c is listed twice"; fail=1 ;; esac
  listed="$listed $c"
done
[ -n "$UI_SHARD_A" ] && [ -n "$UI_SHARD_B" ] || { echo "FAIL: UI_SHARD_A and UI_SHARD_B must not be empty"; fail=1; }

rest=""
for c in $all; do case " $listed " in *" $c "*) ;; *) rest="$rest $c" ;; esac; done
echo "ui-a:$(printf ' %s' $UI_SHARD_A)"
echo "ui-b:$(printf ' %s' $UI_SHARD_B)"
echo "ui-c (the rest):${rest:- NONE}"
[ -n "$rest" ] || { echo "FAIL: ui-c would run no tests"; fail=1; }

# The classes that drive the real Live Activity in SpringBoard need a warm simulator (a cold
# widget-extension launch failed two of them as the first test on a fresh Mac, see
# scripts/ui_test_shards.sh). Find every such class from the sources, so a new one can't be missed.
found=""
for f in DoddyUITests/*.swift; do
  if grep -qi 'springboard' "$f"; then
    for c in $(grep -hoE '^(final )?class [A-Za-z0-9_]+: XCTestCase' "$f" | sed -E 's/^(final )?class ([A-Za-z0-9_]+):.*/\2/'); do found="$found $c"; done
  fi
done
for c in $found; do
  case " $UI_SPRINGBOARD_CLASSES " in *" $c "*) ;; *) echo "FAIL: $c uses SpringBoard but is not in UI_SPRINGBOARD_CLASSES"; fail=1 ;; esac
done
for c in $UI_SPRINGBOARD_CLASSES; do
  printf '%s\n' "$all" | grep -qx "$c" || { echo "FAIL: $c is in UI_SPRINGBOARD_CLASSES but is not a class in DoddyUITests"; fail=1; }
done

# The warm-up test (UI_WARMUP_TEST, "Class/testName") must be a real test, or the warm-up would run
# nothing and its ignored result would hide that.
wclass=${UI_WARMUP_TEST%%/*}; wtest=${UI_WARMUP_TEST#*/}
if ! grep -qE "^(final )?class $wclass: XCTestCase" DoddyUITests/*.swift \
  || ! grep -hE "func $wtest\(" $(grep -lE "^(final )?class $wclass: XCTestCase" DoddyUITests/*.swift) >/dev/null 2>&1; then
  echo "FAIL: UI_WARMUP_TEST $UI_WARMUP_TEST is not a test in DoddyUITests"; fail=1
fi

# xcodebuild runs a part's classes in alphabetical order, so no part may start with one of them.
for part in "ui-a:$UI_SHARD_A" "ui-b:$UI_SHARD_B" "ui-c:$rest"; do
  name=${part%%:*}; first=$(printf '%s\n' ${part#*:} | sort | head -1)
  case " $UI_SPRINGBOARD_CLASSES " in
    *" $first "*) echo "FAIL: $name would start with $first, a SpringBoard test that needs other tests to run before it"; fail=1 ;;
  esac
done
[ "$fail" -eq 0 ] && echo "ok: $(printf '%s\n' "$all" | wc -l | tr -d ' ') UI test classes, each run in exactly one part"
exit "$fail"

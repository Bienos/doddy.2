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

# xcodebuild runs a part's classes in alphabetical order. MemoryBaselineTests' island test needs a
# warm simulator (a cold widget-extension launch failed it twice as the first test, see
# scripts/ui_test_shards.sh), so no part may start with it.
for part in "ui-a:$UI_SHARD_A" "ui-b:$UI_SHARD_B" "ui-c:$rest"; do
  name=${part%%:*}; first=$(printf '%s\n' ${part#*:} | sort | head -1)
  if [ "$first" = "MemoryBaselineTests" ]; then
    echo "FAIL: $name would start with MemoryBaselineTests; it needs other tests to run before it"; fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "ok: $(printf '%s\n' "$all" | wc -l | tr -d ' ') UI test classes, each run in exactly one part"
exit "$fail"

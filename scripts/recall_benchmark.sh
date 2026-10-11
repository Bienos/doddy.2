#!/usr/bin/env bash
# Recall benchmark (OP-016 / OP-008, ADR-249). Runs RecallBenchmarkTests against the real SQLite
# store and writes docs/quality/RECALL_BENCHMARK.md.
#
#   scripts/recall_benchmark.sh                     check against the baseline, write the report
#   scripts/recall_benchmark.sh --update-baseline   also rewrite docs/quality/evals/recall_baseline_v1.json
#                                                   (do this only on purpose, after an improvement or a
#                                                   corpus change, and commit the report with it)
set -euo pipefail
cd "$(dirname "$0")/.."

export DODDY_RECALL_REPORT="$PWD/docs/quality/RECALL_BENCHMARK.md"
if [ "${1:-}" = "--update-baseline" ]; then export DODDY_RECALL_UPDATE_BASELINE=1; fi

flags=()
# Ubuntu's system SQLite lacks the snapshot API GRDB enables by default (same as scripts/ci.sh).
# --allow-shlib-undefined: see scripts/ci.sh (swift-crypto in the Linux test link, ADR-222).
if [ "$(uname)" = "Linux" ]; then flags=(-Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined); fi
swift test --package-path Packages/DoddyCore ${flags[@]+"${flags[@]}"} --filter RecallBenchmarkTests
echo "Report: docs/quality/RECALL_BENCHMARK.md"

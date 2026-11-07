#!/usr/bin/env bash
# Tests for scripts/ci_groups.sh (ADR-684): which Linux check groups a pull request needs.
# The costly mistake is skipping a group for a change that reaches it, so most cases are those.
set -uo pipefail
cd "$(dirname "$0")/.."

failures=0
expect() {  # expected "swift backend node messaging" as t/f letters, description, changed paths...
  local want=$1 what=$2; shift 2
  local out got
  out=$(printf '%s\n' "$@" | scripts/ci_groups.sh 2>/dev/null)
  got=$(printf '%s\n' "$out" | sed -E 's/^[a-z]+=true$/t/; s/^[a-z]+=false$/f/' | tr '\n' ' ' | sed 's/ $//')
  if [ "$got" = "$want" ]; then echo "ok    $want  $what"; else echo "FAIL  wanted '$want', got '$got': $what"; failures=$((failures + 1)); fi
}
#                                  swift backend node messaging
expect "t f f f" "recall benchmark fixtures" docs/quality/evals/recall_golden_v1.json
expect "t f f f" "docs include runtime test fixtures" docs/a.md STATUS.md DECISIONS.md prompts/x.md
expect "f f f f" "agent notes inside code folders" DoddyApp/CLAUDE.md backend/AGENTS.md
expect "f f f f" "per-pull-request change notes" changes/ui-smoke.md changes/README.md
expect "f f f f" "paused Watch and Mac apps" DoddyWatch/A.swift DoddyMac/B.swift project-mac.yml
expect "t f f f" "design includes motion test fixtures" design/a.svg l10n/pl.json blog/p.md
expect "t f f f" "app source" DoddyApp/Features/Voice/VoiceView.swift
expect "t f f f" "the shared package" Packages/DoddyCore/Sources/DoddyCore/A.swift
expect "t t t f" "backend source (Swift tool-catalog and Node secrets checks read it too)" backend/src/a.ts
expect "f f t f" "web app" web/src/App.tsx
expect "f f t f" "site" site/api/join.js
expect "f f t f" "gateway" gateway/api/b.js
expect "f f t t" "messaging server and secrets templates" server/messaging/src/index.ts
expect "f f t f" "voice token server" server/voice-token/src/a.js
expect "t t t t" "contracts shared by Swift, backend, web and messaging" contracts/web/link-code.json
expect "t t f t" "voice agent files read by Swift and backend tests" voice-agent/tools.json
expect "t f t f" "app and web together" DoddyApp/A.swift web/src/B.ts
expect "t t t t" "the check script itself" scripts/ci.sh
expect "t t t t" "the workflow" .github/workflows/ios.yml
expect "t t t t" "a generator" tools/build_blog.py
expect "t t t t" "a folder nobody listed yet" newthing/file.txt
expect "t t t t" "a top-level file nobody listed" Makefile
expect "t t t t" "one unknown path among many docs" docs/a.md STATUS.md weird/x.bin
expect "t t t t" "a server folder nobody listed" server/other/a.ts
expect "t t t t" "no files listed at all"
expect "t f f f" "blank lines are ignored" "" docs/a.md ""

if [ "$failures" -ne 0 ]; then echo "$failures case(s) failed"; exit 1; fi
echo "all cases pass"

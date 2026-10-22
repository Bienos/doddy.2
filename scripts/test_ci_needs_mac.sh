#!/usr/bin/env bash
# Tests for scripts/ci_needs_mac.sh (ADR-497): which pull requests need the hosted macOS build.
# The costly mistake is skipping the Mac for a change that reaches the app, so most cases are those.
set -uo pipefail
cd "$(dirname "$0")/.."

failures=0
expect() {  # expected (true|false), description, changed paths...
  local want=$1 what=$2; shift 2
  local got
  got=$(printf '%s\n' "$@" | scripts/ci_needs_mac.sh 2>/dev/null)
  if [ "$got" = "mac=$want" ]; then
    echo "ok    mac=$want  $what"
  else
    echo "FAIL  wanted mac=$want, got '${got}': $what"
    failures=$((failures + 1))
  fi
}

# Changes that reach the app build or its tests: the Mac runs.
expect true "app source" DoddyApp/Features/Voice/VoiceView.swift
expect true "shared source" Shared/IslandArt/IslandPose.swift
expect true "shared package" Packages/DoddyCore/Sources/DoddyCore/VoiceConversationGate.swift
expect true "widget and share targets" DoddyWidgets/A.swift DoddyShare/B.swift
expect true "unit and UI tests" DoddyTests/X.swift DoddyUITests/Y.swift
expect true "Info.plist and entitlements" Config/Doddy-Info.plist
expect true "an Xcode spec" project-iphone.yml
expect true "the Makefile" Makefile
expect true "voice prompt bundled in the app" voice-agent/instructions.md
expect true "voice tools bundled in the app" voice-agent/tools.json
expect true "voice session bundled in the app" voice-agent/session.json
expect true "the workflow itself" .github/workflows/ios.yml
expect true "the check script the Mac runs" scripts/ci.sh
expect true "a generator the Mac runs" tools/build_strings_catalog.py
expect true "a Markdown file inside the app folder" DoddyApp/README.md
expect true "a folder nobody listed yet" newthing/file.txt
expect true "a top-level file nobody listed yet" Brewfile
expect true "one app file among many docs" docs/a.md STATUS.md Shared/x.swift DECISIONS.md
expect true "a deleted app file (listed under its old path)" DoddyApp/Old.swift docs/new-home.md
expect true "no files listed at all"

# Changes that can't reach the app: the Mac is skipped.
expect false "docs only" docs/implementation/VOICE_SESSION_STARTS.md
expect false "top-level notes" STATUS.md DECISIONS.md README.md BUILD_AND_TEST.md
expect false "agent notes in app folders" DoddyApp/CLAUDE.md Packages/DoddyCore/CLAUDE.md
expect false "servers and site" server/messaging/src/index.ts backend/src/a.ts gateway/api/b.js site/index.html
expect false "secrets manifest and env templates" secrets/manifest.json backend/.env.op
expect false "voice agent notes that aren't bundled" voice-agent/README.md voice-agent/phone/instructions.md
expect false "paused Watch and Mac apps (ADR-572)" DoddyWatch/A.swift DoddyWatchWidgets/B.swift DoddyMac/C.swift DoddyMacWidgets/D.swift Config/DoddyWatch.entitlements Config/DoddyMac-Info.plist project-watch.yml project-mac.yml
expect true "the Watch app's neighbours still run it" DoddyWatch/A.swift DoddyApp/Features/Watch/PhoneWatchLink.swift
expect true "the shared widget file the Watch also reads" Shared/Widgets/WidgetSnapshotFile.swift
expect false "design sources and archives" design/dynamic-island-v4/a.svg assets/brand_candidate/x.png reference/old.md
expect false "translations sources and blog" l10n/pl.json blog/post.md
expect false "deploy and pack files" render.yaml MANIFEST.json PACKAGE_MANIFEST.json skills-lock.json .gitignore
expect false "agent tooling" .claude/settings.json .agents/skills/x.md
expect false "blank lines are ignored" "" docs/a.md ""

if [ "$failures" -ne 0 ]; then echo "$failures case(s) failed"; exit 1; fi
echo "all cases pass"

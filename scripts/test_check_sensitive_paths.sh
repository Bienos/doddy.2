#!/usr/bin/env bash
# Tests for scripts/check_sensitive_paths.sh (ADR-811): which pull requests need the owner's label.
# The costly mistake is letting a signing, deploy, secret, agent-spec or migration change through
# unlabelled, so most cases are those; the rest keep ordinary work label-free.
set -uo pipefail
cd "$(dirname "$0")/.."

failures=0
expect() {  # expected exit (0|1), approved (true|false), description, changed paths...
  local want=$1 approved=$2 what=$3; shift 3
  local got
  printf '%s\n' "$@" | OWNER_APPROVED=$approved GITHUB_ACTIONS= scripts/check_sensitive_paths.sh >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "ok    exit=$want  approved=$approved  $what"
  else
    echo "FAIL  wanted exit $want, got $got (approved=$approved): $what"
    failures=$((failures + 1))
  fi
}

# Sensitive, no label: fails.
expect 1 false "app entitlements" Config/Doddy-Push-AppGroup.entitlements
expect 1 false "an entitlements file anywhere" DoddyApp/Doddy.entitlements
expect 1 false "the app's Info.plist" Config/Doddy-Info.plist
expect 1 false "an extension's Info.plist" Config/DoddyWidgets-Info.plist
expect 1 false "the privacy manifest" DoddyApp/Resources/PrivacyInfo.xcprivacy
expect 1 false "the shipping Xcode spec" project.yml
expect 1 false "the free-team Xcode spec" project-iphone.yml
expect 1 false "the Xcode Cloud script" ci_scripts/ci_post_clone.sh
expect 1 false "Render blueprint" render.yaml
expect 1 false "a Vercel project config" server/voice-token/vercel.json
expect 1 false "the secrets manifest" secrets/manifest.json
expect 1 false "the live prompt" voice-agent/instructions.md
expect 1 false "the live tools" voice-agent/tools.json
expect 1 false "the phone agent's prompt" voice-agent/phone/instructions.md
expect 1 false "a messaging migration" server/messaging/migrations/017_new_table.sql
expect 1 false "the on-device migrations" Packages/DoddyCore/Sources/DoddyPersistence/DoddyDatabase.swift
expect 1 false "package dependencies" Packages/DoddyCore/Package.swift
expect 1 false "pinned package versions" Packages/DoddyCore/Package.resolved
expect 1 false "a workflow" .github/workflows/ios.yml
expect 1 false "Dependabot" .github/dependabot.yml
expect 1 false "the ruleset" .github/rulesets/main.json
expect 1 false "this guard" scripts/check_sensitive_paths.sh
expect 1 false "the capability guard" scripts/check_forbidden_capabilities.sh
expect 1 false "agent rules" AGENTS.md
expect 1 false "Claude's rules" CLAUDE.md
expect 1 false "Claude's permissions" .claude/settings.json
expect 1 false "the constitution" docs/trust/01_THE_DODDY_CONSTITUTION.md
expect 1 false "the constitution's config" docs/trust/config/doddy_rules.yaml
expect 1 false "folder agent notes" DoddyApp/CLAUDE.md
expect 1 false "a nested AGENTS.md" Packages/DoddyCore/AGENTS.md
expect 1 false "anything under .claude" .claude/skills/composio
expect 1 false "agent skills" .agents/skills/composio/SKILL.md
expect 1 false "agent prompts" prompts/M1_MEMORY.md
expect 1 false "Studio skills" studio-skills/doddy-brand/brand.py
expect 1 false "the CI entry point" scripts/ci.sh
expect 1 false "other CI scripts" scripts/ci_needs_mac.sh scripts/ci_install_ubuntu_packages.sh
expect 1 false "the Makefile" Makefile
expect 1 false "a Node manifest" web/package.json
expect 1 false "a Node lockfile" backend/package-lock.json
expect 1 false "a root Node manifest" package.json
expect 1 false "the app's package pins" Config/Package.resolved
expect 1 false "site server functions" site/api/waitlist.js
expect 1 false "the voice token server" server/voice-token/src/handler.js
expect 1 false "a server's secret references" gateway/.env.op
expect 1 false "code owners" .github/CODEOWNERS
expect 1 false "one sensitive file among ordinary ones" DoddyApp/Features/Home/HomeView.swift Config/Doddy-Info.plist docs/a.md
expect 1 false "a renamed entitlements file (both paths are listed)" Config/Old.entitlements Config/New.entitlements

# Sensitive, with the label: passes.
expect 0 true "entitlements, approved" Config/Doddy-AppGroup.entitlements
expect 0 true "many sensitive files, approved" project.yml render.yaml voice-agent/tools.json .github/workflows/ios.yml

# Ordinary work: passes with or without the label.
expect 0 false "app source" DoddyApp/Features/Voice/VoiceView.swift
expect 0 false "package source other than migrations" Packages/DoddyCore/Sources/DoddyCore/VoiceTools.swift
expect 0 false "persistence code that isn't the migrations" Packages/DoddyCore/Sources/DoddyPersistence/SQLiteMemoryRepository.swift
expect 0 false "tests" DoddyTests/A.swift DoddyUITests/B.swift Packages/DoddyCore/Tests/DoddyCoreTests/C.swift
expect 0 false "server source" server/messaging/src/index.ts backend/src/app.ts
expect 0 false "server tests" server/messaging/test/helpers.ts
expect 0 false "voice agent notes" voice-agent/README.md voice-agent/phone/README.md
expect 0 false "docs and status" STATUS.md DECISIONS.md docs/OWNER_QUEUE.md BUILD_AND_TEST.md
expect 0 false "decision files (left out on purpose)" docs/decisions/2026-11-13-example.md
expect 0 false "change notes" changes/example.md
expect 0 false "scripts that aren't CI or guards" scripts/regen.sh scripts/test_ci_groups.sh scripts/test_check_sensitive_paths.sh
expect 0 false "notes named like agent rules" docs/CLAUDE_NOTES.md
expect 0 false "the PR template" .github/pull_request_template.md
expect 0 false "web and site" web/src/App.tsx site/index.html
expect 0 false "other servers' source" gateway/src/index.ts server/messaging/test/x.test.ts
expect 0 false "paused Watch code" DoddyWatch/A.swift
expect 0 false "blank lines only" "" ""
expect 0 true "ordinary work, labelled anyway" DoddyApp/App/RootView.swift

if [ "$failures" -ne 0 ]; then echo "$failures case(s) failed"; exit 1; fi
echo "All cases passed."

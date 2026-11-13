#!/usr/bin/env bash
# Does a pull request change something only the owner should approve (ADR-811)?
#
# Reads the changed paths on stdin, one per line (the same list ci_needs_mac.sh reads). Lists every
# path that changes how Doddy is signed, configured, deployed or governed, with the reason. Exits 1
# when there is one and OWNER_APPROVED isn't `true` (the workflow sets it from the pull request's
# `owner-approved` label), otherwise 0.
#
# This is a speed bump, not a lock: anyone who can label pull requests can add the label. It makes
# such a change visible and deliberate. An agent adds the label to its own pull request once the
# description says why each listed file changes (AGENTS.md, "Merging (owner, 8 Nov 2026)"); the
# owner can add it too.
#
# The workflow (.github/workflows/pr-guard.yml) runs this script from the default branch, never from
# the pull request, so an edit to this list takes effect from the pull request after the one that
# merges it. .github/CODEOWNERS names the owner for the same paths: keep the two in step.
#
# Keep the list short. A label asked for on every pull request gets added without reading.
# docs/decisions/ is left out on purpose: more than half of all pull requests add a decision file
# (68 of the latest 120 commits on main, 13 Nov 2026), and a decision that changes agent rules also changes
# AGENTS.md, CLAUDE.md or docs/trust/, which are listed.
set -euo pipefail

# Prints why a path is sensitive, or nothing.
reason() {
  case "$1" in
    # How the app is signed and what it may do.
    *.entitlements) echo "entitlements" ;;
    Config/*Info.plist) echo "Info.plist (server address, URL scheme, background modes, export compliance)" ;;
    PrivacyInfo.xcprivacy | */PrivacyInfo.xcprivacy) echo "privacy manifest" ;;
    project.yml | project-*.yml) echo "Xcode project spec (bundle IDs, signing, permission texts, packages)" ;;
    ci_scripts/*) echo "Xcode Cloud script (TestFlight builds)" ;;
    # Where and how servers deploy, and which keys they get.
    render.yaml | vercel.json | */vercel.json) echo "deploy configuration" ;;
    secrets/*) echo "secrets manifest" ;;
    .env.op | */.env.op) echo "secret references for a server" ;;
    # Server code a merge deploys to production by itself (Vercel builds main).
    site/api/*) echo "site server functions (deployed on merge)" ;;
    server/voice-token/*) echo "voice token server (deployed on merge)" ;;
    # What the live voice agents say and can do (the owner changes the live prompt, CLAUDE.md).
    voice-agent/README.md | voice-agent/*/README.md) ;;
    voice-agent/*) echo "voice agent spec" ;;
    # Data on phones and servers.
    server/messaging/migrations/*) echo "messaging database migration" ;;
    Packages/DoddyCore/Sources/DoddyPersistence/DoddyDatabase.swift) echo "on-device database migrations" ;;
    # Outside code that builds and runs: dependency manifests and pins.
    Packages/DoddyCore/Package.swift | Packages/DoddyCore/Package.resolved | Config/Package.resolved) echo "Swift package dependencies" ;;
    package.json | */package.json | package-lock.json | */package-lock.json) echo "Node dependencies and scripts" ;;
    # The checks and rules themselves.
    .github/workflows/* | .github/dependabot.yml | .github/rulesets/* | .github/CODEOWNERS) echo "CI or repository rules" ;;
    scripts/check_sensitive_paths.sh | scripts/check_forbidden_capabilities.sh) echo "guard script" ;;
    scripts/ci*.sh | Makefile) echo "CI or build script" ;;
    AGENTS.md | CLAUDE.md | */AGENTS.md | */CLAUDE.md | docs/trust/*) echo "rules for agents" ;;
    .claude/* | .agents/* | prompts/* | studio-skills/*) echo "agent settings, skills or prompts" ;;
  esac
}

found=0
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  why=$(reason "$path")
  if [ -n "$why" ]; then
    [ "$found" -eq 0 ] && echo "Sensitive paths in this change:"
    echo "  $path  ($why)"
    found=$((found + 1))
  fi
done

if [ "$found" -eq 0 ]; then
  echo "No sensitive paths: no owner label needed."
  exit 0
fi
if [ "${OWNER_APPROVED:-false}" = "true" ]; then
  echo "$found sensitive path(s), and the pull request has the owner-approved label: OK."
  exit 0
fi
echo "$found sensitive path(s) and no owner-approved label. The owner reviews these files and adds the" \
  "label to the pull request; this check then runs again by itself." >&2
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::error title=Owner approval needed::$found sensitive path(s) changed; add the owner-approved label after review."
fi
exit 1

#!/usr/bin/env bash
# Which files in a pull request change how Doddy is signed, configured, deployed or governed (ADR-811)?
#
# Reads the changed paths on stdin, one per line (the same list ci_needs_mac.sh reads), and lists every
# such path with the reason. Since 25 Nov 2026 it never fails (decision 2026-11-25-minimum-checks): the
# owner asked for the least process between a push and a merge, so the `owner-approved` label is no
# longer needed and the `sensitive-paths` check is a list to read, not a gate. The check keeps its name
# because the `main` ruleset requires it; removing the job would leave every pull request waiting.
#
# The workflow (.github/workflows/pr-guard.yml) runs this script from the default branch, never from
# the pull request. .github/CODEOWNERS names the owner for the same paths: keep the two in step.
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
  echo "No sensitive paths."
else
  echo "$found sensitive path(s): say in the pull request why each changes. This check does not block."
fi
exit 0

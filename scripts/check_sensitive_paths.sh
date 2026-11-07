#!/usr/bin/env bash
# Does a pull request change something only the owner should approve (ADR-811)?
#
# Reads the changed paths on stdin, one per line (the same list ci_needs_mac.sh reads). Lists every
# path that changes how Doddy is signed, configured, deployed or governed, with the reason. Exits 1
# when there is one and OWNER_APPROVED isn't `true` (the workflow sets it from the pull request's
# `owner-approved` label), otherwise 0.
#
# This is a speed bump, not a lock: anyone who can label pull requests can add the label. It makes
# such a change visible and deliberate. Agents never add the label themselves; the owner does.
#
# Keep the list short. A label asked for on every pull request gets added without reading.
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
    # What the live voice agents say and can do (the owner changes the live prompt, CLAUDE.md).
    voice-agent/README.md | voice-agent/*/README.md) ;;
    voice-agent/*) echo "voice agent spec" ;;
    # Data on phones and servers.
    server/messaging/migrations/*) echo "messaging database migration" ;;
    Packages/DoddyCore/Sources/DoddyPersistence/DoddyDatabase.swift) echo "on-device database migrations" ;;
    Packages/DoddyCore/Package.swift | Packages/DoddyCore/Package.resolved) echo "Swift package dependencies" ;;
    # The checks and rules themselves.
    .github/workflows/* | .github/dependabot.yml | .github/rulesets/*) echo "CI or repository rules" ;;
    scripts/check_sensitive_paths.sh | scripts/check_forbidden_capabilities.sh) echo "guard script" ;;
    AGENTS.md | CLAUDE.md | .claude/settings.json | docs/trust/*) echo "rules for agents" ;;
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

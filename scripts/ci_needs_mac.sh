#!/usr/bin/env bash
# Does a pull request need the hosted macOS build (ADR-497)?
#
# Reads the changed paths on stdin, one per line. Prints `mac=true` or `mac=false` on stdout (the
# workflow appends it to $GITHUB_OUTPUT), and on stderr the first path that needs the Mac.
#
# The macOS job takes about 52 minutes at $0.062 a minute, about $3.20 a run. It is worth it only
# when a change can reach the Xcode build or its tests, or is code that the full scripts/ci.sh runs
# on macOS (bash 3.2 and BSD tools behave differently). So the Mac runs unless EVERY changed path is
# in the list below. Any other path, including a folder added later, runs it: a mistake in this
# list can only cost money, never skip a build that was needed. No input also runs it.
set -euo pipefail

no_mac() {  # 0 when the path can't affect the macOS job
  case "$1" in
    # Bundled into the app as resources (project.yml), unlike the rest of voice-agent/.
    voice-agent/instructions.md | voice-agent/tools.json | voice-agent/session.json) return 1 ;;
    voice-agent/*) return 0 ;;
    # Text, design sources and the web/server code: none of it is in an Xcode target. Generated
    # app files (string catalogs, island art) live in the app folders, so they still run the Mac.
    docs/* | prompts/* | reference/* | blog/* | site/* | design/* | assets/* | VISUAL_REVIEW/* \
      | l10n/* | contracts/* | schemas/* | server/* | backend/* | gateway/* | secrets/* \
      | .agents/* | .claude/*) return 0 ;;
    # Doddy Studio's skills run in Anthropic's container, never in an Xcode target (ADR-584).
    studio-skills/*) return 0 ;;
    # Agent notes, excluded from every target's sources.
    */CLAUDE.md | */AGENTS.md) return 0 ;;
    # Apple Watch and Mac apps (ADR-572): paused, in no target of project.yml or project-iphone.yml.
    # Their own checks (string catalogs, island art, capability guard) run in the Linux `core` job.
    DoddyWatch/* | DoddyWatchWidgets/* | DoddyMac/* | DoddyMacWidgets/* \
      | Config/DoddyWatch* | Config/DoddyMac* | project-watch.yml | project-mac.yml) return 0 ;;
    render.yaml | skills-lock.json | MANIFEST.json | PACKAGE_MANIFEST.json | .gitignore) return 0 ;;
    */*) return 1 ;;
    # Top-level Markdown: README, STATUS, DECISIONS and the like.
    *.md) return 0 ;;
    *) return 1 ;;
  esac
}

count=0 first=""
# Read everything (no early exit), so the writer of a long list never hits a closed pipe.
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  count=$((count + 1))
  if [ -z "$first" ] && ! no_mac "$path"; then first=$path; fi
done

if [ "$count" -eq 0 ]; then
  echo "No changed files listed: the macOS build runs." >&2
  echo "mac=true"
elif [ -n "$first" ]; then
  echo "The macOS build runs: $first can reach the app build or its tests." >&2
  echo "mac=true"
else
  echo "The macOS build is skipped: none of the $count changed files can reach the app build." >&2
  echo "mac=false"
fi

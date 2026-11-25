#!/usr/bin/env bash
# Does a pull request need the hosted macOS build (ADR-497)?
#
# Reads the changed paths on stdin, one per line. Prints `mac=true` or `mac=false` on stdout (the
# workflow appends it to $GITHUB_OUTPUT), and on stderr the first path that needs the Mac.
# A second line, `ui_smoke=true` or `ui_smoke=false` (25 Nov 2026, decision
# 2026-11-25-pull-request-launch-check): does the change touch the UI tests' own code (DoddyUITests/)?
# Such a pull request runs the UI smoke classes; any other runs the unit tests and the two launch tests.
# No input says true: when the list can't be read, the larger run is the safe one.
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
    docs/* | changes/* | prompts/* | reference/* | blog/* | site/* | design/* | assets/* | VISUAL_REVIEW/* \
      | l10n/* | contracts/* | schemas/* | server/* | backend/* | gateway/* | web/* | secrets/* \
      | .agents/* | .claude/*) return 0 ;;
    # Doddy Studio's skills run in Anthropic's container, never in an Xcode target (ADR-740).
    studio-skills/*) return 0 ;;
    # These exact files run only on Ubuntu. Keep shared entry points (ios.yml and ci.sh)
    # and the Mac job selector itself on the conservative build path.
    scripts/ci_groups.sh | scripts/test_ci_groups.sh | scripts/test_screen_models.sh \
      | scripts/ci_install_ubuntu_packages.sh | scripts/test_ci_install_ubuntu_packages.sh \
      | .github/workflows/pr-guard.yml | .github/workflows/vercel-blocked-status.yml) return 0 ;;
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

# 0 when the path is UI test code. Only that: a change to scripts/ci.sh or the workflow must run the
# launch check, the path every other pull request takes, and the smoke path then runs on the push to main.
ui_smoke_path() {
  case "$1" in
    DoddyUITests/*) return 0 ;;
    *) return 1 ;;
  esac
}

count=0 first="" first_ui=""
# Read everything (no early exit), so the writer of a long list never hits a closed pipe.
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  count=$((count + 1))
  if [ -z "$first" ] && ! no_mac "$path"; then first=$path; fi
  if [ -z "$first_ui" ] && ui_smoke_path "$path"; then first_ui=$path; fi
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

if [ "$count" -eq 0 ]; then
  echo "ui_smoke=true"
elif [ -n "$first_ui" ]; then
  echo "The UI smoke classes run on a pull request: $first_ui is UI test code." >&2
  echo "ui_smoke=true"
else
  echo "ui_smoke=false"
fi

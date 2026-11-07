#!/usr/bin/env bash
# Which Linux check groups does a pull request need? (ADR-684, the cousin of ci_needs_mac.sh)
#
# Reads the changed paths on stdin, one per line. Prints one line per group on stdout, for
# $GITHUB_OUTPUT:  swift=true|false  backend=…  node=…  messaging=…
# (The `checks` group, the Python generators and guards, takes seconds and always runs.)
# On stderr: why a group runs.
#
# A group is skipped only when EVERY changed path is known not to reach it. Any path not listed
# here, a folder added later, or no input at all runs every group: a mistake in this list can only
# cost minutes, never skip a check that was needed.
set -euo pipefail

# groups_for PATH: prints the groups the path reaches, "none", or "all".
groups_for() {
  local p=$1
  case "$p" in
    docs/* | design/*) echo swift; return ;;
    # Notes, text sources, archives, agent tooling: no heavy suite reads them (the generators and
    # the pack check, which do, are in the `checks` group that always runs).
    prompts/* | reference/* | blog/* | l10n/* | VISUAL_REVIEW/* \
      | .agents/* | .claude/* | */CLAUDE.md | */AGENTS.md) echo none; return ;;
    # Paused Watch and Mac apps (ADR-572): in no target of project.yml, in no suite.
    DoddyWatch/* | DoddyWatchWidgets/* | DoddyMac/* | DoddyMacWidgets/* \
      | Config/DoddyWatch* | Config/DoddyMac* | project-watch.yml | project-mac.yml) echo none; return ;;
    render.yaml | skills-lock.json | MANIFEST.json | PACKAGE_MANIFEST.json | .gitignore) echo none; return ;;
    backend/*) echo "swift backend node"; return ;;     # Swift tool-catalog tests and Node secrets checks read backend files
    web/* | gateway/* | site/* | server/voice-token/* | secrets/* | tools/secrets/*) echo node; return ;;
    server/messaging/*) echo "messaging node"; return ;;
    contracts/*) echo "swift backend node messaging"; return ;;
    schemas/*) echo "swift backend node messaging"; return ;;
    voice-agent/*) echo "swift backend messaging"; return ;;
    Packages/* | DoddyApp/* | DoddyTests/* | DoddyUITests/* | DoddyWidgets/* | DoddyShare/* | DoddyNotificationContent/* \
      | Shared/* | Config/* | assets/* | project.yml | project-iphone.yml) echo swift; return ;;
    */*) echo all; return ;;                             # scripts/, tools/, .github/, server/other, new folders
    *.md) echo none; return ;;                           # top-level notes: README, STATUS, DECISIONS
    *) echo all; return ;;                               # Makefile and top-level files nobody listed
  esac
}

swift=false backend=false node=false messaging=false count=0 why=""
note() { [ -n "$why" ] || why="$1"; }
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  count=$((count + 1))
  for g in $(groups_for "$path"); do
    case "$g" in
      none) ;;
      all) swift=true backend=true node=true messaging=true; note "$path is not on the list, so everything runs" ;;
      swift) swift=true; note "$path reaches swift" ;;
      backend) backend=true ;;
      node) node=true ;;
      messaging) messaging=true ;;
    esac
  done
done

if [ "$count" -eq 0 ]; then
  echo "No changed files listed: every group runs." >&2
  swift=true backend=true node=true messaging=true
fi
echo "Groups: swift=$swift backend=$backend node=$node messaging=$messaging (checks always)." >&2
printf 'swift=%s\nbackend=%s\nnode=%s\nmessaging=%s\n' "$swift" "$backend" "$node" "$messaging"

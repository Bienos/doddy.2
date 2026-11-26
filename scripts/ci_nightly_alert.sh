#!/usr/bin/env bash
# The nightly run's alert (26 Nov 2026). Tests run only once a night on `main` now (decision
# 2026-11-25-minimum-checks), so a red nightly run must reach the owner without anyone opening the Actions tab.
#
# A red run opens one GitHub issue titled "Nightly run on main failed" (or comments on it when one is already
# open, so a week of red nights is one issue, not seven). GitHub emails the repository's watchers about a new
# issue and its comments. A green run closes that issue with a comment, so an open issue always means "main
# is red now".
#
#   RESULTS="success failure skipped" RUN_URL=https://... scripts/ci_nightly_alert.sh
#
# RESULTS: the results of the jobs the alert waits for (`join(needs.*.result, ' ')`). Uses the `gh` CLI with
# GH_TOKEN and GH_REPO from the workflow. Exits non-zero only when `gh` itself fails.
set -euo pipefail
title="Nightly run on main failed"
results=" ${RESULTS:?RESULTS is required} "
run_url=${RUN_URL:?RUN_URL is required}

open=$(gh issue list --state open --search "in:title \"$title\"" --json number,title \
  --jq "map(select(.title == \"$title\")) | .[0].number // empty")

case "$results" in
  *" failure "* | *" cancelled "*)
    body="The nightly run failed: $run_url

Job results: ${RESULTS}. Fix this first (AGENTS.md, \"Minimum process from push to merge\"). This issue closes by itself after the next green nightly run."
    if [ -n "$open" ]; then
      gh issue comment "$open" --body "Still red: $run_url (job results: ${RESULTS})."
      echo "Commented on issue #$open."
    else
      gh issue create --title "$title" --body "$body"
      echo "Opened an issue."
    fi ;;
  *)
    if [ -n "$open" ]; then
      gh issue close "$open" --comment "The nightly run is green again: $run_url"
      echo "Closed issue #$open: the nightly run is green."
    else
      echo "The nightly run is green and no alert is open."
    fi ;;
esac

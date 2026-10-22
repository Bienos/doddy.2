#!/usr/bin/env bash
# Studio (ADR-584): render the skills' samples with the real Python renderers, then run the messaging
# server's own TypeScript checks on the files (server/messaging/scripts/check-studio-render.mjs).
# The two checkers can't drift apart without this failing. Needs python3 with reportlab and
# matplotlib, and the compiled messaging server (its `npm test` builds it).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
status=0
for sample in "$root"/studio-skills/samples/*.json; do
  out="$work/$(basename "$sample" .json)"
  mkdir -p "$out"
  python3 -I -B "$root/studio-skills/doddy-docs/render_brief.py" --content "$sample" --out-dir "$out" >/dev/null
  python3 -I -B "$root/studio-skills/doddy-infographic/render_infographic.py" --content "$sample" --out-dir "$out" >/dev/null
  echo "--- $(basename "$sample")"
  if ! (cd "$root/server/messaging" && node scripts/check-studio-render.mjs "$sample" "$out"); then status=1; fi
done
[ "$status" -eq 0 ] && echo "PASS: the server's checks accept every sample the renderers made" || echo "FAIL: see above"
exit "$status"

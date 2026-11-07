#!/usr/bin/env bash
# Doddy Studio's own Agent Skills (studio-skills/, docs/implementation/STUDIO.md).
#
#   scripts/studio_skills.sh check              frontmatter and size limits, no unlisted font or image
#                                               files, then both renderers on the samples (and on line,
#                                               donut and numbered variants), each output checked the
#                                               way Doddy's server checks it; finally a broken SVG must
#                                               fail the checker. Needs python3 with reportlab and
#                                               matplotlib. Exit 0 only when everything passes.
#   scripts/studio_skills.sh check-files        only the frontmatter, size and font/image checks (no
#                                               reportlab or matplotlib needed).
#   scripts/studio_skills.sh upload [--dry-run] creates each skill (POST /v1/skills), or a new version
#                                               when STUDIO_SKILL_ID_<NAME> is set (for example
#                                               STUDIO_SKILL_ID_DODDY_BRAND=skill_…), then prints the
#                                               STUDIO_SKILLS value for the messaging server. Needs
#                                               ANTHROPIC_API_KEY (Doddy's own, from 1Password; never
#                                               typed into chat). --dry-run prints the requests only.
set -uo pipefail
cd "$(dirname "$0")/.."

SKILLS_DIR=studio-skills
PY=(python3 -I -B)

skill_dirs() {
  find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -name 'doddy-*' | sort
}

check() {
  local failures=0
  "${PY[@]}" "$SKILLS_DIR/tools/check_skills.py" "$SKILLS_DIR" || failures=$((failures + 1))

  if ! "${PY[@]}" -c "import reportlab, matplotlib" 2>/dev/null; then
    echo "FAIL renderers: python3 needs reportlab and matplotlib (pip install reportlab matplotlib)"
    return 1
  fi

  local work
  work=$(mktemp -d)
  trap 'rm -rf "${work:?}"; trap - RETURN' RETURN
  # The two samples, plus variants that exercise the other chart kinds and numbered facts.
  cp "$SKILLS_DIR/samples/brief.json" "$work/pl.json"
  cp "$SKILLS_DIR/samples/brief-en.json" "$work/en.json"
  "${PY[@]}" - "$work" <<'PY' || failures=$((failures + 1))
import json, sys
from pathlib import Path
work = Path(sys.argv[1])
en = json.loads((work / "en.json").read_text(encoding="utf-8"))
pl = json.loads((work / "pl.json").read_text(encoding="utf-8"))
line = json.loads(json.dumps(en))
line["infographic"]["numbered"] = True
line["infographic"]["chart"] = {"kind": "line", "title": "Average weekly hours during the trial", "unit": "hours",
    "data": [{"label": f"Month {i + 1}", "value": v} for i, v in enumerate([38.5, 36.2, 34.9, 34.1, 33.8, 33.6])], "claims": ["c1"]}
donut = json.loads(json.dumps(pl))
donut["infographic"]["facts"] = donut["infographic"]["facts"][:3]
donut["infographic"]["chart"] = {"kind": "donut", "title": "Jak ogrzewane są domy w przykładzie", "unit": "%",
    "data": [{"label": l, "value": v} for l, v in [("Gaz ziemny", 38), ("Węgiel", 27), ("Pompa ciepła", 14), ("Pellet i drewno", 12), ("Prąd", 6), ("Inne", 3)]], "claims": ["c1"]}
(work / "line.json").write_text(json.dumps(line, ensure_ascii=False), encoding="utf-8")
(work / "donut.json").write_text(json.dumps(donut, ensure_ascii=False), encoding="utf-8")
PY

  local name
  for name in pl en line donut; do
    if "${PY[@]}" "$SKILLS_DIR/doddy-docs/render_brief.py" --content "$work/$name.json" --out-dir "$work/out-$name" >/dev/null \
      && "${PY[@]}" "$SKILLS_DIR/doddy-infographic/render_infographic.py" --content "$work/$name.json" --out-dir "$work/out-$name" >/dev/null; then
      "${PY[@]}" "$SKILLS_DIR/tools/check_outputs.py" --content "$work/$name.json" --dir "$work/out-$name" \
        | sed "s#$work/##" || failures=$((failures + 1))
    else
      echo "FAIL renderers on sample '$name'"
      failures=$((failures + 1))
    fi
  done

  # The checker must catch a broken file: orange text, a tiny label, an external link.
  mkdir -p "$work/broken"
  cp "$work/out-en/"* "$work/broken/"
  sed -i -e '0,/fill="#171715"/s//fill="#FF6A00"/' -e '0,/font-size="30"/s//font-size="12"/' \
    -e 's#</svg>#<a href="https://example.org/"><text x="1" y="1" font-size="30" fill="\#171715">x</text></a></svg>#' \
    "$work/broken/infographic.svg"
  if "${PY[@]}" "$SKILLS_DIR/tools/check_outputs.py" --content "$work/en.json" --dir "$work/broken" > "$work/broken.txt"; then
    echo "FAIL the checker passed a broken SVG"
    failures=$((failures + 1))
  else
    local caught
    caught=$(grep -c '^FAIL' "$work/broken.txt")
    echo "PASS the checker caught a broken SVG ($caught problems: orange text, small text, external link)"
  fi

  if [ "$failures" -eq 0 ]; then
    echo "RESULT: PASS (studio skills)"
  else
    echo "RESULT: FAIL ($failures)"
  fi
  [ "$failures" -eq 0 ]
}

upload() {
  local dry=0
  [ "${1:-}" = "--dry-run" ] && dry=1
  if [ "$dry" -eq 0 ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "Not uploading: ANTHROPIC_API_KEY isn't set. Use Doddy's key from 1Password (item anthropic-api) in" >&2
    echo "this shell only, never in chat or a file. scripts/studio_skills.sh upload --dry-run shows the requests." >&2
    return 2
  fi
  check >/dev/null || { echo "Not uploading: scripts/studio_skills.sh check fails. Run it to see why." >&2; return 1; }

  local pairs=() dir name var id url args file rel response
  while IFS= read -r dir; do
    name=$(basename "$dir")
    var="STUDIO_SKILL_ID_$(echo "$name" | tr 'a-z-' 'A-Z_')"
    id="${!var:-}"
    if [ -n "$id" ]; then url="https://api.anthropic.com/v1/skills/$id/versions"; else url="https://api.anthropic.com/v1/skills"; fi
    args=()
    while IFS= read -r file; do
      rel="${file#"$SKILLS_DIR"/}"
      args+=(-F "files[]=@$file;filename=$rel")
    done < <(find "$dir" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' | sort)
    if [ "$dry" -eq 1 ]; then
      echo "POST $url"
      printf '  %s %s\n' "${args[@]}"
      pairs+=("${id:-<new $name>}@<version>")
      continue
    fi
    response=$(curl -sS --fail-with-body -X POST "$url" \
      -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" "${args[@]}") || {
      echo "Upload of $name failed: $response" >&2
      return 1
    }
    # A new skill answers with its id and latest_version_id; a new version with its own id (skver_…).
    pairs+=("$(printf '%s' "$response" | python3 -I -c '
import json, sys
r, known = json.load(sys.stdin), sys.argv[1]
if known:
    print(known + "@" + r["id"])
else:
    print(r["id"] + "@" + (r.get("latest_version_id") or "latest"))' "$id" 2>/dev/null)") \
      || { echo "Couldn't read the answer for $name: $response" >&2; return 1; }
    echo "uploaded $name: ${pairs[-1]}"
  done < <(skill_dirs)
  local IFS=,
  echo
  echo "STUDIO_SKILLS=${pairs[*]}"
  echo "Set that on the messaging server (and its worker). Pinned versions keep production from changing when someone uploads again."
}

case "${1:-}" in
  check) check ;;
  # Frontmatter, sizes and the font/image allow list only: plain Python, no reportlab or matplotlib.
  check-files) "${PY[@]}" "$SKILLS_DIR/tools/check_skills.py" "$SKILLS_DIR" ;;
  upload) shift; upload "$@" ;;
  *) echo "usage: scripts/studio_skills.sh check | check-files | upload [--dry-run]" >&2; exit 64 ;;
esac

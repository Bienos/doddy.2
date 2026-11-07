#!/usr/bin/env bash
# Regenerates every generated file in the repository (decision 2026-11-07-agent-rules-and-records).
# Use it after a merge conflict in a generated file instead of merging by hand: the string catalogs
# (DoddyApp/Resources/Localizable.xcstrings and the others), the site's pages in every language, the
# blog, the "What can Doddy do?" page, the web app's tokens and brand files, and the site's tokens.
# Each generator also has a --check mode, which scripts/ci.sh runs; this script is the write mode.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -I tools/gen_site_tokens.py
python3 -I tools/gen_web_assets.py
python3 -I tools/build_strings_catalog.py
python3 -I tools/build_site_i18n.py
python3 -I tools/build_blog.py
python3 -I tools/build_day.py
echo "Regenerated. Now run: scripts/ci.sh --only checks"

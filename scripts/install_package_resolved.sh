#!/bin/sh
# Copies the app's pinned Swift package versions, Config/Package.resolved, into a project XcodeGen
# just generated, so Xcode resolves exactly those versions instead of the newest that fit
# project.yml. The project folder is generated and git-ignored; the pins are committed.
#   scripts/install_package_resolved.sh Doddy.xcodeproj
# Used by `make project`, `make project-iphone` and scripts/ci.sh. ci_scripts/ci_post_clone.sh does
# the same in its own lines (Xcode Cloud runs that script on its own). No pins yet: does nothing.
set -eu
cd "$(dirname "$0")/.."
project=${1:?usage: scripts/install_package_resolved.sh <name>.xcodeproj}
[ -f Config/Package.resolved ] || { echo "No Config/Package.resolved yet: packages resolve freely." >&2; exit 0; }
[ -d "$project" ] || { echo "$project doesn't exist: generate it first" >&2; exit 1; }
dest="$project/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$dest"
cp Config/Package.resolved "$dest/Package.resolved"
echo "Pinned package versions installed in $project."

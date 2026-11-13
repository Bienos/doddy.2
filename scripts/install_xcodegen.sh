#!/bin/sh
# Installs XcodeGen at the one version CI uses, after checking the SHA-256 of the release file.
# Used by .github/workflows/ios.yml and ci_scripts/ci_post_clone.sh (Xcode Cloud). Both used to run
# `brew install xcodegen`, so each build got whichever version Homebrew had that day. On your own
# Mac, `brew install xcodegen` is still fine (BUILD_AND_TEST.md); this script is for CI.
#
#   scripts/install_xcodegen.sh
#
# Prints the folder that holds `xcodegen` as its only line on stdout (progress and errors go to
# stderr), so a caller can put it first on PATH:
#   xcodegen_bin=$(scripts/install_xcodegen.sh) && PATH="$xcodegen_bin:$PATH"
# When GITHUB_PATH is set (GitHub Actions) the folder is also added there, so later steps of the job
# find it. The release file is checked before anything is unpacked; a different file stops the run.
# Nothing here runs a downloaded file. A repeat run finds the verified copy and downloads nothing.
#
# The pin. To move to another version, change `version` and `sha256` together, in a pull request
# of their own: download https://github.com/yonaskolb/XcodeGen/releases/download/<version>/xcodegen.zip
# into an empty folder, run `shasum -a 256` on it, and compare with the digest GitHub shows for that
# asset on the release page.
#   version  2.46.0, the version Homebrew's formula had on 13 Nov 2026 (what `brew install xcodegen`
#            gave CI until then); the release file is dated 2026-07-16
#   sha256   of xcodegen.zip, from two separate downloads on 13 Nov 2026 that gave the same file
#            (GitHub's own digest for the asset was not reachable from that session, so it is not
#            cross-checked yet: docs/OWNER_QUEUE.md)
#
# Optional environment variables:
#   XCODEGEN_PREFIX        where to unpack (default: ${RUNNER_TEMP:-${TMPDIR:-/tmp}}/xcodegen-<version>)
#   XCODEGEN_TRIES         download attempts (default 4); XCODEGEN_RETRY_WAIT seconds, times the attempt number (default 10)
#   XCODEGEN_SHA256        replaces the pinned checksum. For scripts/test_install_xcodegen.sh only; CI leaves it unset.
set -eu

version=2.46.0
sha256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
url="https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip"

expected=${XCODEGEN_SHA256:-$sha256}
dest=${XCODEGEN_PREFIX:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/xcodegen-$version}
bin_dir=$dest/xcodegen/bin

say() { echo "install_xcodegen: $*" >&2; }
die() { say "$*"; exit 1; }

# The folder is reported to the caller, and to GitHub Actions when it is running this.
finish() {
  if [ -n "${GITHUB_PATH:-}" ]; then echo "$bin_dir" >> "$GITHUB_PATH"; fi
  echo "$bin_dir"
  exit 0
}

# A copy this script already checked: the marker holds the checksum it was checked against.
if [ -x "$bin_dir/xcodegen" ] && [ "$(cat "$dest/.verified-sha256" 2>/dev/null || true)" = "$expected" ]; then
  say "XcodeGen $version is already installed in $dest"
  finish
fi

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f 1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d ' ' -f 1
  else die "neither sha256sum nor shasum is installed, so the download can't be checked"
  fi
}
command -v curl >/dev/null 2>&1 || die "curl is not installed"
command -v unzip >/dev/null 2>&1 || die "unzip is not installed"

# A new, empty folder for the download and the unpacked copy, removed on the way out.
work=$(mktemp -d "${TMPDIR:-/tmp}/xcodegen-install.XXXXXX")
trap 'rm -rf "$work"' EXIT
zip=$work/xcodegen.zip

tries=${XCODEGEN_TRIES:-4}
wait_s=${XCODEGEN_RETRY_WAIT:-10}
n=1
say "downloading XcodeGen $version"
until curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --max-time 300 --output "$zip" "$url"; do
  [ "$n" -ge "$tries" ] && die "the download failed $n times: $url"
  say "the download failed (attempt $n of $tries); trying again in $((wait_s * n)) s"
  sleep $((wait_s * n))
  n=$((n + 1))
done

actual=$(sha256_of "$zip")
if [ "$actual" != "$expected" ]; then
  die "the downloaded file is not the pinned release: SHA-256 is $actual, expected $expected. Nothing was unpacked."
fi
say "SHA-256 matches the pin ($expected)"

mkdir "$work/unpacked"
unzip -q "$zip" -d "$work/unpacked"
[ -f "$work/unpacked/xcodegen/bin/xcodegen" ] || die "the release file has no xcodegen/bin/xcodegen"
chmod +x "$work/unpacked/xcodegen/bin/xcodegen"

# Replace any earlier, unverified copy; the share/ folder (setting presets) must stay beside bin/.
mkdir -p "$dest"
rm -rf "$dest/xcodegen" "$dest/.verified-sha256"
mv "$work/unpacked/xcodegen" "$dest/xcodegen"
printf '%s\n' "$expected" > "$dest/.verified-sha256"
say "XcodeGen $version installed in $dest"
finish

#!/usr/bin/env bash
# Bootstrap the two Ubuntu 24.04 CI jobs without depending on one mirror's DNS.
# Run as root (sudo on the hosted runner, already root in swift:6.1-noble).
# The fallback uses the image's Ubuntu signing key, isolated apt lists and the
# same Noble release/update/security/backport channels. No trust checks change.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 package... (Ubuntu 24.04 CI only)" >&2
  exit 64
fi
for package in "$@"; do
  if [[ ! "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]; then
    echo "Expected an unversioned Ubuntu package name: $package" >&2
    exit 64
  fi
done

apt_options=(-o APT::Update::Error-Mode=any -o Acquire::Retries=1
  -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15)
if timeout --kill-after=5s 60s apt-get "${apt_options[@]}" update \
  && timeout --kill-after=5s 90s apt-get "${apt_options[@]}" install -y --no-install-recommends "$@"; then
  exit 0
fi

echo "Default Ubuntu dependency install failed; trying the signed HTTPS Ubuntu mirror." >&2
apt_work=$(mktemp -d)
trap 'rm -rf "$apt_work"' EXIT
chmod 755 "$apt_work"  # apt's unprivileged downloader must be able to read the source list.
mkdir "$apt_work/lists"
cat > "$apt_work/sources.list" <<'SOURCES'
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.edge.kernel.org/ubuntu noble main restricted universe multiverse
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.edge.kernel.org/ubuntu noble-updates main restricted universe multiverse
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.edge.kernel.org/ubuntu noble-security main restricted universe multiverse
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.edge.kernel.org/ubuntu noble-backports main restricted universe multiverse
SOURCES
apt_options+=(-o "Dir::Etc::sourcelist=$apt_work/sources.list"
  -o Dir::Etc::sourceparts=- -o "Dir::State::lists=$apt_work/lists")
timeout --kill-after=5s 90s apt-get "${apt_options[@]}" update
timeout --kill-after=5s 180s apt-get "${apt_options[@]}" install -y --no-install-recommends "$@"

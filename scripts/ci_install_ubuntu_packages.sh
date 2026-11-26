#!/usr/bin/env bash
# Bootstrap Ubuntu 24.04 CI jobs without depending on one mirror.
# Run as root (sudo on the hosted runner, already root in swift:6.1-noble).
# The HTTPS kernel.org mirror is tried first, with the image's Ubuntu signing key,
# isolated apt lists and the same Noble release/update/security/backport channels;
# the image's own apt sources are the fallback. No trust checks change.
# Order (25 Nov 2026): the image's plain-http sources stalled until the time limit in
# three jobs of runs 44473265852 and 44477033532 (swift 60 s, node 100 s, messaging
# 121 s lost) before the HTTPS mirror installed the same packages (12 to 71 s).
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

# The hosted image may already have all the tools. Avoid touching the mirrors in that case.
all_installed=true
for package in "$@"; do
  if [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" != 'install ok installed' ]]; then
    all_installed=false
    break
  fi
done
if [ "$all_installed" = true ]; then
  echo "Ubuntu CI dependencies already installed: $*"
  exit 0
fi

# DODDY_APT_DEB_DIR (26 Nov 2026, the node job's redis-server): a folder CI keeps in its cache. When it holds
# the packages' .deb files they are installed from it with dpkg, without `apt-get update` (which was most of
# the step's 47 s, run 45645801212); when it is empty, apt downloads into it, so the workflow can save it.
# The files come from the same signed Ubuntu archive; dpkg checks their dependencies, and if it can't install
# them the usual apt path below runs instead.
deb_dir=${DODDY_APT_DEB_DIR:-}
if [ -n "$deb_dir" ] && compgen -G "$deb_dir/*.deb" >/dev/null; then
  if dpkg -i "$deb_dir"/*.deb; then
    ok=true
    for package in "$@"; do
      [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" == 'install ok installed' ]] || ok=false
    done
    if [ "$ok" = true ]; then echo "Installed from the cached packages in $deb_dir: $*"; exit 0; fi
  fi
  echo "The cached packages in $deb_dir did not install; using apt." >&2
  rm -f "$deb_dir"/*.deb
fi

apt_options=(-o APT::Update::Error-Mode=any -o Acquire::Retries=1
  -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15)
if [ -n "$deb_dir" ]; then
  mkdir -p "$deb_dir/partial"
  apt_options+=(-o "Dir::Cache::archives=$deb_dir")
fi

apt_work=$(mktemp -d)
trap 'rm -rf "$apt_work"; if [ -n "$deb_dir" ]; then rm -rf "$deb_dir/partial" "$deb_dir/lock"; fi' EXIT
chmod 755 "$apt_work"  # apt's unprivileged downloader must be able to read the source list.
mkdir "$apt_work/lists"
cat > "$apt_work/sources.list" <<'SOURCES'
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.edge.kernel.org/ubuntu noble main restricted universe multiverse
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.edge.kernel.org/ubuntu noble-updates main restricted universe multiverse
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.edge.kernel.org/ubuntu noble-security main restricted universe multiverse
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://mirrors.edge.kernel.org/ubuntu noble-backports main restricted universe multiverse
SOURCES
mirror_options=("${apt_options[@]}" -o "Dir::Etc::sourcelist=$apt_work/sources.list"
  -o Dir::Etc::sourceparts=- -o "Dir::State::lists=$apt_work/lists")
if timeout --kill-after=5s 60s apt-get "${mirror_options[@]}" update \
  && timeout --kill-after=5s 90s apt-get "${mirror_options[@]}" install -y --no-install-recommends "$@"; then
  exit 0
fi

echo "The signed HTTPS Ubuntu mirror failed; trying the image's own apt sources." >&2
timeout --kill-after=5s 90s apt-get "${apt_options[@]}" update
timeout --kill-after=5s 180s apt-get "${apt_options[@]}" install -y --no-install-recommends "$@"

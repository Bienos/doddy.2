#!/usr/bin/env bash
# Exercise the real bootstrap with fake apt/timeout: never install on this host.
set -euo pipefail
cd "$(dirname "$0")/.."
test_work=$(mktemp -d)
trap 'rm -rf "$test_work"' EXIT
mkdir "$test_work/bin" "$test_work/tmp"
export BOOTSTRAP_LOG="$test_work/log" BOOTSTRAP_SOURCES="$test_work/sources"
export PATH="$test_work/bin:$PATH" TMPDIR="$test_work/tmp"
cat > "$test_work/bin/timeout" <<'MOCK'
#!/usr/bin/env bash
set -eu
[[ "$1" == --kill-after=5s ]]
case "$2" in 60s|90s|180s) ;; *) exit 90 ;; esac
shift 2
exec "$@"
MOCK
cat > "$test_work/bin/apt-get" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$BOOTSTRAP_LOG"
fallback=false
operation=
for arg in "$@"; do
  case "$arg" in
    Dir::Etc::sourcelist=*)
      fallback=true
      cp "${arg#*=}" "$BOOTSTRAP_SOURCES"
      ;;
    update|install) operation=$arg ;;
  esac
done
case "$BOOTSTRAP_CASE:$fallback:$operation" in
  success:*) exit 0 ;;
  dns:false:*|install:false:install|both:*|fallback-install:true:install) exit 100 ;;
  fallback-install:false:*) exit 100 ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$test_work/bin/timeout" "$test_work/bin/apt-get"

run_case() {
  export BOOTSTRAP_CASE=$1
  : > "$BOOTSTRAP_LOG"
  rm -f "$BOOTSTRAP_SOURCES"
  if scripts/ci_install_ubuntu_packages.sh libsqlite3-dev python3 python3-yaml > "$test_work/output" 2>&1; then
    result=0
  else
    result=$?
  fi
  [ "$result" -eq "$2" ] || { cat "$test_work/output"; exit 1; }
  [ "$(wc -l < "$BOOTSTRAP_LOG" | tr -d ' ')" -eq "$3" ]
  # Every install retains every requested dependency and the strict update mode.
  if [ -s "$BOOTSTRAP_LOG" ]; then
    ! grep -v 'APT::Update::Error-Mode=any' "$BOOTSTRAP_LOG"
    ! grep 'install' "$BOOTSTRAP_LOG" | grep -v 'install -y --no-install-recommends libsqlite3-dev python3 python3-yaml$'
  fi
  # Temporary apt sources and lists are removed after success and failure.
  [ -z "$(ls -A "$test_work/tmp")" ]
  echo "ok: $1 (exit $result)"
}
run_case success 0 2
[ ! -e "$BOOTSTRAP_SOURCES" ]
run_case dns 0 3
[ "$(wc -l < "$BOOTSTRAP_SOURCES" | tr -d ' ')" -eq 4 ]
for suite in noble noble-updates noble-security noble-backports; do
  grep -qx "deb \[signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg\] https://mirrors.edge.kernel.org/ubuntu $suite main restricted universe multiverse" "$BOOTSTRAP_SOURCES"
done
! grep -E 'trusted=yes|allow-unauthenticated|AllowInsecure|Verify-Peer=false' "$BOOTSTRAP_LOG" "$BOOTSTRAP_SOURCES"
grep -q 'Dir::Etc::sourceparts=-' "$BOOTSTRAP_LOG"
grep -q 'Dir::State::lists=' "$BOOTSTRAP_LOG"
run_case install 0 4
run_case both 100 2
run_case fallback-install 100 3
# Neither empty input nor an option masquerading as a package may invoke apt.
invalid_input() {
  : > "$BOOTSTRAP_LOG"
  if scripts/ci_install_ubuntu_packages.sh "$@" > "$test_work/output" 2>&1; then
    echo "FAIL: accepted invalid package input" >&2
    exit 1
  else
    [ "$?" -eq 64 ]
  fi
  [ ! -s "$BOOTSTRAP_LOG" ]
}
invalid_input
for package in --allow-unauthenticated 'python3;echo bad' 'python3=1'; do
  invalid_input "$package"
done
echo "all bootstrap cases pass"

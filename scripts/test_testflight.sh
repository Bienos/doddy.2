#!/usr/bin/env bash
# Tests for scripts/testflight.sh (ADR-694) with stand-ins for make, xcodebuild and xcrun that only record how they
# were called, so they run on Linux. They show the script's own rules: what it refuses, that "validate" never
# uploads, that "upload" does, which settings it passes, and that the key is never printed and is deleted. They say
# nothing about whether Xcode or App Store Connect accept the result.
set -uo pipefail
cd "$(dirname "$0")/.."
repo=$(pwd)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"; mkdir -p "$bin"
log="$tmp/calls.log"

cat > "$bin/make" <<'EOF'
#!/usr/bin/env bash
echo "make $*" >> "$CALLS_LOG"
EOF
cat > "$bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
echo "xcodebuild $*" >> "$CALLS_LOG"
# remember that the key existed while Xcode ran, and its path for the clean-up check
for i in "$@"; do [ -f "$i" ] && case "$i" in *AuthKey_*) echo "$i" > "$KEYPATH_LOG";; esac; done
if [ "$1" = archive ]; then
  [ -z "${FAIL_ARCHIVE:-}" ] || { echo "archive failed"; exit 65; }
  while [ $# -gt 0 ]; do
    case "$1" in
      -archivePath) mkdir -p "$2/Products/Applications/Doddy.app"; arch=$2 ;;
      -clonedSourcePackagesDirPath) mkdir -p "$2" ;;
    esac; shift
  done
elif [ "$1" = -exportArchive ]; then
  while [ $# -gt 0 ]; do
    case "$1" in
      -exportPath) mkdir -p "$2"; touch "$2/Doddy.ipa" ;;
      -exportOptionsPlist) cp "$2" "$PLIST_COPY" ;;
    esac; shift
  done
fi
echo "xcodebuild output line"
EOF
cat > "$bin/xcrun" <<'EOF'
#!/usr/bin/env bash
echo "xcrun $* [API_PRIVATE_KEYS_DIR=${API_PRIVATE_KEYS_DIR:-}]" >> "$CALLS_LOG"
echo "altool output line"
EOF
chmod +x "$bin"/*

export PATH="$bin:$PATH" CALLS_LOG="$log" KEYPATH_LOG="$tmp/keypath" PLIST_COPY="$tmp/ExportOptions.copy"
KEYTEXT="SECRET-KEY-TEXT-1234567890"
base_env() {
  export APP_STORE_CONNECT_KEY_ID=KEY1234567 APP_STORE_CONNECT_ISSUER_ID=11111111-2222-3333-4444-555555555555
  export APP_STORE_CONNECT_API_KEY="$KEYTEXT" DEVELOPMENT_TEAM=TEAM123456 BUILD_NUMBER=42
  unset MARKETING_VERSION BUNDLE_ID PUSH FAIL_ARCHIVE
  export OUT_DIR="$tmp/out"
  : > "$log"; rm -rf "$tmp/out" "$tmp/keypath" "$PLIST_COPY"
}

failures=0
check() { if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; failures=$((failures + 1)); fi; }
called() { grep -q -- "$1" "$log"; }

# 1. Setup mistakes build nothing.
base_env; unset APP_STORE_CONNECT_API_KEY
out=$(scripts/testflight.sh validate 2>&1); rc=$?
check "a missing secret exits 2 and names it" $([ $rc -eq 2 ] && grep -q APP_STORE_CONNECT_API_KEY <<<"$out"; echo $?)
check "and nothing was run" $([ ! -s "$log" ]; echo $?)
base_env; scripts/testflight.sh bogus >/dev/null 2>&1; check "an unknown mode exits 2" $([ $? -eq 2 ]; echo $?)
base_env; BUILD_NUMBER=4x2 scripts/testflight.sh validate >/dev/null 2>&1; check "a non-numeric build number exits 2" $([ $? -eq 2 ]; echo $?)
check "and nothing was run (build number)" $([ ! -s "$log" ]; echo $?)

# 2. validate: archives, exports locally, validates, never uploads.
base_env
out=$(scripts/testflight.sh validate 2>&1); rc=$?
check "validate succeeds" $([ $rc -eq 0 ]; echo $?)
check "it generates the project, archives Release with cloud signing" $(called "^make project" && called "xcodebuild archive.*-configuration Release.*-allowProvisioningUpdates.*-authenticationKeyID KEY1234567"; echo $?)
check "the build number and team are passed" $(called "CURRENT_PROJECT_VERSION=42" && called "DEVELOPMENT_TEAM=TEAM123456"; echo $?)
check "push entitlements are on by default" $(called "DODDY_APP_ENTITLEMENTS=Config/Doddy-Push-AppGroup.entitlements"; echo $?)
check "no bundle ID or version override unless asked" $(! called "DODDY_APP_BUNDLE_IDENTIFIER" && ! called "MARKETING_VERSION"; echo $?)
check "the export destination is local, not upload" $(grep -q '<key>destination</key><string>export</string>' "$PLIST_COPY"; echo $?)
check "it validates the .ipa with altool and the key folder" $(called "xcrun altool --validate-app -f .*Doddy.ipa -t ios --apiKey KEY1234567 --apiIssuer 11111111" && called "API_PRIVATE_KEYS_DIR=/"; echo $?)
check "it never calls an upload" $(! called "upload-app" && ! grep -q 'destination</key><string>upload' "$PLIST_COPY"; echo $?)

# 3. The key is never printed and is deleted.
check "the key text is not in the output" $(! grep -q "$KEYTEXT" <<<"$out"; echo $?)
check "the key text is not in any recorded call" $(! grep -q "$KEYTEXT" "$log"; echo $?)
kp=$(cat "$tmp/keypath" 2>/dev/null)
check "Xcode saw a key file while it ran" $([ -n "$kp" ]; echo $?)
check "the key file is gone afterwards" $([ -n "$kp" ] && [ ! -e "$kp" ]; echo $?)

# 4. upload: export destination is upload, no altool.
base_env
scripts/testflight.sh upload >/dev/null 2>&1; rc=$?
check "upload succeeds" $([ $rc -eq 0 ]; echo $?)
check "the export destination is upload" $(grep -q '<key>destination</key><string>upload</string>' "$PLIST_COPY"; echo $?)
check "altool validation is not run in upload mode" $(! called "altool"; echo $?)

# 5. Options.
base_env; PUSH=0 BUNDLE_ID=com.example.shipping MARKETING_VERSION=1.2.3 scripts/testflight.sh validate >/dev/null 2>&1
check "PUSH=0 leaves the push entitlements out" $(! called "Doddy-Push-AppGroup"; echo $?)
check "BUNDLE_ID is passed as DODDY_APP_BUNDLE_IDENTIFIER" $(called "DODDY_APP_BUNDLE_IDENTIFIER=com.example.shipping"; echo $?)
check "MARKETING_VERSION is passed" $(called "MARKETING_VERSION=1.2.3"; echo $?)

# 6. A failed archive stops everything.
base_env; FAIL_ARCHIVE=1 scripts/testflight.sh upload >/dev/null 2>&1; rc=$?
check "a failed archive fails the script" $([ $rc -ne 0 ]; echo $?)
check "and nothing is exported or uploaded" $(! called "exportArchive" && ! called "altool"; echo $?)

[ "$failures" -eq 0 ] && echo "PASS: testflight" || { echo "$failures failure(s)"; exit 1; }

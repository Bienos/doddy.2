#!/usr/bin/env bash
# Archives the Doddy iPhone app for the App Store and either VALIDATES it with App Store Connect or UPLOADS it to
# TestFlight (ADR-694). The workflow .github/workflows/testflight.yml runs this on a hosted Mac; you can run it on your
# own Mac the same way.
#
#   scripts/testflight.sh validate     archive, export an .ipa, ask App Store Connect to validate it. Uploads nothing.
#   scripts/testflight.sh upload       archive and upload to App Store Connect (TestFlight processes it afterwards).
#
# Needed in the environment (the workflow takes the first three from the `testflight` environment's secrets):
#   APP_STORE_CONNECT_KEY_ID      the API key's ID (App Store Connect > Users and Access > Integrations > Keys)
#   APP_STORE_CONNECT_ISSUER_ID   the issuer ID shown on that page
#   APP_STORE_CONNECT_API_KEY     the whole text of the AuthKey_XXXX.p8 file
#   DEVELOPMENT_TEAM              your Team ID (Membership page; not a secret)
#   BUILD_NUMBER                  a whole number higher than every build already uploaded for this version
# Optional:
#   MARKETING_VERSION             e.g. 0.1.0 (default: the project's)
#   BUNDLE_ID                     overrides DODDY_APP_BUNDLE_IDENTIFIER (default: the project's; see
#                                 docs/implementation/TESTFLIGHT_VALIDATION.md before changing it)
#   PUSH                          1 (default) builds with Config/Doddy-Push-AppGroup.entitlements; 0 without push
#   OUT_DIR                       where the archive, export and logs go (default build/testflight)
#
# Signing is Xcode's cloud-managed signing through the API key (-allowProvisioningUpdates): no certificate or
# profile is stored anywhere. The key is written to a private temporary folder, passed to Xcode and altool by path,
# and deleted when the script ends, whatever happens. It is never printed. Exit 2 is a setup mistake (nothing was
# built); any other non-zero exit is a failed step, named in the output.
set -euo pipefail
cd "$(dirname "$0")/.."

mode=${1:-}
case "$mode" in validate | upload) ;; *) echo "Usage: $0 validate|upload" >&2; exit 2 ;; esac

missing=()
for v in APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_API_KEY DEVELOPMENT_TEAM BUILD_NUMBER; do
  [ -n "${!v:-}" ] || missing+=("$v")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing: ${missing[*]}. Nothing was built." >&2; exit 2
fi
case "$BUILD_NUMBER" in '' | *[!0-9]*) echo "BUILD_NUMBER must be a whole number, got '$BUILD_NUMBER'." >&2; exit 2 ;; esac

out=${OUT_DIR:-build/testflight}
archive="$out/Doddy.xcarchive"
packages="$out/SourcePackages"
export_dir="$out/export"
mkdir -p "$out"

keydir=$(mktemp -d)
chmod 700 "$keydir"
trap 'rm -rf "$keydir"' EXIT
keyfile="$keydir/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
umask 077
printf '%s\n' "$APP_STORE_CONNECT_API_KEY" > "$keyfile"

auth=(-authenticationKeyPath "$keyfile" -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID")

step() { echo; echo "=== $*"; }

step "Generate the Xcode project"
make project

step "Archive (Release, build $BUILD_NUMBER)"
settings=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
[ -z "${MARKETING_VERSION:-}" ] || settings+=(MARKETING_VERSION="$MARKETING_VERSION")
[ -z "${BUNDLE_ID:-}" ] || settings+=(DODDY_APP_BUNDLE_IDENTIFIER="$BUNDLE_ID")
[ "${PUSH:-1}" = "0" ] || settings+=(DODDY_APP_ENTITLEMENTS=Config/Doddy-Push-AppGroup.entitlements)
rm -rf "$archive" "$export_dir"
xcodebuild archive \
  -project Doddy.xcodeproj -scheme Doddy -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive" -clonedSourcePackagesDirPath "$packages" \
  -allowProvisioningUpdates "${auth[@]}" "${settings[@]}" \
  | tee "$out/archive.log" | tail -n 40
[ -d "$archive" ] || { echo "FAILED: no archive was made (see $out/archive.log)." >&2; exit 1; }

step "Debug symbols of binary packages (ADR-693)"
# A missing dSYM is a warning in App Store Connect, never a reason to stop.
scripts/copy_binary_dsyms.sh "$archive" "$packages" || echo "warning: copying the binary packages' dSYMs failed; the upload goes on without them."

step "Export options ($mode)"
destination=export
[ "$mode" != upload ] || destination=upload
cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$destination</string>
	<key>teamID</key><string>$DEVELOPMENT_TEAM</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF
echo "destination: $destination"

step "Export the archive"
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" \
  -exportOptionsPlist "$out/ExportOptions.plist" -allowProvisioningUpdates "${auth[@]}" \
  | tee "$out/export.log" | tail -n 40

if [ "$mode" = validate ]; then
  ipa=$(find "$export_dir" -maxdepth 1 -name '*.ipa' -print -quit 2>/dev/null || true)
  [ -n "$ipa" ] || { echo "FAILED: the export made no .ipa (see $out/export.log)." >&2; exit 1; }
  step "Validate with App Store Connect (nothing is uploaded)"
  API_PRIVATE_KEYS_DIR="$keydir" xcrun altool --validate-app -f "$ipa" -t ios \
    --apiKey "$APP_STORE_CONNECT_KEY_ID" --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID" \
    | tee "$out/validate.log"
  echo; echo "Validation finished. Read $out/validate.log: errors block an upload, warnings do not."
else
  echo; echo "Uploaded. App Store Connect now processes the build; it shows in TestFlight when that finishes (minutes to an hour)."
fi

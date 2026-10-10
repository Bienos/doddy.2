#!/usr/bin/env bash
# Capability guard. Settings/Home copy makes specific privacy claims; this check keeps them true:
#  - the app's own networking lives in four files: the voice token client (one POST of the access
#    code to the token server), Connected Apps' transport (to the Doddy server), the typed-assistant
#    transport (to the M2 gateway, ADR-110) and the messaging server transport (server/messaging,
#    ADR-148); the ElevenLabs SDK does the voice connection,
#  - the system authentication browser is used only by Connected Apps,
#  - audio/ElevenLabs code only inside DoddyApp/Features/Voice,
#  - calendar (EventKit) and contacts code only inside DoddyApp/Infrastructure/Connections,
#  - location and Apple Maps search code (place reminders, ADR-196) only there too, and never
#    "Always" location, background location or significant-change tracking,
#  - photo text reading (Vision) and the photo picker only inside DoddyApp/Features/Photos, never the
#    camera or the whole photo library (ADR-218),
#  - no speech framework, accounts, analytics or crash SDKs, no secrets (server/messaging and
#    render.yaml are checked for key values only: the server legitimately names key headers),
#  - permission keys only for the microphone, calendar, reminders, contacts and "While Using" location,
#  - backend: Composio tool slugs only in the adapters and the tool catalog (and the mock that mimics
#    their answers), no write tools beyond the two reviewed ones (Gmail draft, Todoist task), no proxy execution,
#    and Monid only in the web search module, with one fixed endpoint (no discover/inspect: the model
#    can never pick another paid endpoint).
# Exit 0 = clean, 1 = violation.
set -euo pipefail
cd "$(dirname "$0")/.."

dirs=(DoddyApp DoddyWidgets Shared Packages/DoddyCore/Sources)
voice_dir=DoddyApp/Features/Voice
connections_dir=DoddyApp/Infrastructure/Connections
anywhere='NWConnection|import Network|import Speech|SFSpeech|import CloudKit|import FirebaseCore|import Sentry|import Analytics'
token_client=DoddyApp/Features/Voice/VoiceTokenClient.swift
network_file=DoddyApp/Infrastructure/URLSessionTransport.swift
assistant_transport=DoddyApp/Infrastructure/Network/AppHTTPTransport.swift
messaging_transport=DoddyApp/Infrastructure/Server/ServerHTTPTransport.swift
network_only='URLSession([^A-Za-z]|$)|URLRequest([^A-Za-z]|$)'
web_auth_file=DoddyApp/Features/ConnectedApps/SystemWebAuthenticator.swift
web_auth_only='import AuthenticationServices|ASWebAuthenticationSession|WKWebView|import WebKit|SFSafariViewController'
voice_only='import AVFoundation|import AVFAudio|AVAudio|import ElevenLabs'
connections_only='import EventKit|EKEventStore|EKEvent|EKReminder|import Contacts|CNContact|import CoreLocation|CLLocationManager|CLLocationUpdate|import MapKit|MKLocalSearch|UNLocationNotificationTrigger'
photos_dir=DoddyApp/Features/Photos
photos_only='import Vision|VNRecognizeText|VNImageRequestHandler|import PhotosUI|PhotosPicker'
photo_library='PHPhotoLibrary\.(requestAuthorization|authorizationStatus)|PHAsset\.fetch|UIImagePickerController|AVCaptureSession|NSCameraUsageDescription|NSPhotoLibrary(Add)?UsageDescription'
location_tracking='requestAlwaysAuthorization|NSLocationAlways|allowsBackgroundLocationUpdates|startMonitoringSignificantLocationChanges|startMonitoringVisits|CLBackgroundActivitySession|UIBackgroundModes.*location'
messaging_secrets='(sk-[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}|AC[0-9a-f]{32}|SK[0-9a-f]{32}|BEGIN (RSA |EC )?PRIVATE KEY|(KEY|TOKEN|SECRET)=[^[:space:]]{8,})'
secrets='(sk-[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}|ak_[A-Za-z0-9_-]{20,}|monid_(live|test)_[A-Za-z0-9_-]{16,}|xi-api-key|api[_-]?key[[:space:]]*[:=][[:space:]]*"[^"]+"|BEGIN (RSA |EC )?PRIVATE KEY)'
allowed_permissions='NSMicrophoneUsageDescription|NSCalendarsFullAccessUsageDescription|NSRemindersFullAccessUsageDescription|NSContactsUsageDescription|NSLocationWhenInUseUsageDescription'
backend_src=backend/src
# Drops comment-only lines from `grep -n` output (file:line:   // …, /// …, * …).
code_only() { grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)'; }
composio_adapter=backend/src/providers/composio.ts
# Online accounts (Gmail, Drive, Notion, Todoist): the catalog names each slug once; the mock returns
# the same answer shapes. Nothing else may name a slug.
tools_catalog=backend/src/tools/catalog.ts
tools_mock=backend/src/tools/mock.ts
# Web search: the only file that may talk to Monid.
websearch=backend/src/tools/websearch.ts

status=0
if grep -RInE --include='*.swift' --include='*.plist' "$anywhere" "${dirs[@]}" Config; then
  echo "FAIL: forbidden capability code found (see matches above)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$network_only" "${dirs[@]}" | code_only | grep -v -e "^$network_file:" -e "^$token_client:" -e "^$assistant_transport:" -e "^$messaging_transport:"; then
  echo "FAIL: networking code outside $network_file, $assistant_transport, $messaging_transport and $token_client." >&2; status=1
fi
if grep -RInE --include='*.swift' "$web_auth_only" "${dirs[@]}" | code_only | grep -v "^$web_auth_file:"; then
  echo "FAIL: web authentication / web views outside $web_auth_file." >&2; status=1
fi
if grep -RInE --include='*.swift' "$voice_only" "${dirs[@]}" | grep -v "^$voice_dir/"; then
  echo "FAIL: audio/ElevenLabs code outside $voice_dir." >&2; status=1
fi
if grep -RInE --include='*.swift' "$connections_only" "${dirs[@]}" | grep -v "^$connections_dir/"; then
  echo "FAIL: calendar, contacts or location code outside $connections_dir." >&2; status=1
fi
if grep -RInE --include='*.swift' "$photos_only" "${dirs[@]}" | grep -v "^$photos_dir/"; then
  echo "FAIL: photo reading or the photo picker outside $photos_dir." >&2; status=1
fi
if grep -RInE "$photo_library" "${dirs[@]}" project.yml Config | code_only; then
  echo "FAIL: camera or photo library access; photo notes use Apple's picker only (ADR-218)." >&2; status=1
fi
if grep -RInE "$location_tracking" "${dirs[@]}" project.yml | code_only; then
  echo "FAIL: \"Always\" or background location is not allowed; place reminders use \"While Using\" only." >&2; status=1
fi
if [ -d "$backend_src" ]; then
  if grep -RInE '(^|[^A-Z_])(GOOGLECALENDAR|GOOGLESUPER|GMAIL|GOOGLEDRIVE|NOTION|TODOIST)_[A-Z]' --include='*.ts' "$backend_src" | code_only | grep -v -e "^$composio_adapter:" -e "^$tools_catalog:" -e "^$tools_mock:"; then
    echo "FAIL: Composio tool slugs outside $composio_adapter, $tools_catalog and $tools_mock." >&2; status=1
  fi
  if grep -RInE 'GOOGLECALENDAR_(CREATE|UPDATE|DELETE|PATCH|QUICK_ADD|MOVE|REMOVE|CLEAR|INSERT)' "$backend_src"; then
    echo "FAIL: calendar write tool referenced in the backend." >&2; status=1
  fi
  # The only write tools allowed are GMAIL_CREATE_EMAIL_DRAFT and TODOIST_CREATE_TASK (each needs a fresh
  # on-screen approval). Anything that sends, deletes, shares, edits or labels is refused here.
  if grep -RInE 'GMAIL_(SEND|DELETE|TRASH|REPLY|FORWARD|MODIFY|BATCH|ADD|REMOVE|CREATE_LABEL|PATCH|UPDATE|MOVE|UNTRASH)|GOOGLEDRIVE_(CREATE|UPDATE|DELETE|ADD_FILE_SHARING|EDIT|COPY|MOVE|TRASH|UPLOAD|DOWNLOAD|EMPTY|REMOVE)|NOTION_(CREATE|UPDATE|DELETE|ADD|APPEND|ARCHIVE|INSERT|DUPLICATE|MOVE)|TODOIST_(UPDATE|DELETE|CLOSE|REOPEN|BULK|MOVE|QUICK_ADD|ARCHIVE|ADD)' "$backend_src"; then
    echo "FAIL: a write tool beyond the reviewed Gmail draft and Todoist task is referenced in the backend." >&2; status=1
  fi
  if grep -RInE 'tools\.proxy|proxyExecute|COMPOSIO_MULTI_EXECUTE|COMPOSIO_REMOTE' "$backend_src"; then
    echo "FAIL: generic proxy/meta-tool execution in the backend." >&2; status=1
  fi
  if grep -RInE 'monid\.ai|/v1/run[^s]|/v1/runs/' --include='*.ts' "$backend_src" | code_only | grep -v "^$websearch:"; then
    echo "FAIL: Monid called outside $websearch." >&2; status=1
  fi
  if grep -RInE '/v1/(discover|inspect)|monid_(discover|inspect|run)' --include='*.ts' "$backend_src"; then
    echo "FAIL: Monid endpoint discovery in the backend; web search must stay one fixed endpoint." >&2; status=1
  fi
fi
secret_paths=("${dirs[@]}" project.yml scripts)
for extra in backend/src backend/test contracts .env.example backend/.env.example; do [ -e "$extra" ] && secret_paths+=("$extra"); done
if grep -RInE "$secrets" "${secret_paths[@]}" --exclude=check_forbidden_capabilities.sh; then
  echo "FAIL: possible secret found." >&2; status=1
fi
if [ -d server/messaging ] && grep -RInE "$messaging_secrets" server/messaging render.yaml --exclude-dir=node_modules --exclude-dir=dist; then
  echo "FAIL: possible secret found in server/messaging or render.yaml." >&2; status=1
fi
if grep -RnoE 'NS[A-Za-z]+UsageDescription' project.yml DoddyApp DoddyWidgets Config | grep -vE "$allowed_permissions"; then
  echo "FAIL: only the microphone, calendar, reminders and contacts permissions are allowed." >&2; status=1
fi
[ "$status" -eq 0 ] && echo "PASS: networking only in the token client, URLSessionTransport, the assistant transport and the messaging transport, web auth only in Connected Apps, audio only in Voice, calendar, contacts and location only in Connections, photo reading and the photo picker only in Photos (no camera or photo library access), no Always/background location, no speech/analytics, no secrets, permissions limited to microphone, calendar, reminders, contacts and While Using location; backend has no write tools beyond the reviewed Gmail draft and Todoist task, and no proxy execution."
exit "$status"

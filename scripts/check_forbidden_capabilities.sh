#!/usr/bin/env bash
# Capability guard. Settings/Home copy makes specific privacy claims; this check keeps them true:
#  - the app's own networking lives in four files: the voice token client (one POST of the access
#    code to the token server), Connected Apps' transport (to the Doddy server), the typed-assistant
#    transport (to the M2 gateway, ADR-110) and the messaging server transport (server/messaging,
#    ADR-148); the ElevenLabs SDK does the voice connection, except the OpenAI Realtime test voice
#    (ADR-265), whose WebSocket lives in one file in Features/Voice, and the exchange-rate client
#    (ADR-291), which downloads only the ECB's public rates file,
#  - the system authentication browser is used only by Connected Apps,
#  - ElevenLabs code only inside DoddyApp/Features/Voice; audio (AVFoundation) only there and in
#    DoddyApp/Features/VoiceMemos (recording and playing voice memos, ADR-230),
#  - speech recognition (Speech) only inside DoddyApp/Features/VoiceMemos, and every recognition
#    request there sets requiresOnDeviceRecognition = true (nothing is sent to Apple's servers),
#  - calendar (EventKit) and contacts code only inside DoddyApp/Infrastructure/Connections,
#  - the "Hey Doddy" wake-word engine (Picovoice Porcupine, ADR-254) only in WakeWordListener.swift,
#  - location and Apple Maps search code (place reminders, ADR-196) only there too, and never
#    "Always" location, background location or significant-change tracking,
#  - on-device meaning search (NaturalLanguage embeddings) only inside DoddyApp/Features/Meaning (ADR-227);
#    the NaturalLanguage import also in ReadAloudController, for its language recognizer only (ADR-243),
#  - photo text reading (Vision) and the photo picker only inside DoddyApp/Features/Photos, never the
#    camera or the whole photo library (ADR-218),
#  - WatchConnectivity only in DoddyApp/Features/Watch and the watch app (DoddyWatch), which has no
#    database or networking of its own (ADR-232),
#  - no accounts, analytics or crash SDKs, no secrets (server/messaging and
#    render.yaml are checked for key values only: the server legitimately names key headers),
#  - AlarmKit only inside DoddyApp/Features/Alarms, plus the shared alarm metadata and the snooze
#    countdown widget (ADR-260, ADR-283),
#  - CloudKit (shared lists through the user's iCloud) only inside DoddyApp/Features/Sharing (ADR-263),
#  - permission keys only for alarms (AlarmKit, iOS 26), the microphone, speech recognition (on-device, voice memos), calendar,
#    reminders, contacts and "While Using" location,
#  - backend: Composio tool slugs only in the adapters and the tool catalog (and the mock that mimics
#    their answers), no write tools beyond the reviewed ones (Gmail draft; Todoist add, complete and move,
#    ADR-294), no proxy execution,
#    and Monid only in the web search module, with one fixed endpoint (no discover/inspect: the model
#    can never pick another paid endpoint).
# Exit 0 = clean, 1 = violation.
set -euo pipefail
cd "$(dirname "$0")/.."

dirs=(DoddyApp DoddyWidgets DoddyWatch DoddyWatchWidgets Shared Packages/DoddyCore/Sources)
voice_dir=DoddyApp/Features/Voice
connections_dir=DoddyApp/Infrastructure/Connections
anywhere='NWConnection|import Network|import FirebaseCore|import Sentry|import Analytics'
sharing_dir=DoddyApp/Features/Sharing
sharing_only='import CloudKit|CKContainer|CKDatabase|UICloudSharingController'
token_client=DoddyApp/Features/Voice/VoiceTokenClient.swift
openai_voice=DoddyApp/Features/Voice/OpenAIRealtimeSession.swift
network_file=DoddyApp/Infrastructure/URLSessionTransport.swift
assistant_transport=DoddyApp/Infrastructure/Network/AppHTTPTransport.swift
messaging_transport=DoddyApp/Infrastructure/Server/ServerHTTPTransport.swift
# The ECB's public daily rates file, one fixed address (ADR-291).
rates_client=DoddyApp/Infrastructure/Network/ExchangeRateClient.swift
network_only='URLSession([^A-Za-z]|$)|URLRequest([^A-Za-z]|$)'
web_auth_file=DoddyApp/Features/ConnectedApps/SystemWebAuthenticator.swift
web_auth_only='import AuthenticationServices|ASWebAuthenticationSession|WKWebView|import WebKit|SFSafariViewController'
voice_only='import ElevenLabs'
memos_dir=DoddyApp/Features/VoiceMemos
audio_only='import AVFoundation|import AVFAudio|AVAudio'
speech_only='import Speech|SFSpeech'
watch_link_dir=DoddyApp/Features/Watch
watch_app_dir=DoddyWatch
watch_only='import WatchConnectivity|WCSession'
alarms_dir=DoddyApp/Features/Alarms
alarms_only='import AlarmKit|AlarmManager'
connections_only='import EventKit|EKEventStore|EKEvent|EKReminder|import Contacts|CNContact|import CoreLocation|CLLocationManager|CLLocationUpdate|import MapKit|MKLocalSearch|UNLocationNotificationTrigger'
meaning_dir=DoddyApp/Features/Meaning
meaning_only='NLContextualEmbedding|NLEmbedding'
# Read aloud picks a voice by the note's language (NLLanguageRecognizer, on the iPhone, ADR-243).
natural_language_files='^(DoddyApp/Features/Meaning/|DoddyApp/Features/Voice/ReadAloudController.swift:)'
photos_dir=DoddyApp/Features/Photos
photos_only='import Vision|VNRecognizeText|VNImageRequestHandler|import PhotosUI|PhotosPicker'
photo_library='PHPhotoLibrary\.(requestAuthorization|authorizationStatus)|PHAsset\.fetch|UIImagePickerController|AVCaptureSession|NSCameraUsageDescription|NSPhotoLibrary(Add)?UsageDescription'
location_tracking='requestAlwaysAuthorization|NSLocationAlways|allowsBackgroundLocationUpdates|startMonitoringSignificantLocationChanges|startMonitoringVisits|CLBackgroundActivitySession|UIBackgroundModes.*location'
messaging_secrets='(sk-[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}|AC[0-9a-f]{32}|SK[0-9a-f]{32}|BEGIN (RSA |EC )?PRIVATE KEY|(KEY|TOKEN|SECRET)=[^[:space:]]{8,})'
secrets='(sk-[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}|ak_[A-Za-z0-9_-]{20,}|monid_(live|test)_[A-Za-z0-9_-]{16,}|xi-api-key|api[_-]?key[[:space:]]*[:=][[:space:]]*"[^"]+"|BEGIN (RSA |EC )?PRIVATE KEY)'
allowed_permissions='NSAlarmKitUsageDescription|NSMicrophoneUsageDescription|NSSpeechRecognitionUsageDescription|NSCalendarsFullAccessUsageDescription|NSRemindersFullAccessUsageDescription|NSContactsUsageDescription|NSLocationWhenInUseUsageDescription'
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
# "Hey Doddy" (ADR-254): the wake-word engine and its recorder in one file, so "what it hears
# isn't kept or sent" stays checkable.
wake_file=DoddyApp/Features/Voice/WakeWordListener.swift
wake_only='import Porcupine|PorcupineManager|Porcupine\(|import ios_voice_processor|VoiceProcessor\.instance'

status=0
if grep -RInE --include='*.swift' --include='*.plist' "$anywhere" "${dirs[@]}" Config; then
  echo "FAIL: forbidden capability code found (see matches above)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$network_only" "${dirs[@]}" | code_only | grep -v -e "^$network_file:" -e "^$token_client:" -e "^$assistant_transport:" -e "^$messaging_transport:" -e "^$openai_voice:" -e "^$rates_client:"; then
  echo "FAIL: networking code outside $network_file, $assistant_transport, $messaging_transport, $token_client, $openai_voice and $rates_client." >&2; status=1
fi
# The rates client may only fetch the one fixed ECB file (ADR-291), never an address it is given.
if [ -f "$rates_client" ] && grep -nE 'URL\(string|URLComponents|appendingPathComponent|https?://' "$rates_client" | code_only; then
  echo "FAIL: $rates_client may only fetch ExchangeRateSource.url." >&2; status=1
fi
if grep -RInE --include='*.swift' "$web_auth_only" "${dirs[@]}" | code_only | grep -v "^$web_auth_file:"; then
  echo "FAIL: web authentication / web views outside $web_auth_file." >&2; status=1
fi
if grep -RInE --include='*.swift' "$wake_only" "${dirs[@]}" | code_only | grep -v "^$wake_file:"; then
  echo "FAIL: wake-word engine code outside $wake_file." >&2; status=1
fi
if grep -RInE --include='*.swift' "$voice_only" "${dirs[@]}" | grep -v "^$voice_dir/"; then
  echo "FAIL: ElevenLabs code outside $voice_dir." >&2; status=1
fi
if grep -RInE --include='*.swift' "$audio_only" "${dirs[@]}" | grep -v -e "^$voice_dir/" -e "^$memos_dir/"; then
  echo "FAIL: audio code outside $voice_dir and $memos_dir." >&2; status=1
fi
if grep -RInE --include='*.swift' "$speech_only" "${dirs[@]}" | grep -v "^$memos_dir/"; then
  echo "FAIL: speech recognition outside $memos_dir (ADR-230)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$watch_only" "${dirs[@]}" | grep -v -e "^$watch_link_dir/" -e "^$watch_app_dir/"; then
  echo "FAIL: WatchConnectivity outside $watch_link_dir and $watch_app_dir (ADR-232)." >&2; status=1
fi
# The watch app keeps no database and makes no network calls of its own.
if grep -RInE --include='*.swift' 'import GRDB|DoddyPersistence|URLSession|import Network' "$watch_app_dir"; then
  echo "FAIL: the watch app may only show the iPhone's snapshot and ask the iPhone (ADR-232)." >&2; status=1
fi
if [ -d "$memos_dir" ]; then
  for f in $(grep -RlE --include='*.swift' 'SFSpeech(URL|AudioBuffer)RecognitionRequest' "$memos_dir"); do
    if ! grep -qE 'requiresOnDeviceRecognition = true' "$f"; then
      echo "FAIL: $f makes a speech request without requiresOnDeviceRecognition = true." >&2; status=1
    fi
  done
  if grep -RInE --include='*.swift' 'requiresOnDeviceRecognition = false' "$memos_dir"; then
    echo "FAIL: speech recognition may not leave the iPhone (ADR-230)." >&2; status=1
  fi
fi
if grep -RInE --include='*.swift' "$connections_only" "${dirs[@]}" | grep -v "^$connections_dir/"; then
  echo "FAIL: calendar, contacts or location code outside $connections_dir." >&2; status=1
fi
if grep -RInE --include='*.swift' "$meaning_only" "${dirs[@]}" | grep -v "^$meaning_dir/"; then
  echo "FAIL: on-device language models outside $meaning_dir (ADR-227)." >&2; status=1
fi
if grep -RInE --include='*.swift' 'import NaturalLanguage' "${dirs[@]}" | grep -vE "$natural_language_files"; then
  echo "FAIL: NaturalLanguage outside $meaning_dir and the read-aloud language check (ADR-227, ADR-243)." >&2; status=1
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
  # The only write tools allowed are GMAIL_CREATE_EMAIL_DRAFT, TODOIST_CREATE_TASK and, since ADR-294,
  # TODOIST_CLOSE_TASK_V1 and TODOIST_UPDATE_TASK (each needs a fresh on-screen approval bound to the
  # task Todoist returned). Anything that sends, deletes, shares, edits or labels is refused here, and
  # the two Todoist writes may appear only in the catalog and its mock.
  if grep -RInE 'GMAIL_(SEND|DELETE|TRASH|REPLY|FORWARD|MODIFY|BATCH|ADD|REMOVE|CREATE_LABEL|PATCH|UPDATE|MOVE|UNTRASH)|GOOGLEDRIVE_(CREATE|UPDATE|DELETE|ADD_FILE_SHARING|EDIT|COPY|MOVE|TRASH|UPLOAD|DOWNLOAD|EMPTY|REMOVE)|NOTION_(CREATE|UPDATE|DELETE|ADD|APPEND|ARCHIVE|INSERT|DUPLICATE|MOVE)|TODOIST_(UPDATE|DELETE|CLOSE|REOPEN|BULK|MOVE|QUICK_ADD|ARCHIVE|ADD)' "$backend_src" \
    | grep -vE "^($tools_catalog|$tools_mock):[0-9]+:.*TODOIST_(CLOSE_TASK_V1|UPDATE_TASK)([^A-Z0-9_]|$)" \
    | grep -E 'GMAIL_|GOOGLEDRIVE_|NOTION_|TODOIST_(UPDATE|DELETE|CLOSE|REOPEN|BULK|MOVE|QUICK_ADD|ARCHIVE|ADD)'; then
    echo "FAIL: a write tool beyond the reviewed Gmail draft and the Todoist add, complete and move is referenced in the backend." >&2; status=1
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
if grep -RInE --include='*.swift' "$sharing_only" "${dirs[@]}" | code_only | grep -v "^$sharing_dir/"; then
  echo "FAIL: CloudKit outside $sharing_dir." >&2; status=1
fi
if grep -RInE --include='*.swift' "$alarms_only" "${dirs[@]}" | code_only | grep -v -e "^$alarms_dir/" -e "^Shared/Alarms/DoddyAlarmMetadata.swift:" -e "^DoddyWidgets/AlarmLiveActivity.swift:"; then
  echo "FAIL: AlarmKit outside $alarms_dir." >&2; status=1
fi
if grep -RnoE 'NS[A-Za-z]+UsageDescription' project.yml DoddyApp DoddyWidgets Config | grep -vE "$allowed_permissions"; then
  echo "FAIL: only the alarms, microphone, speech recognition, calendar, reminders, contacts and While Using location permissions are allowed." >&2; status=1
fi
[ "$status" -eq 0 ] && echo "PASS: networking only in the token client, URLSessionTransport, the assistant transport, the messaging transport, the OpenAI test voice and the ECB rates client, web auth only in Connected Apps, ElevenLabs only in Voice, audio only in Voice and Voice memos, on-device speech recognition only in Voice memos, calendar, contacts and location only in Connections, photo reading and the photo picker only in Photos (no camera or photo library access), no Always/background location, no analytics, no secrets, AlarmKit only in Alarms, CloudKit only in Sharing, permissions limited to alarms, microphone, speech recognition, calendar, reminders, contacts and While Using location; backend has no write tools beyond the reviewed Gmail draft and Todoist add, complete and move, and no proxy execution."
exit "$status"

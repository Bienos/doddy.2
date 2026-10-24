#!/usr/bin/env bash
# Capability guard. Settings/Home copy makes specific privacy claims; this check keeps them true:
#  - the app's own networking lives in four files: the voice token client (DODDY's session and the
#    provider-token requests, all to the token server; ADR-494), Connected Apps' transport (to the Doddy server), the typed-assistant
#    transport (to the M2 gateway, ADR-110) and the messaging server transport (server/messaging,
#    ADR-148); the ElevenLabs SDK does the voice connection, except the OpenAI Realtime test voice
#    (ADR-265), whose WebSocket lives in one file in Features/Voice, the exchange-rate client
#    (ADR-300), which downloads only the ECB's public rates file, and the Open Food Facts client
#    (ADR-631), which asks only the address DoddyCore builds from a checked barcode, and the InPost
#    tracking client (ADR-641), which asks only the address DoddyCore builds from a checked parcel number;
#    there is no inFakt client yet (ADR-640: its wire format is unverified), so nothing may talk to inFakt,
#  - the Keychain (Security framework) only in the files that already hold a token or key, and a key the
#    person pasted in for their own account (AccountKeyStore, ADR-640) is read only by the one file that
#    will put it in a request header, never by a screen,
#  - the system authentication browser is used only by Connected Apps; Sign in with Apple
#    (AuthenticationServices without a browser or web view) only in the voice account sign-in
#    (VoiceAccessGate, VoiceAuthSession), whose calls go to the voice token server's
#    /api/voice-auth (ADR-484; they live in the token client since ADR-494), and no password,
#    passkey or credential-provider API anywhere (ADR-494),
#  - ASK-01 (ADR-483): every voice tool asks first. Each tool in voice-agent/tools.json runs on the
#    phone with an x_doddy.ask; every server tool has a card (preview) and runs only through the
#    one approval gate (backend/src/tools/askFirst.ts); the voice controller checks AskFirst
#    before any tool runs,
#  - ElevenLabs code only inside DoddyApp/Features/Voice; audio (AVFoundation) only there, in
#    DoddyApp/Features/VoiceMemos (recording and playing voice memos, ADR-230) and in
#    DoddyApp/Features/Recordings (DODDY Capture: long recordings, ADR-588),
#  - speech recognition (Speech) only inside DoddyApp/Features/VoiceMemos and DoddyApp/Features/Recordings,
#    and every recognition request in either sets requiresOnDeviceRecognition = true (nothing is
#    sent to Apple's servers),
#  - calendar (EventKit), contacts and Motion & Fitness step counts (CoreMotion's pedometer,
#    ADR-568) code only inside DoddyApp/Infrastructure/Connections,
#  - location and Apple Maps search code (place reminders, ADR-196) only there too, and never
#    "Always" location, background location or significant-change tracking,
#  - on-device meaning search (NaturalLanguage embeddings) only inside DoddyApp/Features/Meaning (ADR-227);
#    the NaturalLanguage import also in ReadAloudController, for its language recognizer only (ADR-243),
#  - photo text reading (Vision) and the photo picker only inside DoddyApp/Features/Photos; since
#    ADR-569 (owner, 21 Oct) the photo library is read only in Connections/PhotoLibrarySearch.swift
#    (counts and on-screen pictures, never a write), the camera is iOS's own screen only in
#    Features/Photos/CameraCapture.swift, its permission only in Connections/CameraAccess.swift,
#    and there is no capture session and no write to the photo library anywhere,
#  - WatchConnectivity only in DoddyApp/Features/Watch and the watch app (DoddyWatch), which has no
#    database or networking of its own (ADR-232),
#  - no 1Password code or op:// references in any app target, and no 1Password SDK in the servers
#    (ADR-493: hosts keep plain environment variables; .env.op files are checked by
#    `node tools/secrets/sync.mjs check`),
#  - no accounts, analytics or crash SDKs, no secrets (server/messaging and
#    render.yaml are checked for key values only: the server legitimately names key headers),
#  - AlarmKit only inside DoddyApp/Features/Alarms, plus the shared alarm metadata and the snooze
#    countdown widget (ADR-260, ADR-283),
#  - CloudKit (shared lists through the user's iCloud) only inside DoddyApp/Features/Sharing (ADR-263),
#  - permission keys only for alarms (AlarmKit, iOS 26), the microphone, speech recognition (on-device, voice memos), calendar,
#    reminders, contacts, Motion & Fitness (steps, ADR-568), the camera and reading the photo library (ADR-569)
#    and "While Using" location,
#  - backend: Composio tool slugs only in the adapters and the tool catalog (and the mock that mimics
#    their answers), no write tools beyond the reviewed ones (Gmail draft and reply draft; Todoist add, complete and move,
#    ADR-303), no proxy execution,
#    and Monid only in the web search module, with fixed endpoints (web search, news, places; ADR-489; no discover/inspect: the model
#    can never pick another paid endpoint).
# Exit 0 = clean, 1 = violation.
set -euo pipefail
cd "$(dirname "$0")/.."

dirs=(DoddyApp DoddyWidgets DoddyShare DoddyWatch DoddyWatchWidgets DoddyMac DoddyMacWidgets Shared Packages/DoddyCore/Sources)
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
# The ECB's public daily rates file, one fixed address (ADR-300).
rates_client=DoddyApp/Infrastructure/Network/ExchangeRateClient.swift
# A scanned product's barcode digits, one address built by DoddyCore (ADR-631).
off_client=DoddyApp/Infrastructure/Network/OpenFoodFactsClient.swift
# A parcel number, one address built by DoddyCore (ADR-641).
inpost_client=DoddyApp/Infrastructure/Network/InPostTrackingClient.swift
# The Keychain: the files that hold a token or key. AccountKeyStore (ADR-640) holds keys the person pasted in.
keychain_only='import Security|SecItem(Add|Update|Delete|CopyMatching)|kSecClass'
keychain_files='^(DoddyApp/Infrastructure/(Network/KeychainCredentialStore|Server/ServerKeychainStore|DeviceSession|KeychainSessionStore|AccountKeyStore)|DoddyApp/Features/Voice/VoiceAuthSession)\.swift:'
account_key_store=DoddyApp/Infrastructure/AccountKeyStore.swift
# The one file that will put the inFakt key in a header. It does not exist yet (ADR-640): until a sandbox call
# has settled how inFakt takes an invoice, nothing in the app reads the key or talks to inFakt.
infakt_client=DoddyApp/Infrastructure/Network/InFaktClient.swift
# Every way Foundation can reach the network: sessions and their tasks, URL byte streams,
# loading a web address straight into Data or String, and the older connection APIs. The app's own
# URLSessionTransport type name is not networking and stays allowed.
network_only='URLSession(WebSocketTask|DataTask|DownloadTask|UploadTask|StreamTask|Task|Configuration)?([^A-Za-z]|$)|URLRequest([^A-Za-z]|$)|\.resourceBytes|NSURLConnection|CFReadStream|CFHTTPMessage|contentsOf: *URL\(string:'
web_auth_file=DoddyApp/Features/ConnectedApps/SystemWebAuthenticator.swift
# A browser or web view: only Connected Apps (ADR-484 narrowed this from the whole framework).
web_auth_only='ASWebAuthenticationSession|WKWebView|import WebKit|SFSafariViewController'
# AuthenticationServices itself: Connected Apps, and Sign in with Apple for the voice account.
auth_services='import AuthenticationServices'
apple_sign_in_files='^(DoddyApp/Features/ConnectedApps/SystemWebAuthenticator.swift|DoddyApp/Features/Voice/VoiceAccessGate.swift|DoddyApp/Features/Voice/VoiceAuthSession.swift):'
voice_auth=DoddyApp/Features/Voice/VoiceAuthSession.swift
apple_sign_in_other='ASAuthorizationPasswordProvider|ASAuthorizationPlatformPublicKeyCredential|ASAuthorizationSecurityKey|ASCredentialProvider|ASAuthorizationProviderExtension|ASPasskey'
voice_only='import ElevenLabs'
memos_dir=DoddyApp/Features/VoiceMemos
recordings_dir=DoddyApp/Features/Recordings
audio_only='import AVFoundation|import AVFAudio|AVAudio'
speech_only='import Speech|SFSpeech'
watch_link_dir=DoddyApp/Features/Watch
watch_app_dir=DoddyWatch
watch_only='import WatchConnectivity|WCSession'
alarms_dir=DoddyApp/Features/Alarms
alarms_only='import AlarmKit|AlarmManager'
connections_only='import EventKit|EKEventStore|EKEvent|EKReminder|import Contacts|CNContact|import CoreLocation|CLLocationManager|CLLocationUpdate|import MapKit|MKLocalSearch|UNLocationNotificationTrigger|import CoreMotion|CMPedometer|CMMotionActivityManager'
meaning_dir=DoddyApp/Features/Meaning
meaning_only='NLContextualEmbedding|NLEmbedding'
# Read aloud picks a voice by the note's language (NLLanguageRecognizer, on the iPhone, ADR-243).
natural_language_files='^(DoddyApp/Features/Meaning/|DoddyApp/Features/Voice/ReadAloudController.swift:)'
photos_dir=DoddyApp/Features/Photos
photos_only='import Vision|VNRecognizeText|VNImageRequestHandler|import PhotosUI|PhotosPicker'
# ADR-569: each of these in its one file only.
photo_library_file=DoddyApp/Infrastructure/Connections/PhotoLibrarySearch.swift
photo_library='import Photos($|[^A-Za-z])|PHPhotoLibrary|PHAsset|PHImageManager|PHFetchOptions'
camera_ui_file=DoddyApp/Features/Photos/CameraCapture.swift
camera_ui='UIImagePickerController'
camera_access_file=DoddyApp/Infrastructure/Connections/CameraAccess.swift
# Never, anywhere: a camera session of Doddy's own, or a write to the user's photo library.
camera_and_library_never='AVCaptureSession|AVCapturePhotoOutput|AVCaptureVideoDataOutput|AVCaptureMovieFileOutput|PHAssetChangeRequest|PHAssetCreationRequest|UIImageWriteToSavedPhotosAlbum|NSPhotoLibraryAddUsageDescription|performChanges'
location_tracking='requestAlwaysAuthorization|NSLocationAlways|allowsBackgroundLocationUpdates|startMonitoringSignificantLocationChanges|startMonitoringVisits|CLBackgroundActivitySession|UIBackgroundModes.*location'
messaging_secrets='(sk-[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}|AC[0-9a-f]{32}|SK[0-9a-f]{32}|BEGIN (RSA |EC )?PRIVATE KEY|(KEY|TOKEN|SECRET)=[^[:space:]]{8,})'
secrets='(sk-[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}|ak_[A-Za-z0-9_-]{20,}|monid_(live|test)_[A-Za-z0-9_-]{16,}|xi-api-key|api[_-]?key[[:space:]]*[:=][[:space:]]*"[^"]+"|BEGIN (RSA |EC )?PRIVATE KEY)'
allowed_permissions='NSAlarmKitUsageDescription|NSMicrophoneUsageDescription|NSSpeechRecognitionUsageDescription|NSCalendarsFullAccessUsageDescription|NSRemindersFullAccessUsageDescription|NSContactsUsageDescription|NSMotionUsageDescription|NSCameraUsageDescription|NSPhotoLibraryUsageDescription|NSLocationWhenInUseUsageDescription|NSFaceIDUsageDescription'
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
# The wake-word engine (Picovoice Porcupine, ADR-254) was removed in ADR-549: no file may import it again.
wake_only='import Porcupine|PorcupineManager|Porcupine\(|import ios_voice_processor|VoiceProcessor\.instance'

status=0
if grep -RInE --include='*.swift' --include='*.plist' "$anywhere" "${dirs[@]}" Config; then
  echo "FAIL: forbidden capability code found (see matches above)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$network_only" "${dirs[@]}" | code_only | grep -v -e "^$network_file:" -e "^$token_client:" -e "^$assistant_transport:" -e "^$messaging_transport:" -e "^$openai_voice:" -e "^$rates_client:" -e "^$off_client:" -e "^$inpost_client:" -e "^$voice_auth:"; then
  echo "FAIL: networking code outside $network_file, $assistant_transport, $messaging_transport, $token_client, $voice_auth, $openai_voice, $rates_client, $off_client and $inpost_client." >&2; status=1
fi
# The Keychain only where a token or key already lives (ADR-640).
if grep -RInE --include='*.swift' "$keychain_only" "${dirs[@]}" | code_only | grep -vE "$keychain_files"; then
  echo "FAIL: Keychain code outside the files that hold a token or key (see keychain_files in this script)." >&2; status=1
fi
# A key the person pasted in is never read by a screen or anything else: only the inFakt client (not built yet),
# which is the only place that may put it in a request. Its masked state is all a screen sees.
if grep -RInE --include='*.swift' 'AccountKeyStore\.read\(|KeychainAccountKey' "${dirs[@]}" | code_only | grep -v -e "^$infakt_client:" -e "^$account_key_store:"; then
  echo "FAIL: reading a pasted-in key outside $infakt_client; screens use AccountKeyStore.manager(for:), which has no key in it (ADR-640)." >&2; status=1
fi
# No key, however it is named, in a log line, a print or a string shown to the person.
if [ -f "$account_key_store" ] && grep -nE 'print\(|NSLog|os_log|Logger|debugPrint|dump\(' "$account_key_store" | code_only; then
  echo "FAIL: $account_key_store may not log or print anything (ADR-640)." >&2; status=1
fi
# Nothing in the app talks to inFakt until a client exists and its wire format is verified (ADR-640).
if [ ! -f "$infakt_client" ] && grep -RInE --include='*.swift' 'api\.infakt\.pl|sandbox-infakt\.pl|X-inFakt-ApiKey|InFaktAPI\.(productionBase|sandboxBase|apiKeyHeader)' DoddyApp DoddyWidgets DoddyShare DoddyWatch | code_only; then
  echo "FAIL: the app names inFakt's address or key header without a verified client at $infakt_client (ADR-640)." >&2; status=1
fi
# The voice account client may only post to VoiceConfig.authEndpoint, never an address it builds (ADR-484).
if [ -f "$voice_auth" ] && grep -nE 'URL\(string|URLComponents|appendingPathComponent|https?://' "$voice_auth" | code_only; then
  echo "FAIL: $voice_auth may only post to VoiceConfig.authEndpoint." >&2; status=1
fi
# Face ID (ADR-310): LocalAuthentication only in the app lock.
if grep -RInE --include='*.swift' 'import LocalAuthentication|LAContext' "${dirs[@]}" | code_only | grep -v "^DoddyApp/Features/Privacy/AppLock.swift:"; then
  echo "FAIL: LocalAuthentication outside DoddyApp/Features/Privacy/AppLock.swift." >&2; status=1
fi
# The rates client may only fetch the one fixed ECB file (ADR-300), never an address it is given.
if [ -f "$rates_client" ] && grep -nE 'URL\(string|URLComponents|appendingPathComponent|https?://' "$rates_client" | code_only; then
  echo "FAIL: $rates_client may only fetch ExchangeRateSource.url." >&2; status=1
fi
# The Open Food Facts client may only ask OpenFoodFacts.productURL(for:) (ADR-631), never an address it builds.
if [ -f "$off_client" ] && grep -nE 'URL\(string|URLComponents|appendingPathComponent|https?://|URLRequest\(url: *[^ O]' "$off_client" | code_only; then
  echo "FAIL: $off_client may only ask OpenFoodFacts.productURL(for:)." >&2; status=1
fi
# The InPost client may only ask InPostTracking.url(for:) (ADR-641), never an address it builds.
if [ -f "$inpost_client" ] && grep -nE 'URL\(string|URLComponents|appendingPathComponent|https?://|URLRequest\(url: *[^ I]' "$inpost_client" | code_only; then
  echo "FAIL: $inpost_client may only ask InPostTracking.url(for:)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$web_auth_only" "${dirs[@]}" | code_only | grep -v "^$web_auth_file:"; then
  echo "FAIL: web authentication / web views outside $web_auth_file." >&2; status=1
fi
if grep -RInE --include='*.swift' "$auth_services" "${dirs[@]}" | code_only | grep -vE "$apple_sign_in_files"; then
  echo "FAIL: AuthenticationServices outside Connected Apps and the voice account's Sign in with Apple (ADR-484)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$apple_sign_in_other" "${dirs[@]}" | code_only; then
  echo "FAIL: password, passkey or credential-provider APIs; only Sign in with Apple is allowed (ADR-494)." >&2; status=1
fi
# ASK-01 (ADR-483): a tool without a way to ask first fails here. Only the public lookups of
# ADR-575 (web, weather, Wikipedia, news, places, sums, conversions) may run at once.
if ! python3 -I - voice-agent/tools.json <<'PY'
import json, sys
PUBLIC = {"calculate", "convert_units", "convert_currency", "web_search", "news_search", "find_places",
          "geocode_place", "get_weather", "wikipedia_search", "wikipedia_summary"}
bad = []
for t in json.load(open(sys.argv[1], encoding="utf-8"))["tools"]:
    x = t.get("x_doddy", {})
    if x.get("ask") == "runs_now":
        # ADR-575: public lookups run at once; they may never be a change.
        if x.get("confirm_on_screen") or t.get("name") not in PUBLIC:
            bad.append(t.get("name"))
        continue
    if x.get("runs_on") != "phone" or x.get("ask") not in ("yes_or_tap", "tap") or (x.get("ask") == "tap") != bool(x.get("confirm_on_screen")):
        bad.append(t.get("name"))
if bad:
    print("tools without an ask:", ", ".join(map(str, bad)))
    sys.exit(1)
PY
then
  echo "FAIL: ASK-01: every voice tool must run on the phone and ask first (x_doddy.ask; 'tap' with confirm_on_screen), except ADR-575's public lookups." >&2; status=1
fi
voice_controller=DoddyApp/Features/Voice/VoiceSessionController.swift
if [ -f "$voice_controller" ] && ! { grep -q 'AskFirst.need(for: request)' "$voice_controller" && grep -q 'askLedger.mayRun(' "$voice_controller"; }; then
  echo "FAIL: ASK-01: $voice_controller must check AskFirst before a tool runs." >&2; status=1
fi
if grep -RInE --include='*.swift' "$wake_only" "${dirs[@]}" | code_only; then
  echo "FAIL: wake-word engine code is back (removed in ADR-549)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$voice_only" "${dirs[@]}" | grep -v "^$voice_dir/"; then
  echo "FAIL: ElevenLabs code outside $voice_dir." >&2; status=1
fi
if grep -RInE --include='*.swift' "$audio_only" "${dirs[@]}" | grep -v -e "^$voice_dir/" -e "^$memos_dir/" -e "^$recordings_dir/" -e "^$camera_access_file:[0-9]*:import AVFoundation$"; then
  echo "FAIL: audio code outside $voice_dir, $memos_dir and $recordings_dir (the camera permission file may only import AVFoundation)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$speech_only" "${dirs[@]}" | grep -v -e "^$memos_dir/" -e "^$recordings_dir/"; then
  echo "FAIL: speech recognition outside $memos_dir and $recordings_dir (ADR-230, ADR-588)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$watch_only" "${dirs[@]}" | grep -v -e "^$watch_link_dir/" -e "^$watch_app_dir/"; then
  echo "FAIL: WatchConnectivity outside $watch_link_dir and $watch_app_dir (ADR-232)." >&2; status=1
fi
# The watch app keeps no database and makes no network calls of its own.
if grep -RInE --include='*.swift' 'import GRDB|DoddyPersistence|URLSession|import Network' "$watch_app_dir"; then
  echo "FAIL: the watch app may only show the iPhone's snapshot and ask the iPhone (ADR-232)." >&2; status=1
fi
# The Mac menu bar prototype types notes into its own database on that Mac: no network, no
# microphone or speech, nothing sent to the iPhone (ADR-435).
if grep -RInE --include='*.swift' 'URLSession|import Network|import AVFoundation|import AVFAudio|AVAudio|import Speech|WCSession|import CloudKit' DoddyMac; then
  echo "FAIL: the Mac menu bar app may only save typed notes on that Mac (ADR-435)." >&2; status=1
fi
# Its desktop widget reads only the note count: no database, no network (ADR-439).
if grep -RInE --include='*.swift' 'import GRDB|DoddyPersistence|URLSession|import Network|AVAudio|import Speech' DoddyMacWidgets; then
  echo "FAIL: the Mac desktop widget may only read the note count (ADR-439)." >&2; status=1
fi
for speech_dir in "$memos_dir" "$recordings_dir"; do
  if [ -d "$speech_dir" ]; then
    for f in $(grep -RlE --include='*.swift' 'SFSpeech(URL|AudioBuffer)RecognitionRequest' "$speech_dir"); do
      if ! grep -qE 'requiresOnDeviceRecognition = true' "$f"; then
        echo "FAIL: $f makes a speech request without requiresOnDeviceRecognition = true." >&2; status=1
      fi
    done
    if grep -RInE --include='*.swift' 'requiresOnDeviceRecognition = false' "$speech_dir"; then
      echo "FAIL: speech recognition may not leave the iPhone (ADR-230, ADR-588)." >&2; status=1
    fi
  fi
done
# DODDY Capture's audio and words never leave the iPhone (ADR-588): no networking of any kind in its
# folder, and no upload API, whatever the general networking rule above allows elsewhere.
if [ -d "$recordings_dir" ] && grep -RInE --include='*.swift' 'URLSession|URLRequest|import Network|uploadTask|\.upload\(|WCSession|import CloudKit' "$recordings_dir" | code_only; then
  echo "FAIL: $recordings_dir may not send anything anywhere (ADR-588)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$connections_only" "${dirs[@]}" | grep -v "^$connections_dir/"; then
  echo "FAIL: calendar, contacts, location or Motion & Fitness code outside $connections_dir." >&2; status=1
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
if grep -RInE --include='*.swift' "$photo_library" "${dirs[@]}" | code_only | grep -v "^$photo_library_file:"; then
  echo "FAIL: photo library code outside $photo_library_file (ADR-569)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$camera_ui" "${dirs[@]}" | code_only | grep -v "^$camera_ui_file:"; then
  echo "FAIL: the camera screen outside $camera_ui_file (ADR-569)." >&2; status=1
fi
if grep -RInE --include='*.swift' 'AVCaptureDevice' "${dirs[@]}" | code_only | grep -v "^$camera_access_file:"; then
  echo "FAIL: camera permission code outside $camera_access_file (ADR-569)." >&2; status=1
fi
if grep -RInE "$camera_and_library_never" "${dirs[@]}" project.yml Config | code_only; then
  echo "FAIL: a capture session or a write to the photo library; Doddy only reads the library and uses iOS's camera screen (ADR-569)." >&2; status=1
fi
if grep -RInE "$location_tracking" "${dirs[@]}" project.yml | code_only; then
  echo "FAIL: \"Always\" or background location is not allowed; place reminders use \"While Using\" only." >&2; status=1
fi
if [ -d "$backend_src" ]; then
  if grep -RInE '(^|[^A-Z_])(GOOGLECALENDAR|GOOGLESUPER|GMAIL|GOOGLEDRIVE|NOTION|TODOIST|OUTLOOK)_[A-Z]' --include='*.ts' "$backend_src" | code_only | grep -v -e "^$composio_adapter:" -e "^$tools_catalog:" -e "^$tools_mock:"; then
    echo "FAIL: Composio tool slugs outside $composio_adapter, $tools_catalog and $tools_mock." >&2; status=1
  fi
  # Google Calendar writes (ADR-486): only create, patch (move, rename, answer an invitation) and
  # delete, in the catalog and its mock, each behind ASK-01's tap. No quick-add (free text), clear,
  # move between calendars, or calendar-level changes.
  if grep -RInE 'GOOGLECALENDAR_(CREATE|UPDATE|DELETE|PATCH|QUICK_ADD|MOVE|REMOVE|CLEAR|INSERT)' "$backend_src" \
    | grep -vE "^($tools_catalog|$tools_mock):[0-9]+:[^G]*GOOGLECALENDAR_(CREATE_EVENT|PATCH_EVENT|DELETE_EVENT)([^A-Z0-9_]|$)"; then
    echo "FAIL: a calendar write tool beyond the reviewed Google Calendar create, patch and delete is referenced in the backend." >&2; status=1
  fi
  # ADR-488: Notion create, append and move-to-trash, and a new private Google Doc (drive.file).
  # Since ADR-485 also the Gmail send, reply, forward, label and Trash tools (each behind ASK-01's
  # tap on the exact payload), in the catalog and its mock only. Never a permanent or bulk delete.
  # The only write tools allowed are GMAIL_CREATE_EMAIL_DRAFT, TODOIST_CREATE_TASK and, since ADR-303,
  # TODOIST_CLOSE_TASK_V1 and TODOIST_UPDATE_TASK (each needs a fresh on-screen approval bound to the
  # task Todoist returned). Anything that sends, deletes, shares, edits or labels is refused here, and
  # the two Todoist writes may appear only in the catalog and its mock.
  if grep -RInE 'GMAIL_(SEND|DELETE|TRASH|REPLY|FORWARD|MODIFY|BATCH|ADD|REMOVE|CREATE_LABEL|PATCH|UPDATE|MOVE|UNTRASH)|GOOGLEDRIVE_(CREATE|UPDATE|DELETE|ADD_FILE_SHARING|EDIT|COPY|MOVE|TRASH|UPLOAD|DOWNLOAD|EMPTY|REMOVE)|NOTION_(CREATE|UPDATE|DELETE|ADD|APPEND|ARCHIVE|INSERT|DUPLICATE|MOVE)|TODOIST_(UPDATE|DELETE|CLOSE|REOPEN|BULK|MOVE|QUICK_ADD|ARCHIVE|ADD)' "$backend_src" \
    | grep -vE "^($tools_catalog|$tools_mock):[0-9]+:.*TODOIST_(CLOSE_TASK_V1|UPDATE_TASK)([^A-Z0-9_]|$)" \
    | grep -vE "^($tools_catalog|$tools_mock):[0-9]+:[^G]*GMAIL_(SEND_EMAIL|REPLY_TO_THREAD|FORWARD_MESSAGE|ADD_LABEL_TO_EMAIL|MOVE_TO_TRASH)([^A-Z0-9_]|$)" \
    | grep -vE "^($tools_catalog|$tools_mock):[0-9]+:[^GN]*(NOTION_(CREATE_NOTION_PAGE|APPEND_TEXT_BLOCKS|ARCHIVE_NOTION_PAGE)|GOOGLEDRIVE_CREATE_FILE_FROM_TEXT)([^A-Z0-9_]|$)" \
    | grep -E 'GMAIL_|GOOGLEDRIVE_|NOTION_|TODOIST_(UPDATE|DELETE|CLOSE|REOPEN|BULK|MOVE|QUICK_ADD|ARCHIVE|ADD)'; then
    echo "FAIL: a write tool beyond the reviewed Gmail ones (draft, send, reply, forward, labels, Trash) and the Todoist add, complete and move is referenced in the backend." >&2; status=1
  fi
  # Outlook (ADR-340): the only write is OUTLOOK_CREATE_DRAFT, in the catalog and its mock. Nothing
  # that sends, deletes, moves, replies, flags or changes the calendar.
  # Since ADR-486/487 also the reviewed calendar and mail writes below, each behind ASK-01's tap.
  # Never a "permanently" delete, a batch, a cancel-for-everyone or anything on another user's mailbox.
  outlook_ok='OUTLOOK_(CREATE_DRAFT|CALENDAR_CREATE_EVENT|UPDATE_CALENDAR_EVENT|DELETE_CALENDAR_EVENT|ACCEPT_EVENT|DECLINE_EVENT|SEND_EMAIL|REPLY_EMAIL|FORWARD_MESSAGE|MOVE_MESSAGE|UPDATE_USER_MAIL_FOLDER_MESSAGE)'
  if grep -RInE 'OUTLOOK_(SEND|DELETE|MOVE|UPDATE|CREATE|REPLY|FORWARD|COPY|PATCH|FLAG|MARK|ADD|REMOVE|ACCEPT|DECLINE|CANCEL|TENTATIVE|SNOOZE|DISMISS|BATCH)' "$backend_src" \
    | grep -vE "^($tools_catalog|$tools_mock):[0-9]+:([^O]|O[^U])*${outlook_ok}([^A-Z0-9_]|$)([^O]|O[^U])*$"; then
    echo "FAIL: an Outlook write tool beyond the reviewed ones (ADR-340, ADR-486, ADR-487) is referenced in the backend." >&2; status=1
  fi
  if grep -RInE '(OUTLOOK|GOOGLECALENDAR|GMAIL|GOOGLEDRIVE|NOTION|TODOIST)_[A-Z_]*(PERMANENT|EMPTY_TRASH|PURGE)' "$backend_src"; then
    echo "FAIL: a permanent-delete tool is referenced in the backend; permanent deletion is out of scope (ASK-01 prompt)." >&2; status=1
  fi
  # ASK-01: every server tool has a card and runs only through the one gate.
  if grep -nE 'preview\?\(' "$tools_catalog"; then
    echo "FAIL: ASK-01: a tool's preview (its card) is required in $tools_catalog." >&2; status=1
  fi
  if ! python3 -I - "$tools_catalog" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
blocks = re.findall(r"export const (\w+): CloudToolDefinition = \{(.*?)\n\};", src, re.S)
missing = [name for name, body in blocks if "\n  preview:" not in body]
if not blocks or missing:
    print("tools without a card:", ", ".join(missing) or "(none found)")
    sys.exit(1)
PY
  then
    echo "FAIL: ASK-01: every tool in $tools_catalog needs a preview (its card)." >&2; status=1
  fi
  if grep -RInE 'consumeApproval\(' --include='*.ts' "$backend_src" | code_only | grep -vE "^$backend_src/(store|policy|tools/askFirst)\.ts:"; then
    echo "FAIL: ASK-01: approvals are checked only in backend/src/tools/askFirst.ts (and the older policy.ts)." >&2; status=1
  fi
  if ! grep -q 'this.ask.allows(binding, request.approvalId' "$backend_src/tools/service.ts" || ! grep -q 'this.ask.allows(binding(target)' "$backend_src/tools/service.ts"; then
    echo "FAIL: ASK-01: both run paths in backend/src/tools/service.ts must go through AskGate." >&2; status=1
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
if [ -d server/messaging ] && grep -RInE "$messaging_secrets" server/messaging render.yaml --exclude-dir=node_modules --exclude-dir=dist --exclude=.env.op; then
  echo "FAIL: possible secret found in server/messaging or render.yaml." >&2; status=1
fi
# The other deployed services (gateway, voice token server, site functions), the voice agent spec and
# tools: key values only, since their code legitimately names headers such as xi-api-key.
service_dirs=()
for extra in gateway server/voice-token site voice-agent tools; do [ -d "$extra" ] && service_dirs+=("$extra"); done
if [ "${#service_dirs[@]}" -gt 0 ] && grep -RInE "${messaging_secrets%)}|ak_[A-Za-z0-9_-]{20,}|monid_(live|test)_[A-Za-z0-9_-]{16,}|PASSWORD=[^[:space:]]{8,})" \
    "${service_dirs[@]}" --exclude-dir=node_modules --exclude-dir=dist --exclude=package-lock.json --exclude=.env.op; then
  echo "FAIL: possible secret found in gateway, server/voice-token, site, voice-agent or tools." >&2; status=1
fi
# 1Password (ADR-493): the app ships no secrets and no 1Password code, and the servers read plain
# environment variables (no 1Password SDK at boot). op:// references live only in the .env.op
# templates and secrets/, which `node tools/secrets/sync.mjs check` keeps to references only.
onepassword='op://|@1password/|onepassword-sdk|OnePasswordSDK|OP_SERVICE_ACCOUNT_TOKEN|OP_CONNECT_(HOST|TOKEN)'
if grep -RInE "$onepassword" "${dirs[@]}" Config project.yml project-iphone.yml project-watch.yml project-mac.yml; then
  echo "FAIL: 1Password references or code in an app target (ADR-493)." >&2; status=1
fi
if grep -nE '"@1password/' backend/package.json server/*/package.json gateway/package.json site/package.json 2>/dev/null; then
  echo "FAIL: a server depends on the 1Password SDK; hosts keep plain environment variables (ADR-493)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$sharing_only" "${dirs[@]}" | code_only | grep -v "^$sharing_dir/"; then
  echo "FAIL: CloudKit outside $sharing_dir." >&2; status=1
fi
if grep -RInE --include='*.swift' "$alarms_only" "${dirs[@]}" | code_only | grep -v -e "^$alarms_dir/" -e "^Shared/Alarms/DoddyAlarmMetadata.swift:" -e "^DoddyWidgets/AlarmLiveActivity.swift:"; then
  echo "FAIL: AlarmKit outside $alarms_dir." >&2; status=1
fi
if grep -RnoE 'NS[A-Za-z]+UsageDescription' project.yml DoddyApp DoddyWidgets DoddyShare Config | grep -vE "$allowed_permissions"; then
  echo "FAIL: only the alarms, microphone, speech recognition, calendar, reminders, contacts, Motion & Fitness, camera, photo library (read), While Using location and Face ID permissions are allowed." >&2; status=1
fi
[ "$status" -eq 0 ] && echo "PASS: ASK-01: every voice tool and every server tool asks first through one gate; networking only in the token client, the voice account sign-in, URLSessionTransport, the assistant transport, the messaging transport, the OpenAI test voice, the ECB rates client, the Open Food Facts client and the InPost client (one address each) and nothing that talks to inFakt, the Keychain only in the files that hold a token or key (a key the person pasted in is read only by the inFakt client, which isn't built), web auth only in Connected Apps, Sign in with Apple only in the voice account sign-in and no password or passkey APIs, ElevenLabs only in Voice, audio only in Voice, Voice memos and Recordings, on-device speech recognition only in Voice memos and Recordings (nothing in Recordings sends anything), calendar, contacts, location and Motion & Fitness only in Connections, photo reading and the photo picker only in Photos, the photo library read only in PhotoLibrarySearch and the camera only through iOS's camera screen (no capture session, no library writes), no Always/background location, no analytics, no secrets, no 1Password code in the app or SDK in the servers, AlarmKit only in Alarms, CloudKit only in Sharing, permissions limited to alarms, microphone, speech recognition, calendar, reminders, contacts, Motion & Fitness, camera, photo library (read), While Using location and Face ID (LocalAuthentication only in the app lock); backend has no write tools beyond the reviewed Gmail draft and reply draft, the Outlook draft and Todoist add, complete and move, and no proxy execution."
exit "$status"

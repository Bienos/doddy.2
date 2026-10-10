#!/usr/bin/env bash
# Capability guard. Settings/Home copy makes specific privacy claims; this check keeps them true:
#  - the app's own networking lives in three files: the voice token client (one POST of the access
#    code to the token server), Connected Apps' transport (to the Doddy server) and the typed-assistant
#    transport (to the M2 gateway, ADR-110); the ElevenLabs SDK does the voice connection,
#  - the system authentication browser is used only by Connected Apps,
#  - audio/ElevenLabs code only inside DoddyApp/Features/Voice,
#  - calendar (EventKit) and contacts code only inside DoddyApp/Infrastructure/Connections,
#  - no speech framework, accounts, analytics or crash SDKs, no secrets,
#  - permission keys only for the microphone, calendar, reminders and contacts,
#  - backend: Composio tool slugs only in the adapters and the tool catalog (and the mock that mimics
#    their answers), no write tools beyond the two reviewed ones (Gmail draft, Todoist task), no proxy execution.
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
network_only='URLSession([^A-Za-z]|$)|URLRequest([^A-Za-z]|$)'
web_auth_file=DoddyApp/Features/ConnectedApps/SystemWebAuthenticator.swift
web_auth_only='import AuthenticationServices|ASWebAuthenticationSession|WKWebView|import WebKit|SFSafariViewController'
voice_only='import AVFoundation|import AVFAudio|AVAudio|import ElevenLabs'
connections_only='import EventKit|EKEventStore|EKEvent|EKReminder|import Contacts|CNContact'
secrets='(sk-[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}|ak_[A-Za-z0-9_-]{20,}|xi-api-key|api[_-]?key[[:space:]]*[:=][[:space:]]*"[^"]+"|BEGIN (RSA |EC )?PRIVATE KEY)'
allowed_permissions='NSMicrophoneUsageDescription|NSCalendarsFullAccessUsageDescription|NSRemindersFullAccessUsageDescription|NSContactsUsageDescription'
backend_src=backend/src
# Drops comment-only lines from `grep -n` output (file:line:   // …, /// …, * …).
code_only() { grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)'; }
composio_adapter=backend/src/providers/composio.ts
# Online accounts (Gmail, Drive, Notion, Todoist): the catalog names each slug once; the mock returns
# the same answer shapes. Nothing else may name a slug.
tools_catalog=backend/src/tools/catalog.ts
tools_mock=backend/src/tools/mock.ts

status=0
if grep -RInE --include='*.swift' --include='*.plist' "$anywhere" "${dirs[@]}" Config; then
  echo "FAIL: forbidden capability code found (see matches above)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$network_only" "${dirs[@]}" | code_only | grep -v -e "^$network_file:" -e "^$token_client:" -e "^$assistant_transport:"; then
  echo "FAIL: networking code outside $network_file, $assistant_transport and $token_client." >&2; status=1
fi
if grep -RInE --include='*.swift' "$web_auth_only" "${dirs[@]}" | code_only | grep -v "^$web_auth_file:"; then
  echo "FAIL: web authentication / web views outside $web_auth_file." >&2; status=1
fi
if grep -RInE --include='*.swift' "$voice_only" "${dirs[@]}" | grep -v "^$voice_dir/"; then
  echo "FAIL: audio/ElevenLabs code outside $voice_dir." >&2; status=1
fi
if grep -RInE --include='*.swift' "$connections_only" "${dirs[@]}" | grep -v "^$connections_dir/"; then
  echo "FAIL: calendar or contacts code outside $connections_dir." >&2; status=1
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
fi
secret_paths=("${dirs[@]}" project.yml scripts)
for extra in backend/src backend/test contracts .env.example backend/.env.example; do [ -e "$extra" ] && secret_paths+=("$extra"); done
if grep -RInE "$secrets" "${secret_paths[@]}" --exclude=check_forbidden_capabilities.sh; then
  echo "FAIL: possible secret found." >&2; status=1
fi
if grep -RnoE 'NS[A-Za-z]+UsageDescription' project.yml DoddyApp DoddyWidgets Config | grep -vE "$allowed_permissions"; then
  echo "FAIL: only the microphone, calendar, reminders and contacts permissions are allowed." >&2; status=1
fi
[ "$status" -eq 0 ] && echo "PASS: networking only in the token client, URLSessionTransport and the assistant transport, web auth only in Connected Apps, audio only in Voice, calendar and contacts only in Connections, no speech/analytics, no secrets, permissions limited to microphone, calendar, reminders and contacts; backend has no write tools beyond the reviewed Gmail draft and Todoist task, and no proxy execution."
exit "$status"

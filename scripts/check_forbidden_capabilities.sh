#!/usr/bin/env bash
# Capability guard. Settings/Home copy makes specific privacy claims; this check keeps them true:
#  - networking code of our own only in DoddyApp/Infrastructure/Server (Doddy server client);
#    the ElevenLabs SDK does the voice connection,
#  - audio/ElevenLabs code only inside DoddyApp/Features/Voice,
#  - EventKit only in the Reminders gateway (M4); no speech framework, accounts, analytics or crash SDKs,
#  - no secrets (app, scripts and server/), and no permission keys except the microphone.
# The server (server/) is a separate program and may use the network; the app may not.
# Exit 0 = clean, 1 = violation.
set -euo pipefail
cd "$(dirname "$0")/.."

dirs=(DoddyApp Packages/DoddyCore/Sources)
voice_dir=DoddyApp/Features/Voice
server_dir=DoddyApp/Infrastructure/Server
server_only='URLSession|URLRequest'
anywhere='NWConnection|import Network|import Speech|SFSpeech|import AuthenticationServices|import CloudKit|import FirebaseCore|import Sentry|import Analytics'
voice_only='import AVFoundation|import AVFAudio|AVAudio|import ElevenLabs'
server_secrets='(sk-[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}|AC[0-9a-f]{32}|SK[0-9a-f]{32}|BEGIN (RSA |EC )?PRIVATE KEY|(KEY|TOKEN|SECRET)=[^[:space:]]{8,})'
secrets='(sk-[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}|xi-api-key|api[_-]?key[[:space:]]*[:=][[:space:]]*"[^"]+"|BEGIN (RSA |EC )?PRIVATE KEY)'

status=0
if grep -RInE --include='*.swift' --include='*.plist' "$anywhere" "${dirs[@]}"; then
  echo "FAIL: forbidden capability code found (see matches above)." >&2; status=1
fi
reminders_dir=DoddyApp/Features/Reminders
if grep -RInE --include='*.swift' 'import EventKit|EKEventStore|EKReminder' "${dirs[@]}" | grep -v "^$reminders_dir/EventKitReminderGateway.swift:"; then
  echo "FAIL: EventKit code outside $reminders_dir/EventKitReminderGateway.swift." >&2; status=1
fi
if grep -RInE --include='*.swift' "$server_only" "${dirs[@]}" | grep -v "^$server_dir/"; then
  echo "FAIL: networking code outside $server_dir." >&2; status=1
fi
if grep -RInE --include='*.swift' "$voice_only" "${dirs[@]}" | grep -v "^$voice_dir/"; then
  echo "FAIL: audio/ElevenLabs code outside $voice_dir." >&2; status=1
fi
if grep -RInE "$secrets" "${dirs[@]}" project.yml scripts --exclude=check_forbidden_capabilities.sh; then
  echo "FAIL: possible secret found." >&2; status=1
fi
# The server legitimately sends provider key *headers*; there we look for key *values* only.
if grep -RInE "$server_secrets" server render.yaml --exclude-dir=node_modules --exclude-dir=dist; then
  echo "FAIL: possible secret found in server/." >&2; status=1
fi
if grep -RnoE 'NS[A-Za-z]+UsageDescription' project.yml DoddyApp | grep -vE 'NS(Microphone|RemindersFullAccess)UsageDescription'; then
  echo "FAIL: only the microphone and Reminders permissions are allowed." >&2; status=1
fi
[ "$status" -eq 0 ] && echo "PASS: own networking only in Infrastructure/Server, audio only in Voice, EventKit only in the Reminders gateway, no speech/accounts/analytics, no secrets, only microphone + Reminders permissions."
exit "$status"

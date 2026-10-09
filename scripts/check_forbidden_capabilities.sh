#!/usr/bin/env bash
# Capability guard. Settings/Home copy makes specific privacy claims; this check keeps them true:
#  - no networking code of our own (the ElevenLabs SDK does the voice connection),
#  - audio/ElevenLabs code only inside DoddyApp/Features/Voice,
#  - calendar (EventKit) and contacts code only inside DoddyApp/Infrastructure/Connections,
#  - no speech framework, accounts, analytics or crash SDKs, no secrets,
#  - permission keys only for the microphone, calendar, reminders and contacts.
# Exit 0 = clean, 1 = violation.
set -euo pipefail
cd "$(dirname "$0")/.."

dirs=(DoddyApp Packages/DoddyCore/Sources)
voice_dir=DoddyApp/Features/Voice
connections_dir=DoddyApp/Infrastructure/Connections
anywhere='URLSession|URLRequest|NWConnection|import Network|import Speech|SFSpeech|import AuthenticationServices|import CloudKit|import FirebaseCore|import Sentry|import Analytics'
voice_only='import AVFoundation|import AVFAudio|AVAudio|import ElevenLabs'
connections_only='import EventKit|EKEventStore|EKEvent|EKReminder|import Contacts|CNContact'
secrets='(sk-[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}|xi-api-key|api[_-]?key[[:space:]]*[:=][[:space:]]*"[^"]+"|BEGIN (RSA |EC )?PRIVATE KEY)'
allowed_permissions='NSMicrophoneUsageDescription|NSCalendarsFullAccessUsageDescription|NSRemindersFullAccessUsageDescription|NSContactsUsageDescription'

status=0
if grep -RInE --include='*.swift' --include='*.plist' "$anywhere" "${dirs[@]}"; then
  echo "FAIL: forbidden capability code found (see matches above)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$voice_only" "${dirs[@]}" | grep -v "^$voice_dir/"; then
  echo "FAIL: audio/ElevenLabs code outside $voice_dir." >&2; status=1
fi
if grep -RInE --include='*.swift' "$connections_only" "${dirs[@]}" | grep -v "^$connections_dir/"; then
  echo "FAIL: calendar or contacts code outside $connections_dir." >&2; status=1
fi
if grep -RInE "$secrets" "${dirs[@]}" project.yml scripts --exclude=check_forbidden_capabilities.sh; then
  echo "FAIL: possible secret found." >&2; status=1
fi
if grep -RnoE 'NS[A-Za-z]+UsageDescription' project.yml DoddyApp | grep -vE "$allowed_permissions"; then
  echo "FAIL: only the microphone, calendar, reminders and contacts permissions are allowed." >&2; status=1
fi
[ "$status" -eq 0 ] && echo "PASS: no own networking, audio only in Voice, calendar and contacts only in Connections, no speech/accounts/analytics, no secrets, permissions limited to microphone, calendar, reminders and contacts."
exit "$status"

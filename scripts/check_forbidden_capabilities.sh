#!/usr/bin/env bash
# M0 guard: the app and core sources must not contain networking, audio, speech, reminders,
# account or secret code. Settings/Home copy claims exactly this ("no networking, microphone
# or reminders code"), so this check is what makes that claim testable.
# Exit 0 = clean, 1 = violation.
set -euo pipefail
cd "$(dirname "$0")/.."

dirs=(DoddyApp Packages/DoddyCore/Sources)
pattern='URLSession|URLRequest|NWConnection|import Network|import AVFoundation|import AVFAudio|AVAudio|import Speech|SFSpeech|import EventKit|EKEventStore|import AuthenticationServices|import CloudKit|import FirebaseCore|import Sentry|import Analytics'
secrets='(sk-[A-Za-z0-9]{20,}|api[_-]?key[[:space:]]*[:=][[:space:]]*"[^"]+"|BEGIN (RSA |EC )?PRIVATE KEY)'

status=0
if grep -RInE --include='*.swift' --include='*.plist' --include='*.yml' "$pattern" "${dirs[@]}" project.yml; then
  echo "FAIL: forbidden capability code found (see matches above)." >&2; status=1
fi
if grep -RInE "$secrets" "${dirs[@]}" project.yml scripts; then
  echo "FAIL: possible secret found." >&2; status=1
fi
if grep -nE 'NS(Microphone|SpeechRecognition|RemindersFullAccess|Reminders)[A-Za-z]*UsageDescription' project.yml DoddyApp -r; then
  echo "FAIL: M0 must not request OS permissions." >&2; status=1
fi
[ "$status" -eq 0 ] && echo "PASS: no networking/audio/speech/EventKit/account code, no secrets, no permission keys (M0)."
exit "$status"

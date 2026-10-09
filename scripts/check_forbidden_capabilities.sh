#!/usr/bin/env bash
# Capability guard. Settings/Home copy makes specific privacy claims; this check keeps them true:
#  - networking of our own only in the voice token client (one POST of the access code to the
#    token server); the ElevenLabs SDK does the voice connection,
#  - audio/ElevenLabs code only inside DoddyApp/Features/Voice,
#  - no speech framework, EventKit, accounts, analytics or crash SDKs,
#  - no secrets, and no permission keys except the microphone.
# Exit 0 = clean, 1 = violation.
set -euo pipefail
cd "$(dirname "$0")/.."

dirs=(DoddyApp DoddyControls Shared Packages/DoddyCore/Sources)
voice_dir=DoddyApp/Features/Voice
token_client=DoddyApp/Features/Voice/VoiceTokenClient.swift
token_only='URLSession|URLRequest'
anywhere='NWConnection|import Network|import Speech|SFSpeech|import EventKit|EKEventStore|import AuthenticationServices|import CloudKit|import FirebaseCore|import Sentry|import Analytics'
voice_only='import AVFoundation|import AVFAudio|AVAudio|import ElevenLabs'
secrets='(sk-[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}|xi-api-key|api[_-]?key[[:space:]]*[:=][[:space:]]*"[^"]+"|BEGIN (RSA |EC )?PRIVATE KEY)'

status=0
if grep -RInE --include='*.swift' --include='*.plist' "$anywhere" "${dirs[@]}"; then
  echo "FAIL: forbidden capability code found (see matches above)." >&2; status=1
fi
if grep -RInE --include='*.swift' "$token_only" "${dirs[@]}" | grep -v "^$token_client:"; then
  echo "FAIL: networking code outside $token_client." >&2; status=1
fi
if grep -RInE --include='*.swift' "$voice_only" "${dirs[@]}" | grep -v "^$voice_dir/"; then
  echo "FAIL: audio/ElevenLabs code outside $voice_dir." >&2; status=1
fi
if grep -RInE "$secrets" "${dirs[@]}" project.yml scripts --exclude=check_forbidden_capabilities.sh; then
  echo "FAIL: possible secret found." >&2; status=1
fi
if grep -RnoE 'NS[A-Za-z]+UsageDescription' project.yml DoddyApp DoddyControls | grep -v 'NSMicrophoneUsageDescription'; then
  echo "FAIL: only the microphone permission is allowed." >&2; status=1
fi
[ "$status" -eq 0 ] && echo "PASS: own networking only in the token client, audio only in Voice, no EventKit/speech/accounts/analytics, no secrets, microphone is the only permission."
exit "$status"

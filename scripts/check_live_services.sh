#!/usr/bin/env bash
# Read-only check of Doddy's four live services (docs/implementation/GO_LIVE_RUNBOOK_2026-10-13.md).
# Sends no secrets: the voice token and gateway checks use a made-up code and an empty body, so a
# working server refuses them. Override the addresses with the environment variables below.
#   scripts/check_live_services.sh
#   DODDY_GATEWAY_URL=https://my-gateway.vercel.app scripts/check_live_services.sh
set -u

BACKEND_URL="${DODDY_BACKEND_URL:-https://doddy-yaci.onrender.com}"
MESSAGING_URL="${DODDY_MESSAGING_URL:-https://doddy-messaging-zw1n.onrender.com}"
VOICE_TOKEN_URL="${DODDY_VOICE_TOKEN_URL:-https://doddy-voice-token.onrender.com}"
GATEWAY_URL="${DODDY_GATEWAY_URL:-https://doddy-gateway.vercel.app}"

failures=0

# probe NAME METHOD URL EXPECTED_STATUS HINT [curl args...]
probe() {
  local name="$1" method="$2" url="$3" expected="$4" hint="$5"
  shift 5
  local body status
  # Render's free plan sleeps; the first request can take close to a minute.
  body="$(curl -sS -m 90 -X "$method" -w $'\n%{http_code}' "$@" "$url" 2>&1)"
  status="${body##*$'\n'}"
  body="${body%$'\n'*}"
  body="$(printf '%s' "$body" | tr '\n' ' ' | cut -c1-160)"
  if [ "$status" = "$expected" ]; then
    printf 'OK    %-12s %s %s\n' "$name" "$status" "$body"
  else
    printf 'FAIL  %-12s %s %s\n      -> %s\n' "$name" "$status" "$body" "$hint"
    failures=$((failures + 1))
  fi
}

probe backend GET "$BACKEND_URL/v1/health" 200 \
  "Render service 'doddy' is down or asleep too long: Render dashboard -> doddy -> Logs."
probe messaging GET "$MESSAGING_URL/healthz" 200 \
  "Render service 'doddy-messaging' is down: check its Logs and DATABASE_URL."
# A wrong code must get 401. 402 = Vercel disabled the deployment (billing); 500 = env vars missing.
probe voice-token POST "$VOICE_TOKEN_URL/api/voice-token" 401 \
  "500 server_not_configured: add ELEVENLABS_API_KEY and DODDY_ACCESS_CODES in Render (doddy-voice-token -> Environment); Render redeploys on save." \
  -H 'authorization: Bearer not-a-real-code-000000'
# An empty body must get 400 (invalidRequest). 503 = env vars missing; 402 = Vercel billing.
probe gateway POST "$GATEWAY_URL/api/register" 400 \
  "402: fix Vercel billing. 503 notConfigured: set the OPENAI_*, GATEWAY_* and Redis variables (gateway/README.md) and redeploy." \
  -H 'content-type: application/json' --data '{}'

if [ "$failures" -eq 0 ]; then
  echo "RESULT: all four services answer as expected (this does not prove a real conversation works)."
else
  echo "RESULT: $failures service(s) need attention."
  exit 1
fi

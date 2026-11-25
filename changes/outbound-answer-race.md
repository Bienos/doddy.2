# Call me now: the answer no longer fails when Twilio's "in-progress" callback arrives first

`/webhooks/twilio/voice/outbound/:callId` accepted only calls still `requested` or `ringing`. When Twilio's
`in-progress` status callback landed first (seen 80 ms ahead on 19 Nov), the call was `answered` already and the
caller heard the fallback "can't talk" in a Polly voice. The same call (same `CallSid`) may now connect if no session
is open yet, still only once. Test: `scheduledCalls.test.ts` (real Postgres, ran locally). Needs a `doddy-messaging` deploy.

# Tool/action contract — deterministic user control
**M4 only.** A model proposes what to do; it never authorizes side effects.

## Tool registry record
`id, version, capability, schema, permissionScope, sideEffectRisk, requiresConfirmation, availability, cooldown, timeout, executor, receiptVerifier, retentionPolicy`. M4 implements `create_apple_reminder` first. Search/weather/calendar are exploratory future registrations, not hidden APIs.

## Reminder state machine
```
drafted → needsClarification → readyForConfirmation → userConfirmed
→ pendingExternalWrite → verifiedSucceeded | verifiedFailed | unknownOutcome
```
Every external write has deterministic `operationId` and canonical payload digest. In `unknownOutcome`, reconcile against local receipt / external identifier before proposing retry to avoid duplicates. User must see resolved date/timezone and list before confirming. Permission denied → local draft retained (not incorrectly claimed as saved to Apple Reminders). Deleting the local note does not silently delete external EventKit reminder.

## Security and truth rules
- Typed input validation, allowed calendars/lists, resolved timestamp, explicit user confirmation, permission check at execution time.
- Tool receipts `{operationId, toolName, status, verifiedAt, externalId?, errorCode?}`. Mark `succeeded` only when adapter verified result; if not, surface `unknown`.
- A web page, model prompt, memory or other external data cannot approve actions or escalate scopes.
- Atomic storage of pending state before external call; log only the event result with no user content unless explicit debug opt-in and documented retention.
- Actions are single-step, inspectable and user-cancellable where safe. No background autonomous multi-tool plan in MVP.

## Follow-through experiment
Compare observed task completion and natural repeated use with Apple's Reminders, Notes and Siri, including permission/setup friction. Show users unambiguous real reminders rather than mock demos.

# Native memory / Island baseline

Owner approved this focused native baseline on 10 October 2026. Local branch
`codex/doddy2-native-baseline`, from Island revision
`1d9b6437b6be288aac293a5fc80da1591fd36948` of `Bienos/doddy.2`.

## Scope and order

1. Build the existing app and widget extension with the installed Apple toolchain; fix blockers.
2. Preserve the SQLite foundation and fix voice capture source metadata.
3. Verify the core package, native launch, save/search/restart and Island lifecycle using synthetic data.
4. Record exact results, screenshots and a physical-iPhone checklist. Stop for owner review.

No automatic merge of the diverged Connections branch, new services, paid voice calls,
credentials, production signing, publishing, or artwork changes. Thought Pocket remains
a separate design reference pending visual selection. Imported research/design documents
and the older `AI-AGENT-DODDY` repository remain read-only.

## Safety and tests

The default development identifier stays unchanged. Simulator build overrides
`DODDY_APP_BUNDLE_IDENTIFIER=com.bienos.doddy2.baseline` to avoid replacing an existing
Doddy install or its data. Test data must be synthetic; in-memory or dedicated test storage
must not touch personal records. No voice provider session is opened by automated tests.

Run package validation/persistence tests, pack-integrity and capability guards, native
app/widget compilation and focused app/UI tests. Clearly distinguish Apple build proof,
offline lifecycle fixtures and actual microphone/provider/physical-device behavior.

Open risks: SDK API compatibility, cancellation while connecting, overlapping proposals,
system-driven Activity lifetime, completeUntilFirstUserAuthentication protection and backup
behavior, and the existing all-notes/recent-conversation context sent when a user starts voice.
Provider privacy/authentication and real device behavior remain release gates, not outcomes
of a no-paid-call simulator baseline.

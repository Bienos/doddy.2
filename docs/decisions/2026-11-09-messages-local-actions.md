# Messages offers the same local note, list and reminder actions as voice

- Date: 2026-11-09
- Decided by: owner, “zrob 2 i 4”, implementing the selected text/voice parity item.
- Status: implemented on a feature branch; rollout requires the messaging server update and app build.

Messages clients opt into a versioned localActions extension with their local clock/time zone. The server asks the existing model for one typed proposal from an eight-action allowlist; it executes no phone tools. Legacy clients keep the original schema/prompt. An updated phone retries an explicit old-server invalidRequest once without the extension; no retry follows a timeout/unknown response.

The phone parses arguments again through VoiceToolRequest, displays the exact immutable payload and consumes the offer on the user's tap. Reads also require that tap. Offers expire after five minutes and are never restored from storage. Closing, locking, revoking consent or switching account invalidates them. One execution at a time prevents duplicate taps; unknown outcomes are terminal, with instructions to check the actual store before asking again.

The native executor uses MemoryStore's verified SQLite writes and the same ReminderAction read-before/write/read-back flow as voice. ToolGate checks release scope, Pause all and connection switches. Permission is checked at execution; a reminders permission prompt occurs only after a tap and only for an enabled connection. The EventKit write adapter checks the account/screen/consent/switch scope again after asynchronous lookup. Exact list and item matches are required; no fuzzy destructive target. Private/sample records are excluded. The trusted native receipt is stored in the conversation, whose existing Doddy Web copy is disclosed on the card. Model prose accompanying a proposal is replaced with a neutral offer, never treated as completion evidence.

DOD-06/07/08/09/11, ASK-01, UX-01/02/03. No voice SDK is started, no migration or live agent changes. Real phone permission/notifications, language accuracy and live-model intent selection remain device/staging checks; automated tests use synthetic data and local provider stand-ins.

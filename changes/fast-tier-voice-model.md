# Live on 15 Nov 2026: the voice model runs on the fast tier

The live main agent's `service_tier` is `fast` (version `agtvrsn_4401m7ez5dncese85wmb5gb0qw85`), on the owner's word. Same model (`gpt-6-luna`), prompt and tools. Measured before: 42/42 tests, the model's first token 1.47 s → 1.00 s median, about +$0.005 a minute. After the switch: the seven agent tests × 2 passed 14/14. Log and rollback in `voice-agent/README.md`; `voice-agent/session.json` records the tier. For STATUS.md: the voice agent's model is `gpt-6-luna` on the fast tier.

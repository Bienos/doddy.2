# Bounded context before connecting voice

Voice startup reads a small SQLite snapshot instead of the screens' full MemoryStore. Notes are filtered by privacy, source and category before a fixed row limit. Lists are names/counts only. Current privacy is checked again after awaiting the read. Failed reads are unavailable, never empty. Translator startup does not read this personal context.

The existing 6000-character notes and 4000-character recent-conversation budgets remain. Overflow is explicit and search_memories/read_list provide on-demand access. Learned facts and errands may use only already-loaded, policy-filtered context; their maintenance/export/all-history reads do not delay connection. No extra cloud state or cross-account cache is introduced.

Measure the `Voice startup context` signpost separately from token, room, microphone and first successful interaction on an iPhone. This decision claims less prerequisite work, not a measured device latency improvement.

# Poland Pack v2 — Voice + Polish context (11 November 2026)

**Status: code staged on a dependent draft PR. Not merged, released, or synced to the live ElevenLabs agent.**
Depends on the v1 Poland Pack (#333), whose code is the base branch. Merge/rebase v1 first, then review v2.

## Implementation

- `get_poland_info` is a **new phone tool** in the version-controlled `voice-agent/tools.json`, with 4 limited topics:
  - `weather`: IMGW station observation (not a forecast).
  - `warnings`: IMGW warnings filtered by the selected county's TERYT.
  - `air`: GIOŚ v1 air-quality index of a named measuring station (not a citywide average).
  - `rates`: NBP EUR/USD/GBP reference exchange rates with effective dates.
- `PolandVoiceRequest` validates `topic` and selected city. No precise GPS access, no default city, no unsupported destinations. The offline `PolishContext` maps common aliases such as Wawa, Kraków, Gdańsk, smog, ostrzeżenia and kursy, rather than loading a large prompt on every session.
- Voice parser → ToolCatalog → AskFirst → ConnectionPause → CarProfile → ActivityLog → VoiceSessionController. The app only contacts official sources **after a spoken yes or screen tap**, through the existing network transport, and replies with source-supported data or an explicit unavailable response.
- The iPhone's Poland Pack screen uses the same `PolandPackFetcher` under `DoddyApp/Infrastructure/Network/PolandOpenDataClient.swift`, not a separate implementation.
- A bounded GIOŚ station lookup and 15-minute in-memory station-metadata cache are shared between screen and voice.
- `PolandVoiceTests` covers city/topic aliasing, missing-city handling, invalid inputs, approval, paused connections, tool classifications and activity logging.

## Product and safety contracts

- The developer tool remains `elevenlabs_tool_id: "not_synced"`. Editing `voice-agent/tools.json` and `voice-agent/instructions.md` **does not modify the live ElevenLabs agent**. An owner review, explicit synchronization and post-sync read-back are required before describing the tool as live.
- Voice prompt routes official Polish **measurements** to `get_poland_info`, not the generic forecast tool; future weather still uses `geocode_place` + `get_weather`. The normal `convert_currency` tool continues to use ECB rates. Only requests for **NBP reference rates** route to the new tool.
- The new lookup is `AskFirst.yesFirst`, not an unapproved public web call. `connections.pauseAll` blocks it. It cannot post, follow, buy, book, access private accounts or issue payments.
- Freshness: a weather measurement includes its measurement date/time; a rate includes the NBP effective date. Do not describe a station observation as a forecast or a missing index as good air.
- Public sources: https://dane.imgw.pl/apiinfo ; https://powietrze.gios.gov.pl/pjp/content/api ; https://api.nbp.pl/ . Commercial reuse requirements and API limits require owner/legal review before public launch.

## Wykop as the next separate integration

Wykop has an official **v3 REST/JSON developer API** at https://dev.wykop.pl/ (docs: https://doc.wykop.pl/).
Do not scrape, post on behalf of a user, or commit API credentials. Proposed next PR: a server-side **read-only** trending/search adapter after developer registration and verification of available scopes, rate limits and terms. Separate a fact from an opinion; provide links and dates; no automated replies or votes. No Wykop integration is implemented in this PR.

## Validation and release gates

1. v1 #333 Swift and iOS CI green, then merge v1.
2. v2 `swift test --package-path Packages/DoddyCore --filter PolandVoiceTests`, full core suite and Xcode build.
3. PR guard will request the repository owner's `owner-approved` label for the **protected voice-agent configuration**. Do not bypass the label.
4. Review tool spec against the actual ElevenLabs agent (still `not_synced`) and intentionally sync after owner approval. Do not remove an existing tool, change model/voice or publish a prompt change without separate review.
5. On-device spoken Polish/English smoke tests; ask card, Pause all, device offline, unsupported city, stale server data, city-specific warning/air index, End during fetch, and tool response after interruption.
6. Verify commercial data-reuse terms before broad consumer distribution.

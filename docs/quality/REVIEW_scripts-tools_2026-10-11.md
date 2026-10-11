# Review — `scripts/` and `tools/` (2026-10-11)

Read-only review. No code changed.

**Read in full:**
- `scripts/ci.sh`, `check_forbidden_capabilities.sh`, `typecheck_app_logic.sh`, `check_island_art.sh`, `recall_benchmark.sh`, `verify_imported_pack.py`.
- `tools/verify_pack.py`, `gen_site_tokens.py`, `build_strings_catalog.py`.

**Read in part:**
- `tools/build_blog.py`: escaping, front matter, file writes.
- `tools/whole_doddy/cut_wave.py`.
- `tools/island_boards/generate_island_art.py`: its outline and file writes.

**Not re-read:** `scripts/voice_agent_spec.py`, which was covered by the voice-agent review earlier today, and `tools/island_boards/*.swift`, which are checks run by `check_island_art.sh`.

## Tests run

| Command | Result |
|---|---|
| The guard's secret pattern, run over the folders it doesn't scan (`gateway/`, `server/voice-token/`, `site/`, `voice-agent/`, `tools/`) | no key values; one header name (`xi-api-key` in `server/voice-token/src/handler.js:127`), which is why the value-only pattern is needed there |
| Search of the app for networking calls the guard's pattern misses | today they appear only in the allowed transport files (`URLSessionConfiguration`, `URLSessionWebSocketTask` in the OpenAI voice file), plus `URLSessionTransport.shared` used as a type elsewhere |
| Search for localization call forms `build_strings_catalog.py` doesn't match | `Text(LocalizedStringKey(variable))` only, and those variables are covered by its `title:`/`subtitle:` pattern |

Every check script also ran earlier today as part of the other fixes: `ci.sh` steps, the guard, the strings catalog, the blog check, the island art check and the type-check. All passed.

## What is solid

- **`ci.sh` fails honestly:** a step that can't run is `NOT RUN` and the script exits 2, never green. The messaging DB tests are listed as `SKIPPED` without a database.
- **The guard keeps each sensitive framework in one place,** so the privacy copy stays checkable. It covers networking, ElevenLabs, audio, on-device-only speech, EventKit/Contacts/location, CloudKit, AlarmKit, WatchConnectivity, the wake-word engine and permissions. On the backend it covers Composio write tools, proxy execution and Monid endpoints.
- **Generated files can't drift:** the strings catalogs, blog, site tokens and island art are all checked against a fresh generation. The strings tool refuses Polish lines whose `%` placeholders don't match.
- **The imported pack is hash-checked,** and font binaries are refused, including inside archives.

## Findings (most severe first)

### Medium

1. **`check_forbidden_capabilities.sh:49,92` — the "networking only in these files" check misses several ways to reach the network**
   - **Problem:** `network_only='URLSession([^A-Za-z]|$)|URLRequest([^A-Za-z]|$)'` only matches the bare words `URLSession` and `URLRequest`. It doesn't catch:
     - `URLSessionWebSocketTask`, `URLSessionDataTask` / `DownloadTask` / `UploadTask` / `StreamTask`;
     - `URL.resourceBytes`;
     - `Data(contentsOf:)` / `String(contentsOf:)` with a web URL;
     - `NSURLConnection`;
     - `CFReadStream` / `CFHTTPMessage`.
   - **Failure scenario:** A new view loads a picture with `Data(contentsOf: URL(string: "https://…")!)`, or opens a WebSocket. The guard passes, and Settings' "What leaves this iPhone" and the site's privacy lines become untrue without any check noticing (DOD-11).
   - **Fix:** add these patterns to `network_only`, keeping the same allow-list:
     - `URLSession(WebSocketTask|DataTask|DownloadTask|UploadTask|StreamTask|Task|Configuration)?([^A-Za-z]|$)`
     - `\.resourceBytes|NSURLConnection|CFReadStream|CFHTTPMessage`
     - `contentsOf: *URL\(string:`

     `URLSessionTransport` (an app type) must stay allowed.

2. **`check_forbidden_capabilities.sh:167-171` — no secret scan in three of the deployed services**
   - **Problem:** `secret_paths` covers the app, `project.yml`, `scripts`, `backend` and `contracts`, and `server/messaging` gets a value-only scan. `gateway/`, `server/voice-token/` and `site/` hold the OpenAI and ElevenLabs keys and the waitlist admin password in their environments, and they aren't scanned.
   - **Failure scenario:** A real key pasted into a gateway test or a voice-token fixture is committed with green CI.
   - **Fix:** run the value-only `messaging_secrets` pattern, extended with `xi_`, `ak_` and `monid_` values, over `gateway server/voice-token site voice-agent tools`, excluding `node_modules`. The header-name pattern (`xi-api-key`) would wrongly flag `server/voice-token/src/handler.js:127`.

### Low

3. **`tools/__pycache__/build_strings_catalog.cpython-313.pyc` is committed (since `45bf843`)**
   - **Problem:** `.gitignore` has no `__pycache__/` or `*.pyc`.
   - **Failure scenario:** The compiled bytecode can go stale against the source, and other runs keep adding new cache files to the working tree.
   - **Fix:** delete the file and add `__pycache__/` and `*.pyc` to `.gitignore`.

4. **`typecheck_app_logic.sh:68-84` — the list of files to type-check is maintained by hand**
   - **Problem:** A new app file that needs no UI framework isn't type-checked until someone adds it. For example, today's `DeviceConnecting` protocol in `DeviceConnections.swift` imports EventKit, so it can't be added anyway.
   - **Fix:** print a warning listing `DoddyApp`/`Shared` files whose imports are all in {Foundation, Observation, DoddyCore, os} and that aren't on the list. Warn rather than fail: a candidate may still use UI types declared elsewhere.

5. **`ci.sh:104-105` — no iPhone simulator gives a confusing failure**
   - **Problem:** If `xcrun simctl list` has no iPhone, `sim_id` is empty and xcodebuild fails on `id=` with a destination error that doesn't explain itself.
   - **Fix:** if it's empty, report `NOT RUN: no available iPhone simulator; set DODDY_DESTINATION`.

6. **`ci.sh:54` — the voice-token tests run one file by name**
   - **Problem:** CI runs `node --test server/voice-token/test/handler.test.js`, while its `package.json` runs `test/*.test.js`.
   - **Failure scenario:** A second test file is skipped in CI with green results.
   - **Fix:** use `npm test --prefix server/voice-token`, as the other services do.

7. **`check_island_art.sh:18-24` — the check writes into a tracked file**
   - **Problem:** The generator writes into the committed `IslandBoardArt.generated.swift` before the comparison.
   - **Failure scenario:** A run interrupted (Ctrl-C, crash) between the write and the restore leaves a modified tracked file.
   - **Fix:** restore from `$work/committed.swift` in the `trap`, or give the generator an output-path argument.

8. **`build_blog.py:71-75` — markdown links accept any scheme**
   - **Problem:** A `[x](javascript:…)` link is written as-is.
   - **Failure scenario:** Posts are owner-written and the CSP blocks inline script, so the impact is small.
   - **Fix:** allow only `https:`, `http:`, `mailto:`, `/` and `#`, and fail the build otherwise.

## Top fixes

| # | Fix | Finding | Effort | Risk |
|---|---|---|---|---|
| 1 | Widen the guard's network patterns | 1 | S | Low (allow-list unchanged; verify zero new hits) |
| 2 | Secret-value scan over gateway, voice-token, site, voice-agent, tools | 2 | S | Low |
| 3 | Remove the `.pyc`; ignore `__pycache__` | 3 | S | None |
| 4 | `npm test` for voice-token in CI; simulator NOT RUN message | 5, 6 | S | Low |
| 5 | Type-check candidate warning; island-art trap; blog link schemes | 4, 7, 8 | S | Low |

## Constitution evidence log

- **DOD-11 (privacy):**
  - **What the code enforces:** the privacy copy is backed by the guard, which runs in CI and passed today.
  - **Gaps:** findings 1 and 2. Until they're fixed, "networking only in these files" holds for `URLSession` and `URLRequest` only.
- **Honest results:** `ci.sh` never reports PASS for a step that didn't run (NOT RUN / SKIPPED / BLOCKED exit 2). Finding 6 is the one place where a test file could be silently left out.
- **Claims to limit:** the guard is a text search. It shows that certain code isn't present, and can't prove what the app does at runtime.

---

## Fix status (2026-10-11, owner approved "fix all")

| # | Status |
|---|---|
| 1 | fixed: `network_only` also matches session task and configuration types, `.resourceBytes`, `contentsOf: URL(string:`, `NSURLConnection` and CFNetwork streams. Each kind planted in a scratch copy fails the guard; `URLSessionTransport.shared` passes. |
| 2 | fixed: value-only secret scan over `gateway`, `server/voice-token`, `site`, `voice-agent` and `tools` (`node_modules`, `dist` and lockfiles excluded). A planted `sk_…` key, `…_API_KEY=sk-…` and `…_PASSWORD=…` each fail. |
| 3 | fixed: `.pyc` removed; `__pycache__/` and `*.pyc` ignored |
| 4 | fixed: `VoiceConfig.swift` and `ActivityLogStore.swift` added (17 files type-checked). The 9 non-UI files that need networking or EventKit types are listed by name on every run. |
| 5 | fixed: no iPhone simulator → `NOT RUN` with what to do |
| 6 | fixed: CI runs `npm test --prefix server/voice-token` (17 pass) |
| 7 | fixed: the trap restores the committed art. Checked with a hand edit: the check fails (exit 1) and the file is left exactly as it was. |
| 8 | fixed: links must start with `https://`, `http://`, `mailto:`, `/` or `#`; a `javascript:` link stops the build |

**Checks run:** `scripts/ci.sh --core-only`. Every step passes: the pack, the guard, both agent specs, the blog, the strings, 778 DoddyCore tests, the 17-file type-check, the island art, voice-token, backend, gateway, messaging and the site. The messaging DB tests are SKIPPED (no database) and the iOS app is NOT RUN.

# Plan: move `backend/` and `web/` from zod 3.25.76 to zod 4

- **Date:** 2026-11-13
- **Decided by:** proposal, owner approval pending. Nothing is upgraded by this file.
- **Status:** proposed
- **Replaces:** nothing. It gives `docs/OWNER_QUEUE.md` row 9 (the advisory on zod 3) a plan to decide on.

## Why
- `backend/` and `web/` pin `zod` 3.25.76 (July 2025). `server/messaging/` already pins 4.6.7, the current release (12 Oct 2026), so the team has a working zod 4 setup in the same repository (44 source files and 1 test file there import it).
- `backend/src/cappedArray.ts` exists because zod 3 judges an over-long array only after it has looked at every item, which costs memory in proportion to the body (its comment records the measurement and the advisory). Zod 4 is the version the advisory names as the fix. Whether 4.6.7 makes that guard unnecessary has to be measured, not assumed.
- A package that stays two majors behind makes later fixes harder to take.

## Where zod is used (counted by `grep` on 13 Nov 2026; rough, includes a few false positives)
| Folder | Files importing zod | What it does there |
|---|---|---|
| `backend/src` | 30 | every request body and tool contract, the environment (`config.ts`, 27 `.default(` calls), Logbook, flights, payments, decks, memory |
| `backend/test` | 3 | schemas used by tests; 36 `safeParse` and 42 `parse` calls |
| `web/src` | 5 | `api/schemas.ts`, `logbook/schema.ts`, `memory/schema.ts`, `owner/schema.ts`: the checks on the server's replies; `api/client.ts` takes a schema as a generic |
| `server/messaging/` | 44 src, 1 test | already on zod 4.6.7: out of scope, a source of patterns |
| `gateway/`, `site/`, `server/voice-token/`, `tools/` | 0 | do not use zod |

Every import in `backend/` and `web/` is from `"zod"` itself (none uses a subpath such as `zod/v4`).

## What changes in zod 4 that matters here
Taken from zod's own migration guide (`packages/docs/content/v4/changelog.mdx` in the zod repository, read on 13 Nov 2026), matched against these folders. Counts are lines, not files.

**Will not compile or will throw. Must be fixed by hand**
1. `z.record(valueSchema)` with one argument is gone. `backend/src/tools/contracts.ts` (2), `backend/src/payments/x402.ts` (1): `z.record(z.string(), z.unknown())`.
2. A record keyed by an enum is now exhaustive: every key must be present. `backend/src/web/logbook.ts` (2: tools, by_kind) and `web/src/logbook/schema.ts` (1: by_kind) use `z.record(z.enum(...), ...)` for counts that may be missing, so they need `z.partialRecord(...)`. A test with a missing key will show it; the inferred type changes too. Records keyed by a plain or regex string (`languages`, and `tools` in the web schema) are not affected.
3. `z.ZodTypeDef` is removed and `ZodType` has two type parameters (`Output`, `Input`), not three: `backend/src/flights/service.ts:78`. `z.ZodTypeAny` (`backend/src/capabilities.ts`, `backend/src/cappedArray.ts`, one backend test, `web/src/api/client.ts`) still works, but the guide says to use `z.ZodType`.
4. `backend/src/cappedArray.ts` uses zod 3 issue builders: `z.ZodIssueCode`, `z.getParsedType`, and `too_big` / `too_small` issues with `type`, `inclusive` and `exact`. Zod 4's issue shapes are different (`origin`, no `exact`), so this file is rewritten, or deleted if a measurement shows zod 4 refuses a long array before reading its items. Its callers (`memory/contract.ts` and the routes whose body cap is large) and `refuseLongList` keep the same refusal text, path and code, which the tests check.

**Compiles, behaves differently. Needs a test or a look**
5. `.default()` now returns the default without parsing it, and the value must match the output type. Zod 3 parsed it. Here the 9 lines outside `config.ts` (8 in `web/src`, 1 in `backend/src/web/logbook.ts`) are plain numbers and booleans, and `config.ts` defaults are plain strings, so nothing is expected to change, but `config.ts` also has a `z.preprocess` that deserves one test.
6. A default inside an optional field is now applied (`z.string().default("x").optional()` gives `"x"` for a missing key; zod 3 left it missing): `web/src/api/schemas.ts:32` (`signup`) is one.
7. `z.unknown()` and `z.any()` object keys are required at parse time from 4.4.0: `backend/src/tools/catalog.ts:410` (`data: z.unknown()` in a passthrough envelope), `backend/src/travel/kiwi.ts` and the `error` fields use `.optional()` and are fine. A provider reply with no `data` key would now be refused.
8. `.uuid()` is stricter (the variant bits are checked; `z.guid()` is the old laxness). 13 uses in `backend/src`, 2 in `web/src`. Every uuid-shaped string in `backend/test`, `web/test`, `web/e2e` and `contracts/` (190 of them) already has valid version and variant digits, so the shared fixtures should pass; a fixture added later with `00000000-0000-0000-0000-000000000001` would not.
9. `.email()` (3), `.url()` (4 in backend) and `.regex()` keep working; `.email()`, `.uuid()`, `.url()` on `z.string()` are deprecated in favour of `z.email()`, `z.uuid()`, `z.url()` (no urgency), and their stricter patterns can refuse an address or URL zod 3 accepted.
10. `z.number()` refuses `Infinity`, and `.int()` accepts safe integers only (`.int()`: 28 lines in `backend/src`, 25 in `web/src`).
11. Default error messages are worded differently (zod 3: "Required", "Expected string, received number"; zod 4: "Invalid input: expected string, received undefined"). Nothing in `backend/` or `web/` matches on those strings (searched for the common ones). Of the 5 places that read `.issues`, three use only `issue.path` to build their own refusal text; two put zod's `issue.message` into a text that people or the model see: `backend/src/decks/spec.ts:169` (problems listed for a deck) and `backend/src/flights/service.ts:81` (a refused tool call). Those two will read differently after the upgrade. Issue codes changed too (`invalid_enum_value` and `invalid_literal` became `invalid_value`; `invalid_string` became `invalid_format`), and no code in these folders reads them (`grep` found none).
12. `z.coerce.number()` has an input type of `unknown`, and a missing key with a coerce field now errors: one use, `backend/src/flights/duffel.ts:34`, inside an array, so not affected.

**Deprecated but still working. Leave for later**
13. The `message` option (a `grep` for `message:` finds over 200 lines in `backend/` and `web/`, many of them `AppError` texts rather than zod; `invalid_type_error`, `required_error` and `errorMap`, which are removed, appear nowhere), `.strict()` (about 190 lines) and `.passthrough()` (15 lines in 5 files of `backend/src`): the guide deprecates them for `error:`, `z.strictObject()` and `z.looseObject()`. They keep working in zod 4, so a mechanical rewrite is optional and belongs in its own pull request, if wanted.
14. `.refine()` no longer narrows through a type predicate; `ctx.path` is gone. No code here is known to depend on either; the compiler will say.

**Not in use here:** `.format()`, `.flatten()`, `.errors`, `.formErrors`, `.merge()`, `.nativeEnum()`, `.nonempty()`, `.deepPartial()`, `z.function()`, `z.promise()`, `.brand()`, `.ip()`, `.cidr()`, `z.intersection()`.

## Suggested order of work
Each step is one small pull request; each needs `npm test` in the folder and `scripts/ci.sh --only node` (web) or `--only backend`.
1. **Measure first (no code change).** In a scratch copy, install zod 4.6.7 in `backend/`, run the 400,000-empty-object body from the comment in `cappedArray.ts` against a plain `z.array(item).max(n)`, and record the heap growth. This decides step 4 and whether the advisory is closed by the upgrade alone.
2. **`web/` first** (5 files, no zod internals). Bump to an exact 4.6.7, change the two enum-keyed records to `partialRecord`, run `npm run typecheck`, `npm test` (173 tests) and `npm run build`.
3. **`backend/` mechanical fixes**: single-argument records, `ZodTypeDef`, enum-keyed records, `ZodTypeAny` to `ZodType`. Compile with zod 4 and fix what the compiler reports; do not change schemas that compile.
4. **`backend/src/cappedArray.ts`**: rewrite for zod 4's issue shape or remove it, according to step 1. Keep the same refusal text, `path` and `code` and the existing tests for them.
5. **`backend/` behaviour pass**: run the whole `npm test` (about 7 minutes) and the contracts and fixtures (`contracts/`); add tests for the `catalog.ts` envelope without `data` and for `config.ts` with a preprocessed value and defaults; read `scripts/ci.sh --only backend` and `--only node` results.
6. **Docs and records**: `DEPENDENCIES_AND_LICENSES.md`, `OWNER_QUEUE.md` row 9, `backend/` and `web/` READMEs where they name zod 3; update the comment in `cappedArray.ts` and `memory/contract.ts`.
7. **Optional, later**: the deprecated spellings (`error:`, `strictObject`, `z.email()`).

A route with fewer big steps exists: zod 3.25.x also ships the new engine under `import { z } from "zod/v4"`, so files can move one at a time while the package stays on 3.25.76. It leaves two zod APIs in the tree for a while, and whether the advisory's fix is in that copy has not been checked, so it is not the recommended route here.

## What the owner decides
1. Whether to do it at all now: the advisory is rated by the repository as "nothing urgent" (`OWNER_QUEUE.md` row 9), and `cappedArray` already limits the cost on the routes with large bodies.
2. Whether `web/` and `backend/` may move to exactly 4.6.7 (the version `server/messaging/` runs), pinned without a caret as every other dependency here is.
3. Whether the optional rewrite of deprecated spellings (step 7) is wanted, or the deprecated forms stay.
4. If step 1 shows zod 4 needs no guard: whether `cappedArray` and `refuseLongList` are deleted, which removes code that enforces a documented limit (ADR-711).

## Evidence
- Read: zod's migration guide, `package.json` of the three folders, `grep` of the folders named above (13 Nov 2026), `npm view zod` for the current release and its date.
- Run: `web/` tests on the current zod 3 setup (173 pass), as part of the vitest bump in the same pull request as this file. Nothing was run with zod 4. No schema was changed.
- From memory, not re-read: the community codemod `zod-v3-to-v4` named in the guide exists; this plan does not rely on it.

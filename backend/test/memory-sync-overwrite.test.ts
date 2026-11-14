import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { USER_A } from "./helpers.js";
import { startWeb, type WebRig } from "./webRig.js";

/**
 * Characterization of today's notes sync (research item 9; docs/decisions/2026-11-09-incremental-sync-design.md).
 * `PUT /v1/web/memory/notes` replaces the whole list, and the server keeps no revision. So two iPhones
 * on one account overwrite each other: the one that sends last wins and the other's notes are deleted.
 * This test passes while that is true. It is not a wanted behaviour: when versioned sync lands it must
 * be replaced by the "a stale device cannot delete a newer note" test described in the design.
 */

let rig: WebRig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const note = (n: number, text: string) => ({ id: uuid(n), text, source: "explicit_voice", capturedAt: "2026-10-21T10:00:00.000Z" });
const list = async (r: WebRig) => (await r.call("GET", "/v1/web/memory/notes?limit=100", { token: USER_A })).body.notes.map((n: { id: string }) => n.id);

test("KNOWN LIMITATION: a second iPhone with an older list deletes the first iPhone's newer note", async () => {
  rig = await startWeb();
  assert.equal((await rig.call("PUT", "/v1/web/memory/state", { token: USER_A, body: { notes: true, conversations: false } })).status, 200);
  const phone1 = [note(1, "Shared note"), note(2, "Only phone one has this")];
  const phone2 = [note(1, "Shared note")]; // phone two has not synced yet

  assert.equal((await rig.call("PUT", "/v1/web/memory/notes", { token: USER_A, body: { items: phone1 } })).status, 200);
  assert.deepEqual((await list(rig)).sort(), [uuid(1), uuid(2)]);

  // Phone two sends its stale snapshot and is told "1 note kept".
  const res = await rig.call("PUT", "/v1/web/memory/notes", { token: USER_A, body: { items: phone2 } });
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { count: 1 });

  // Phone one's note 2 is gone from the server, with no conflict reported to either phone.
  assert.deepEqual(await list(rig), [uuid(1)]);
});

test("KNOWN LIMITATION: an edit made on one iPhone is rolled back by the other iPhone's older copy", async () => {
  rig = await startWeb();
  assert.equal((await rig.call("PUT", "/v1/web/memory/state", { token: USER_A, body: { notes: true, conversations: false } })).status, 200);
  await rig.call("PUT", "/v1/web/memory/notes", { token: USER_A, body: { items: [note(1, "Version two, edited on phone one")] } });
  await rig.call("PUT", "/v1/web/memory/notes", { token: USER_A, body: { items: [note(1, "Version one, old copy on phone two")] } });
  const [n] = (await rig.call("GET", "/v1/web/memory/notes", { token: USER_A })).body.notes;
  assert.equal(n.text, "Version one, old copy on phone two");
});

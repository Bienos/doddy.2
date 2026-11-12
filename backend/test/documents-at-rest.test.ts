import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { DOCUMENT_LINK_TTL_SECONDS, DocumentLinks, documentDisposition, DocumentSeal, serveDocument } from "../src/documents.js";
import { AppError } from "../src/errors.js";
import { MemoryCipher } from "../src/memory/crypto.js";
import { Store } from "../src/store.js";
import { KIND_INFO } from "../src/tools/claude.js";
import { USER_A } from "./helpers.js";
import { startWeb, type WebRig } from "./webRig.js";

/**
 * Documents encrypted at rest (decision 2026-11-12-documents-at-rest): a file's name and bytes are
 * stored encrypted, bound to their account and row; older plain-text rows are encrypted once by the
 * sweep; a file's receipt names its kind only; a signed link is sandboxed, lives a day and is checked
 * against the row on every open.
 */

let rig: WebRig | undefined;
const stores: Store[] = [];
afterEach(async () => {
  await rig?.close();
  rig = undefined;
  for (const store of stores.splice(0)) await store.close();
});

const LINK_KEY = Buffer.alloc(32, 7);
const links = new DocumentLinks(LINK_KEY, "https://api.doddy.test");

async function makeDocument(r: WebRig, title: string, kind = "pdf", token = USER_A) {
  const args = { kind, title, request: "A one-page summary for the owner" };
  const asked = await r.call("POST", "/v1/tools/prepare", { token, body: { tool: "make_document", arguments: args } });
  assert.equal(asked.status, 200, asked.text);
  const ran = await r.call("POST", "/v1/tools/run", { token, body: { tool: "make_document", arguments: args, timeZone: "Europe/Warsaw", approvalId: asked.body.approvalId } });
  assert.equal(ran.status, 200, ran.text);
  await r.tools.settle();
  return ran.body as { document: { url: string }; receipt: { summary: string } };
}

const raw = async (store: Store, id: string) =>
  (await store.db.query<{ user_id: string; name: string; name_ciphertext: Uint8Array | null; body: Uint8Array | null; key_version: number | null }>(
    "SELECT user_id, name, name_ciphertext, body, key_version FROM documents WHERE id = $1",
    [id],
  )).rows[0]!;

const open = (r: WebRig, url: string) => {
  const u = new URL(url);
  return r.call("GET", `${u.pathname}${u.search}`, { token: null });
};

test("a file and its name are stored encrypted, and read back only for their own account and row", async () => {
  rig = await startWeb();
  const made = await makeDocument(rig, "Secret plan for Anna");
  const id = links.claim(new URL(made.document.url))!.id;
  const stored = await raw(rig.store, id);
  assert.equal(stored.key_version, 1);
  assert.equal(stored.name, "", "no name in plain text");
  assert.ok(stored.name_ciphertext && stored.body);
  assert.ok(!Buffer.from(stored.name_ciphertext).toString("latin1").includes("Anna"), "the name column holds ciphertext");
  assert.ok(!Buffer.from(stored.body).toString("latin1").includes("DEMO PDF"), "the file column holds ciphertext");

  const row = await rig.store.getDocument(id);
  assert.equal(row?.name, "Secret plan for Anna.pdf");
  assert.equal(row?.body?.toString("utf8"), "DEMO PDF: Secret plan for Anna");
  assert.equal((await rig.store.getDocument(id, { file: false }))?.body, null, "a status check doesn't read the file");
  const listed = await rig.store.listDocuments(stored.user_id, 10);
  assert.deepEqual(listed.map((d) => [d.name, d.size]), [["Secret plan for Anna.pdf", Buffer.byteLength("DEMO PDF: Secret plan for Anna")]]);

  // The same ciphertext moved to another account, or its name and file swapped, no longer reads.
  await rig.store.db.query("UPDATE documents SET user_id = 'someone-else' WHERE id = $1", [id]);
  assert.equal(await rig.store.getDocument(id), null);
  assert.deepEqual(await rig.store.listDocuments("someone-else", 10), []);
  await rig.store.db.query("UPDATE documents SET user_id = $2, name_ciphertext = body WHERE id = $1", [id, stored.user_id]);
  assert.equal(await rig.store.getDocument(id), null);
  // And with another key nothing reads either.
  await rig.store.db.query("UPDATE documents SET name_ciphertext = $2 WHERE id = $1", [id, stored.name_ciphertext]);
  assert.ok(await rig.store.getDocument(id));
  rig.store.sealDocumentsWith(new DocumentSeal(new MemoryCipher(Buffer.alloc(32, 9))));
  assert.equal(await rig.store.getDocument(id), null);
  assert.equal(await rig.store.getOwnDocument(stored.user_id, id), null);
});

test("without the key no file is made and nothing is written, as with kept memory", async () => {
  rig = await startWeb({ memoryKey: null });
  const args = { kind: "pdf", title: "Plan", request: "A one-page summary for the owner" };
  const asked = await rig.call("POST", "/v1/tools/prepare", { token: USER_A, body: { tool: "make_document", arguments: args } });
  assert.equal(asked.status, 503, asked.text);
  assert.equal(asked.body.error.code, "live_not_configured");
  assert.equal(Number((await rig.store.db.query<{ n: string }>("SELECT count(*) AS n FROM documents")).rows[0]!.n), 0);
  await assert.rejects(rig.store.startDocument("u", "a.md", "text/markdown", 1), (e: unknown) => e instanceof AppError && e.code === "live_not_configured");
  await assert.rejects(rig.store.finishDocument("u", "x", "a.md", "text/markdown", Buffer.from("x")), (e: unknown) => e instanceof AppError && e.code === "live_not_configured");
});

test("rows written in plain text before are read as before, and the sweep encrypts each once", async () => {
  const store = await Store.memory();
  stores.push(store);
  const insert = (id: string, status: string, body: Buffer | null) =>
    store.db.query("INSERT INTO documents (id, user_id, status, name, mime, body, created_at) VALUES ($1, 'u', $2, $3, 'application/pdf', $4, 1)", [id, status, `${id}.pdf`, body]);
  await insert("aaaaaaaaaaaaaaaaaaaaaaaa", "ready", Buffer.from("old file"));
  await insert("bbbbbbbbbbbbbbbbbbbbbbbb", "failed", null);
  await insert("cccccccccccccccccccccccc", "working", null);

  // No key: the sweep does nothing and the old rows still read.
  assert.equal(await store.sealPlaintextDocuments(), 0);
  assert.equal((await store.getDocument("aaaaaaaaaaaaaaaaaaaaaaaa"))?.body?.toString(), "old file");

  store.sealDocumentsWith(new DocumentSeal(new MemoryCipher(Buffer.alloc(32, 6))));
  const before = await store.listDocuments("u", 10);
  assert.equal(await store.sealPlaintextDocuments(), 2, "the ready and the failed row; a row still being made is left to its job");
  assert.equal(await store.sealPlaintextDocuments(), 0, "a second sweep changes nothing");
  assert.deepEqual(await store.listDocuments("u", 10), before, "the same names and sizes");
  const ready = await raw(store, "aaaaaaaaaaaaaaaaaaaaaaaa");
  assert.equal(ready.key_version, 1);
  assert.equal(ready.name, "");
  assert.ok(!Buffer.from(ready.body!).toString("latin1").includes("old file"));
  assert.equal((await store.getDocument("aaaaaaaaaaaaaaaaaaaaaaaa"))?.body?.toString(), "old file");
  assert.equal((await raw(store, "cccccccccccccccccccccccc")).key_version, null);

  // Once the old job is failed, the next sweep encrypts its name too.
  await store.failStaleDocuments(Date.now(), 0);
  assert.equal(await store.sealPlaintextDocuments(), 1);
  assert.equal((await store.getDocument("cccccccccccccccccccccccc"))?.name, "cccccccccccccccccccccccc.pdf");
});

test("a file's receipt names its kind, never the user's words", async () => {
  rig = await startWeb();
  const made = await makeDocument(rig, "Divorce papers for Anna", "doc");
  assert.equal(made.receipt.summary, "Started a document.");
  const bodies = (await rig.store.db.query<{ body: string }>("SELECT body FROM tool_receipts")).rows.map((r) => r.body).join("\n");
  assert.ok(!/Anna|Divorce/.test(bodies), "no title in any stored receipt");
});

test("a signed link: sandboxed, nosniff, inline only for the kinds Doddy makes, a day long, and checked against the row", async () => {
  rig = await startWeb();
  const made = await makeDocument(rig, "Trip");
  const id = links.claim(new URL(made.document.url))!.id;
  const owner = (await raw(rig.store, id)).user_id;

  const res = await open(rig, made.document.url);
  assert.equal(res.status, 200);
  assert.equal(res.text, "DEMO PDF: Trip");
  assert.equal(res.headers.get("content-security-policy"), "sandbox; default-src 'none'");
  assert.equal(res.headers.get("x-content-type-options"), "nosniff");
  assert.match(res.headers.get("content-disposition")!, /^inline; filename="Trip.pdf"/);
  assert.equal(new URL(made.document.url).searchParams.get("exp"), String(Math.floor(rig.clock.ms / 1000) + DOCUMENT_LINK_TTL_SECONDS));

  // A link made for another account, for the same file, doesn't open it.
  const forOther = links.link(id, "someone-else", new Date(rig.clock.ms));
  assert.equal((await open(rig, forOther)).status, 404);
  assert.equal((await open(rig, `${forOther}&status=1`)).status, 404);

  // After a day the genuine link says it expired, and its status is "gone".
  rig.clock.advance((DOCUMENT_LINK_TTL_SECONDS + 1) * 1000);
  const expired = await open(rig, made.document.url);
  assert.equal(expired.status, 404);
  assert.match(expired.text, /This link has expired/);
  assert.ok(!expired.text.includes("DEMO PDF"));
  assert.deepEqual((await open(rig, `${made.document.url}&status=1`)).body, { status: "gone" });

  // A fresh link works until the file is deleted, then never again.
  const fresh = links.link(id, owner, new Date(rig.clock.ms));
  assert.equal((await open(rig, fresh)).status, 200);
  await rig.store.db.query("DELETE FROM documents WHERE id = $1", [id]);
  const gone = await open(rig, fresh);
  assert.equal(gone.status, 404);
  assert.match(gone.text, /This link doesn't work any more/);
  assert.deepEqual((await open(rig, `${fresh}&status=1`)).body, { status: "gone" });
});

test("only the kinds Doddy makes open inline; any other type is a sandboxed download", async () => {
  for (const info of Object.values(KIND_INFO)) assert.equal(documentDisposition(info.mime), "inline", info.mime);
  for (const mime of ["text/html", "text/html; charset=utf-8", "image/svg+xml", "application/xhtml+xml", "text/xml", "application/javascript", "application/octet-stream", ""]) {
    assert.equal(documentDisposition(mime), "attachment", mime);
  }
  assert.equal(documentDisposition("Application/PDF"), "inline");

  // Served: a row whose type isn't one of them goes out as an attachment, still sandboxed.
  const id = "abcdefghijklmnopqrstuvwx";
  const at = new Date("2026-11-12T10:00:00Z");
  const store = {
    getDocument: async () => ({ id, user_id: "u", status: "ready", name: "page.html", mime: "text/html", body: Buffer.from("<script>x</script>"), created_at: at.getTime() }),
  } as unknown as Parameters<typeof serveDocument>[4];
  let headers: Record<string, string | number> = {};
  const res = { writeHead: (_: number, h: Record<string, string | number>) => void (headers = h), end: () => {} } as unknown as Parameters<typeof serveDocument>[1];
  assert.equal(await serveDocument({} as Parameters<typeof serveDocument>[0], res, new URL(links.link(id, "u", at)), links, store, at), 200);
  assert.match(String(headers["content-disposition"]), /^attachment; filename="page.html"/);
  assert.equal(headers["content-security-policy"], "sandbox; default-src 'none'");
  assert.equal(headers["x-content-type-options"], "nosniff");
});

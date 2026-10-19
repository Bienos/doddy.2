#!/usr/bin/env node
// Terminal harness for calls Doddy makes for you (ADR-500): live test #1 without the iPhone app.
// It uses the same API as the app, with its own anonymous account and your verified phone.
//
//   export DODDY_SERVER=https://<doddy-messaging host>
//   node scripts/task-call.mjs init --phone "+48 600 100 200"     # account + SMS code to your phone
//   node scripts/task-call.mjs status                              # is the feature on? any agent problems?
//   node scripts/task-call.mjs brief --to "+48 601 200 300" --callee "Drugi telefon" \
//        --me Anna --me-gen Anny --goal "Sprawdzić, czy laptop jest gotowy." \
//        --question "Czy laptop z serwisu jest gotowy?" [--fact reference:"Zlecenie 12345"] [--max 240]
//   node scripts/task-call.mjs approve      # shows the card, asks you to type TAK, dials
//   node scripts/task-call.mjs live         # live transcript; then the answer card
//   node scripts/task-call.mjs takeover     # (second terminal) your phone rings; press 1 to join
//   node scripts/task-call.mjs end          # (second terminal) Doddy says goodbye and hangs up
//   node scripts/task-call.mjs card         # answer card, cost, deletion receipts
//   node scripts/task-call.mjs ack          # you have the card: the server deletes its copies
//
// The device token is kept in ~/.doddy-task-call.json (mode 600). Nothing here prints it.

import { chmodSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline/promises";

const STATE = join(homedir(), ".doddy-task-call.json");
const server = (process.env.DODDY_SERVER ?? "").replace(/\/$/, "");
const [cmd, ...rest] = process.argv.slice(2);

function args(list) {
  const out = { fact: [] };
  for (let i = 0; i < list.length; i++) {
    const key = list[i].replace(/^--/, "");
    const value = list[i + 1];
    if (key === "fact") out.fact.push(value); else out[key] = value;
    i++;
  }
  return out;
}
const load = () => (existsSync(STATE) ? JSON.parse(readFileSync(STATE, "utf8")) : {});
const save = (s) => { writeFileSync(STATE, JSON.stringify(s, null, 2)); chmodSync(STATE, 0o600); };
const ask = async (q) => { const rl = createInterface({ input: process.stdin, output: process.stdout }); const a = await rl.question(q); rl.close(); return a.trim(); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function api(method, path, body, token = load().token) {
  if (!/^https:\/\/|^http:\/\/(localhost|127\.0\.0\.1)[:/]/.test(server)) throw new Error("Set DODDY_SERVER to the https URL of doddy-messaging.");
  const res = await fetch(server + path, {
    method,
    headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body !== undefined ? { "content-type": "application/json" } : {}) },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  return { status: res.status, json };
}

function must(r, ...ok) {
  if (!ok.includes(r.status)) {
    console.error(`HTTP ${r.status}: ${JSON.stringify(r.json)}`);
    process.exit(1);
  }
  return r.json;
}

function printCard(p) {
  console.log("\n=== Karta rozmowy (do zatwierdzenia) ===");
  console.log(`Dzwoni do:   ${p.callee.name}, ${p.callee.phone}`);
  console.log(`Skąd numer:  ${p.callee.source}${p.callee.sourceLabel ? ` (${p.callee.sourceLabel})` : ""}`);
  console.log(`Cel:         ${p.goal}`);
  console.log(`Powie:       „${p.openingLine}”`);
  console.log(`Może podać:  ${p.facts.length ? p.facts.map((f) => `${f.kind}: ${f.text}`).join("; ") : "(nic)"}`);
  console.log("Nie zrobi:");
  for (const f of p.forbidden) console.log(`  - ${f}`);
  console.log(`Najdłużej:   ${Math.round(p.maxDurationSecs / 60)} min · nagrywanie dźwięku: ${p.recordsAudio ? "tak" : "nie"} · ważna do ${p.approvableUntil}`);
}

const money = (micros, currency) => `${(micros / 1e6).toFixed(4)} ${currency}`;

function printResult(kase) {
  const r = kase.results.at(-1);
  if (!r) { console.log("Brak wyniku."); return; }
  console.log(`\n=== Wynik (${r.state}) ===`);
  if (r.result) {
    const x = r.result;
    console.log(`Wynik:        ${x.outcome}  · pewność: ${x.confidence}${x.confidenceReasons.length ? ` (${x.confidenceReasons.join(", ")})` : ""}`);
    console.log(`Podsumowanie: ${x.summary}`);
    if (x.quote) console.log(`Cytat:        „${x.quote.text}” (linia ${x.quote.line})`);
    console.log(`Następny krok: ${x.nextStep.text}`);
    for (const w of x.warnings) console.log(`Uwaga:        ${w.kind} w linii ${w.line}`);
    console.log("Zapis:");
    x.transcript.forEach((l, i) => console.log(`  ${String(i).padStart(2)} ${l.speaker === "doddy" ? "Doddy" : "Rozmówca"}: ${l.text}`));
  }
  const c = kase.cost;
  console.log(`\nKoszt: ${money(c.totalMicros, c.currency)}${c.approximate ? " (część szacowana)" : ""}${c.complete ? "" : `; niepełny${c.pending ? ", czeka na dane" : ""}${c.unknownParts.length ? `, nieznane: ${c.unknownParts.join(", ")}` : ""}`}`);
  for (const i of c.items) console.log(`  ${i.component}${i.ref ? `[${i.ref.slice(0, 8)}]` : ""}: ${i.status}${i.amountMicros != null ? ` ${money(i.amountMicros, i.currency)}` : ""}${i.quantity != null ? ` (${i.quantity} ${i.unit})` : ""}`);
  console.log("Usunięte:");
  for (const d of kase.deletions) console.log(`  ${d.item} @ ${d.location}: ${d.result} (${d.reason})`);
}

const state = load();
const caseId = () => rest.find((x) => /^[0-9a-f-]{36}$/.test(x)) ?? state.caseId;

switch (cmd) {
  case "init": {
    const a = args(rest);
    if (!a.phone) throw new Error("--phone is required");
    a.phone = a.phone.replace(/[\s\-().]/g, ""); // E.164, as the app sends it
    const acct = must(await api("POST", "/v1/accounts", undefined, null), 201);
    save({ token: acct.deviceToken });
    must(await api("POST", "/v1/phone/verification", { phone: a.phone }), 202, 204, 200);
    const code = await ask("Kod z SMS-a: ");
    must(await api("POST", "/v1/phone/verification/check", { phone: a.phone, code }), 200);
    console.log("Gotowe: konto utworzone, numer zweryfikowany.");
    break;
  }
  case "status":
    console.log(JSON.stringify(must(await api("GET", "/v1/call-cases/availability"), 200), null, 2));
    break;
  case "brief": {
    const a = args(rest);
    for (const k of ["to", "callee", "me", "me-gen", "goal", "question"]) if (!a[k]) throw new Error(`--${k} is required`);
    const facts = a.fact.map((f) => { const i = f.indexOf(":"); return { kind: f.slice(0, i), text: f.slice(i + 1) }; });
    const p = must(await api("POST", "/v1/call-cases", {
      kind: "ask", callee: { name: a.callee, phone: a.to, source: "typed" }, principal: { name: a.me, genitive: a["me-gen"] },
      goal: a.goal, question: a.question, facts, ...(a.max ? { maxDurationSecs: Number(a.max) } : {}),
    }), 201);
    save({ ...state, caseId: p.caseId, digest: p.digest });
    printCard(p);
    console.log(`\nSprawa: ${p.caseId}. ${p.callableNow ? "Teraz: node scripts/task-call.mjs approve" : "Poza godzinami 8–20: zatwierdź z --at <ISO>."}`);
    break;
  }
  case "approve": {
    const kase = must(await api("GET", `/v1/call-cases/${caseId()}`), 200);
    if (!kase.preview) throw new Error("This case has no brief any more.");
    printCard(kase.preview);
    const a = args(rest.filter((x) => !/^[0-9a-f-]{36}$/.test(x)));
    if ((await ask("\nWpisz TAK, aby Doddy zadzwonił: ")) !== "TAK") { console.log("Nie zatwierdzono. Nic nie wybrano."); break; }
    const r = await api("POST", `/v1/call-cases/${caseId()}/approve`, { digest: kase.preview.digest, ...(a.at ? { at: a.at } : {}) });
    console.log(`HTTP ${r.status}: ${JSON.stringify(r.json)}`);
    break;
  }
  case "live": {
    let cursor;
    let phase;
    for (;;) {
      const v = must(await api("GET", `/v1/call-cases/${caseId()}/live${cursor ? `?after=${encodeURIComponent(cursor)}` : ""}`), 200);
      if (v.attempt?.phase !== phase) { phase = v.attempt?.phase; console.log(`[${new Date().toLocaleTimeString("pl-PL")}] ${phase}${v.attempt?.takeover ? ` · przejęcie: ${v.attempt.takeover.state}` : ""}`); }
      for (const l of v.lines) console.log(`  ${l.speaker === "doddy" ? "Doddy" : "Rozmówca"}: ${l.text}`);
      cursor = v.cursor ?? cursor;
      if (phase === "ended" || !v.attempt) break;
      await sleep(1000);
    }
    console.log("Rozmowa zakończona. Czekam na kartę (do 4 min)...");
    for (let i = 0; i < 50; i++) {
      const kase = must(await api("GET", `/v1/call-cases/${caseId()}`), 200);
      if (kase.results.at(-1)?.state === "ready") { printResult(kase); break; }
      await sleep(5000);
    }
    break;
  }
  case "takeover":
    console.log(JSON.stringify(must(await api("POST", `/v1/call-cases/${caseId()}/takeover`), 202)));
    console.log("Twój telefon zadzwoni z numeru Doddy'ego. Odbierz i naciśnij 1.");
    break;
  case "end":
    console.log(JSON.stringify(must(await api("POST", `/v1/call-cases/${caseId()}/end`), 202)));
    break;
  case "card":
    printResult(must(await api("GET", `/v1/call-cases/${caseId()}`), 200));
    break;
  case "ack": {
    const kase = must(await api("GET", `/v1/call-cases/${caseId()}`), 200);
    const r = kase.results.at(-1);
    if (!r?.resultDigest) throw new Error("No ready result to acknowledge.");
    const out = must(await api("POST", `/v1/call-cases/${caseId()}/ack`, { attemptId: r.attemptId, resultDigest: r.resultDigest }), 200);
    for (const d of out.deletions) console.log(`  ${d.item} @ ${d.location}: ${d.result} (${d.reason})`);
    break;
  }
  default:
    console.log(readFileSync(new URL(import.meta.url), "utf8").split("\n").filter((l) => l.startsWith("//")).map((l) => l.slice(3)).join("\n"));
}

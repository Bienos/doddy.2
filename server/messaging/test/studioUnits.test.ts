// Studio without a database (ADR-584): the job contract and digest, the content rules, the research
// pack, every file check, the cost, and the whole pipeline against a fake Claude.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { SeenSources } from "../src/errands/researcher.js";
import { checkFiles, contrast, failed, pngSize, scanSvg, TEXT_COLOURS } from "../src/studio/checks.js";
import { fileIdsOf, parseSkills, STUDIO_MAKE_TOOL_TYPE, STUDIO_RESEARCH_TOOL_TYPES, AnthropicStudioApi } from "../src/studio/model.js";
import { buildPack, costOf, runStudio, type StudioControl } from "../src/studio/pipeline.js";
import { appState, contentProblems, jobBody, jobDigest, jobJson, type RenderContent, type Stage } from "../src/studio/schema.js";
import { content, FakeStudioApi, goodFiles, goodSvg, job, packOutput, pdf, png, researchMessage, URLS } from "./studioFakes.js";

const pack = () => {
  const seen = new SeenSources();
  for (const u of URLS) seen.add(u, "t");
  return buildPack(packOutput().claims, seen, new Map(URLS.map((u) => [u, "2026-10-22T10:00:00.000Z"])));
};
const render = (over = {}): RenderContent => ({ ...content(over), language: "pl", ...pack() });

describe("the job and its digest", () => {
  test("a strict job: optional fields absent, never empty; the digest is SHA-256 of the canonical JSON", () => {
    const vector = jobBody.parse({
      kind: "brief", topic: "Pompy ciepła w Polsce: ile kosztują i czy się opłacają?", audience: "właściciel domu", length: "standard",
      style: "plain", language: "pl", details: "Bez żargonu, \"po ludzku\".\nKrótko.",
      sources: [{ url: "https://www.gov.pl/web/klimat", title: "Ministerstwo Klimatu i Środowiska" }],
    });
    assert.equal(jobJson(vector), '{"audience":"właściciel domu","details":"Bez żargonu, \\"po ludzku\\".\\nKrótko.","kind":"brief","language":"pl","length":"standard","sources":[{"title":"Ministerstwo Klimatu i Środowiska","url":"https://www.gov.pl/web/klimat"}],"style":"plain","topic":"Pompy ciepła w Polsce: ile kosztują i czy się opłacają?"}');
    assert.equal(jobDigest(vector).toString("hex"), "c7c404fa57d3b4932b1b03c4a0092bf7df504d8894ef7a8c27040f453588321f", "the app pins the same vector");
    assert.equal(jobDigest(jobBody.parse({ kind: "brief", topic: "Heat pumps", length: "short", style: "lively", language: "en" })).toString("hex"),
      "69ca45fdd2c0e1932392ebc5d3b258691a78cc9bc28fbda954f40c9808889ea6");
    for (const bad of [
      { ...job, kind: "deck" }, { ...job, topic: "  " }, { ...job, topic: "x".repeat(301) }, { ...job, language: "PL" },
      { ...job, sources: [] }, { ...job, audience: "" }, { ...job, extra: 1 }, { ...job, details: null },
      { ...job, sources: [{ url: "javascript:alert(1)", title: "x" }] }, { ...job, sources: Array(6).fill({ url: "https://a.b", title: "x" }) },
    ]) assert.equal(jobBody.safeParse(bad).success, false, JSON.stringify(bad).slice(0, 80));
  });

  test("the app sees researching, making and checking for a running item", () => {
    assert.equal(appState("draft", null), undefined);
    assert.equal(appState("running", "plan"), "researching");
    assert.equal(appState("running", "write"), "researching");
    assert.equal(appState("running", "make"), "making");
    assert.equal(appState("running", "store"), "checking");
    assert.equal(appState("needs_look", null), "needs_look");
  });
});

describe("the research pack and the content rules", () => {
  test("claims whose page the run never saw are dropped; sources are numbered with when they were seen", () => {
    const p = pack();
    assert.deepEqual(p.claims.map((c) => [c.id, c.source]), [["c1", "s1"], ["c2", "s2"], ["c3", "s3"]]);
    assert.equal(p.claims.some((c) => c.text.includes("nie była czytana")), false);
    assert.deepEqual(p.sources.map((s) => s.url), URLS);
    assert.equal(p.sources[0]!.fetchedAt, "2026-10-22T10:00:00.000Z");
  });

  test("good content passes; unknown claims, missing claims and broken limits are named", () => {
    assert.deepEqual(contentProblems(content(), pack()), []);
    const c = content();
    c.sections[0]!.points[0]!.claims = ["c9"];
    c.infographic.facts = c.infographic.facts.slice(0, 2);
    c.infographic.headline.claims = [];
    c.infographic.altText = " ";
    c.infographic.chart.kind = "donut";
    c.infographic.chart.data = [{ label: "a", value: -1 }, { label: "b", value: Number.NaN }];
    const problems = contentProblems(c, pack());
    for (const want of ["c9", "facts: 2", "headline names no claim", "alt text is empty", "negative in a donut", "isn't a number"]) {
      assert.ok(problems.some((p) => p.includes(want)), `${want} in ${problems.join(" | ")}`);
    }
  });
});

describe("the file checks", () => {
  test("files a correct render makes pass every check", () => {
    const c = render();
    const files = Object.entries(goodFiles(c)).map(([name, bytes]) => ({ name: name as never, bytes }));
    const checks = checkFiles(files, c);
    assert.deepEqual(failed(checks), [], JSON.stringify(failed(checks)));
    assert.ok(checks.length >= 10);
  });

  test("orange text, small text, scripts, external links, a missing fact and missing alt text all fail", () => {
    const c = render();
    const svgCheck = (svg: string) => {
      const files = Object.entries({ ...goodFiles(c), "infographic.svg": Buffer.from(svg) }).map(([name, bytes]) => ({ name: name as never, bytes }));
      return failed(checkFiles(files, c)).map((x) => x.name);
    };
    assert.deepEqual(svgCheck(goodSvg(c).replace("fill: #171715", "fill: #ff6a00")), ["svg_text_colours", "svg_contrast"]);
    assert.deepEqual(svgCheck(goodSvg(c).replace("font-size: 28px", "font-size: 12px")), ["svg_min_text_size"]);
    assert.deepEqual(svgCheck(goodSvg(c, '<script>alert(1)</script>')), ["svg_safe"]);
    assert.deepEqual(svgCheck(goodSvg(c, '<a href="https://evil.example"><rect width="1" height="1"/></a>')), ["svg_safe"]);
    assert.deepEqual(svgCheck(goodSvg(c, '<rect onclick="x()" width="1" height="1"/>')), ["svg_safe"]);
    assert.deepEqual(svgCheck(goodSvg(c, '<image href="data:image/png;base64,AA"/>')), ["svg_safe"]);
    assert.deepEqual(svgCheck(goodSvg(c).replace("Oszczędność: 30–50% rocznie", "")), ["svg_text_present"]);
    assert.deepEqual(svgCheck(goodSvg(c).replace(/<desc>.*<\/desc>/, "")), ["svg_alt_text"]);
    assert.deepEqual(svgCheck(goodSvg(c).replace('viewBox="0 0 1080 1350"', 'viewBox="0 0 800 600"')), ["svg_size"]);
    assert.deepEqual(svgCheck("not svg"), ["svg_parses"]);
  });

  test("wrapped lines still count as the fact; fill and size are inherited from a parent group", () => {
    const c = render();
    const svg = goodSvg(c).replace("<text x=\"60\" y=\"180\" style=\"font-size: 28px; font-family: 'DejaVu Sans'; fill: #171715\">Montaż: 40–60 tys. zł</text>",
      '<g style="font-size: 30px; fill: #A64B00"><text x="60" y="180">Montaż:</text><text x="60" y="210">40–60 tys. zł</text></g>');
    assert.notEqual(svg, goodSvg(c));
    const scan = scanSvg(svg)!;
    assert.ok(scan.texts.some((t) => t.text === "Montaż:" && t.fill === "#A64B00" && t.fontSize === 30));
    const files = Object.entries({ ...goodFiles(c), "infographic.svg": Buffer.from(svg) }).map(([name, bytes]) => ({ name: name as never, bytes }));
    assert.deepEqual(failed(checkFiles(files, c)), []);
  });

  test("PNG sizes are exact; a PDF with active content or no pages fails; stream bytes don't count", () => {
    assert.deepEqual(pngSize(png(1080, 1350)), { width: 1080, height: 1350 });
    assert.equal(pngSize(Buffer.from("GIF89a")), undefined);
    const c = render();
    const run = (over: Record<string, Buffer>) => failed(checkFiles(Object.entries({ ...goodFiles(c), ...over }).map(([name, bytes]) => ({ name: name as never, bytes })), c)).map((x) => x.name);
    assert.deepEqual(run({ "infographic.png": png(1080, 1080) }), ["png_phone_size"]);
    assert.deepEqual(run({ "infographic-a4.png": png(2480, 3508) }), ["png_print_size"]);
    assert.deepEqual(run({ "brief.pdf": pdf("/AA << /O << /S /JavaScript /JS (app.alert(1)) >> >> ") }), ["pdf_no_active_content"]);
    assert.deepEqual(run({ "brief.pdf": Buffer.from("%PDF-1.4\n%%EOF") }), ["pdf_valid"]);
    assert.deepEqual(run({ "brief.pdf": Buffer.from("<html>") }), ["pdf_valid"]);
    const files = Object.entries(goodFiles(c)).filter(([n]) => n !== "brief.pdf").map(([name, bytes]) => ({ name: name as never, bytes }));
    assert.deepEqual(failed(checkFiles(files, c)).map((x) => x.name), ["files_present"]);
  });

  test("the text colours all pass 4.5:1 on paper; orange doesn't", () => {
    for (const colour of TEXT_COLOURS) assert.ok(contrast(colour, "#FFF7E9") >= 4.5, colour);
    assert.ok(contrast("#FF6A00", "#FFF7E9") < 4.5);
  });
});

describe("the model calls", () => {
  test("research has only web search and fetch, capped, with blocked domains; make has only code execution", () => {
    const api = new AnthropicStudioApi("sk-ant-test", {
      skills: [{ id: "skill_a", version: "latest" }], maxSearches: 15, maxFetches: 12, blockedDomains: ["spam.example"], taskBudgetTokens: 150_000,
    });
    const tools = api.researchTools();
    assert.deepEqual(tools.map((t) => t.type), [...STUDIO_RESEARCH_TOOL_TYPES]);
    assert.deepEqual(tools.map((t) => t.max_uses), [15, 12]);
    for (const t of tools) assert.deepEqual((t as { blocked_domains?: string[] }).blocked_domains, ["spam.example"]);
    assert.equal("allowed_domains" in tools[0]!, false, "allowed and blocked domains can't be combined");
    const open = new AnthropicStudioApi("sk-ant-test", { skills: [], maxSearches: 1, maxFetches: 1, blockedDomains: [], taskBudgetTokens: 20_000 });
    assert.equal("blocked_domains" in open.researchTools()[0]!, false);
    assert.equal(STUDIO_MAKE_TOOL_TYPE, "code_execution_20250825");
    assert.deepEqual(parseSkills("skill_a, skill_b@3"), [{ id: "skill_a", version: "latest" }, { id: "skill_b", version: "3" }]);
    assert.deepEqual(parseSkills(""), []);
    assert.deepEqual(fileIdsOf([{ type: "bash_code_execution_tool_result", content: { type: "bash_code_execution_result", content: [{ file_id: "f1" }, { x: 1 }] } }, { type: "text" }]), ["f1"]);
  });

  test("cost: Opus 5.5 list prices and $10 per 1,000 searches", () => {
    assert.equal(costOf({ inputTokens: 1_000_000, outputTokens: 100_000, cacheReadTokens: 1_000_000, cacheWriteTokens: 0 }, 10), 4 + 2 + 0.2 + 0.1);
  });
});

describe("the pipeline against a fake Claude", () => {
  const control = (over: Partial<StudioControl> = {}) => {
    const stages: Stage[] = [];
    const logs: { msg: string; extra?: object }[] = [];
    return {
      stages, logs,
      c: {
        deadline: new Date(Date.now() + 60_000), isCancelled: async () => false, setStage: async (s: Stage) => { stages.push(s); },
        jobLimitUsd: 50, cancelPollMs: 5, log: (msg: string, extra?: object) => logs.push({ msg, extra }), ...over,
      } satisfies StudioControl,
    };
  };

  test("plan → research → pack → write → make → check: ready, every file kept, Anthropic's copies deleted and read back", async () => {
    const api = new FakeStudioApi();
    const { c, stages, logs } = control();
    const out = await runStudio(api, job, c);
    assert.equal(out.kind, "made", JSON.stringify(out));
    if (out.kind !== "made") return;
    assert.equal(out.state, "ready");
    assert.deepEqual(api.calls, ["plan", "research", "pack", "write", "make"]);
    assert.deepEqual(stages, ["plan", "research", "write", "make", "check"]);
    assert.deepEqual(out.files.map((f) => f.name).sort(), ["brief.pdf", "infographic-a4.png", "infographic.png", "infographic.svg"]);
    assert.deepEqual(out.pending, []);
    assert.equal(api.deleted.size, 4, "every file made at Anthropic is deleted there");
    assert.equal(out.result.title, "Pompy ciepła w Polsce");
    assert.deepEqual(out.result.sources.map((s) => s.url), URLS);
    assert.deepEqual(out.result.skills, api.skills);
    assert.equal(out.searches, 3, "the API's own count wins when higher");
    assert.ok(out.costUsd > 0);
    // The job reaches the model only as data, and the make step gets the checked content.
    assert.ok(JSON.parse(api.researchInputs[0]![0]!.content as string).job.topic === job.topic);
    const made = JSON.parse((api.makeInputs[0]![0]!.content as string).replace(/^content\.json:\n/, ""));
    assert.deepEqual(made.claims.map((x: { id: string }) => x.id), ["c1", "c2", "c3"]);
    assert.equal(made.language, "pl");
    assert.equal(JSON.stringify(logs).includes("Pompy"), false, "logs carry counts, never words");
  });

  test("a pause_turn is resumed with the same messages; extra files are not kept but still deleted", async () => {
    const api = new FakeStudioApi();
    api.researches.push(researchMessage("pause_turn"), researchMessage());
    api.makes.push({ files: { ...goodFiles(content()), "notes.txt": Buffer.from("x") } });
    const out = await runStudio(api, job, control().c);
    assert.equal(out.kind, "made");
    assert.equal(api.researchInputs[1]!.length, 2, "the paused assistant turn goes back");
    if (out.kind === "made") assert.equal(out.files.some((f) => (f.name as string) === "notes.txt"), false);
    assert.equal(api.deleted.size, 5);
  });

  test("a failed check goes back to make once, with the failures listed; a second failure is needs_look, never ready", async () => {
    const api = new FakeStudioApi();
    const bad = { ...goodFiles(content()), "infographic.png": png(800, 800) };
    api.makes.push({ files: bad }, { files: bad });
    const out = await runStudio(api, job, control().c);
    assert.equal(out.kind, "made");
    if (out.kind !== "made") return;
    assert.equal(out.state, "needs_look");
    assert.deepEqual(api.calls.filter((x) => x === "make"), ["make", "make"]);
    const retry = api.makeInputs[1]!.at(-1)!.content as string;
    assert.ok(retry.includes("png_phone_size"), retry);
    assert.ok(out.result.checks.some((x) => x.name === "png_phone_size" && !x.passed));

    const fixed = new FakeStudioApi();
    fixed.makes.push({ files: bad });
    const ok = await runStudio(fixed, job, control().c);
    assert.equal(ok.kind === "made" && ok.state, "ready", "the second make's files replace the first's");
  });

  test("content that breaks the rules is sent back with its last attempt and the problems; three times is unreadable_result", async () => {
    const api = new FakeStudioApi();
    const broken = content();
    broken.infographic.facts = [];
    api.writes.push({ kind: "ok", value: broken, usage: {} });
    assert.equal((await runStudio(api, job, control().c)).kind, "made");
    assert.ok(JSON.parse(api.writeInputs[1]!).fixThese.some((p: string) => p.startsWith("facts: 0")));

    const twice = new FakeStudioApi();
    assert.deepEqual(JSON.parse(api.writeInputs[1]!).previousAttempt.infographic.facts, [], "the retry carries the attempt it fixes");
    twice.writes.push({ kind: "ok", value: broken, usage: {} }, { kind: "ok", value: broken, usage: {} }, { kind: "ok", value: broken, usage: {} });
    const out = await runStudio(twice, job, control().c);
    assert.equal(out.kind === "failed" && out.code, "unreadable_result");
    assert.equal(twice.calls.includes("make"), false, "nothing is rendered from content that failed");
  });

  test("too few claims from pages the run saw is too_little_found", async () => {
    const api = new FakeStudioApi();
    api.researches.push(researchMessage("end_turn", [URLS[0]!]));
    const out = await runStudio(api, job, control().c);
    assert.equal(out.kind === "failed" && out.code, "too_little_found");
  });

  test("a refusal, a provider error, the job's dollar limit, Cancel and the time limit each end it honestly", async () => {
    const refused = new FakeStudioApi();
    refused.plans.push({ kind: "refused", usage: {} });
    assert.equal(((o) => o.kind === "failed" && o.code)(await runStudio(refused, job, control().c)), "refused");

    const broken = new FakeStudioApi();
    broken.onCall = (s) => { if (s === "research") throw new Error("socket hang up"); };
    assert.equal(((o) => o.kind === "failed" && o.code)(await runStudio(broken, job, control().c)), "provider_error");

    const pricey = new FakeStudioApi();
    assert.equal(((o) => o.kind === "failed" && o.code)(await runStudio(pricey, job, control({ jobLimitUsd: 0.05 }).c)), "cost_limit");

    let cancelled = false;
    const cancelling = new FakeStudioApi();
    cancelling.onCall = (s) => { if (s === "write") cancelled = true; };
    const out = await runStudio(cancelling, job, control({ isCancelled: async () => cancelled }).c);
    assert.equal(out.kind, "cancelled");
    assert.equal(cancelling.calls.includes("make"), false);

    const late = new FakeStudioApi();
    assert.equal(((o) => o.kind === "failed" && o.code)(await runStudio(late, job, control({ deadline: new Date(Date.now() - 1) }).c)), "time_limit");
  });

  test("a file Anthropic won't confirm deleted comes back as pending, even when the job fails afterwards", async () => {
    const api = new FakeStudioApi();
    api.stubborn.add("file_1");
    const out = await runStudio(api, job, control().c);
    assert.deepEqual(out.pending, ["file_1"]);

    const failing = new FakeStudioApi();
    failing.stubborn.add("file_2");
    failing.makes.push({ files: goodFiles(content()), stop: "refusal" });
    const f = await runStudio(failing, job, control().c);
    assert.equal(f.kind === "failed" && f.code, "refused");
    assert.deepEqual(f.pending, ["file_2"]);
    assert.equal(failing.deleted.size, 3);
  });
});

// Test doubles for Studio (ADR-584): a fake Claude that answers each step, and the files a correct
// render would produce. Nothing here calls Anthropic.
import type { ResearchMessage, ResearchTurn } from "../src/errands/researcher.js";
import type { StepModels } from "../src/studio/models.js";
import type { MakeMessage, MakeTurn, SkillRef, StudioModelApi, Structured } from "../src/studio/model.js";
import type { ContentOutput, PackOutput, PlanOutput, RenderContent, StudioJob } from "../src/studio/schema.js";

export const job: StudioJob = {
  kind: "brief", topic: "Pompy ciepła w Polsce: ile kosztują?", length: "standard", style: "plain", language: "pl",
};

export const usage = (input = 1000, output = 500) => ({ input_tokens: input, output_tokens: output, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 });

export const plan: PlanOutput = {
  title: "Pompy ciepła w Polsce", subQuestions: ["Ile kosztuje montaż?", "Jakie są dopłaty?", "Ile się oszczędza?"],
  outline: ["Koszt", "Dopłaty", "Oszczędności"], audience: "właściciele domów",
};

export const URLS = ["https://www.gov.pl/web/klimat/pompy", "https://www.ure.gov.pl/raport", "https://example.org/oszczednosci"];

/** One research message that searched and fetched the three URLs and wrote notes. */
export function researchMessage(stop: string = "end_turn", urls = URLS): ResearchMessage {
  return {
    stop_reason: stop,
    usage: { ...usage(20000, 4000), server_tool_use: { web_search_requests: 3, web_fetch_requests: 2 } },
    content: [
      { type: "server_tool_use", id: "s1", name: "web_search", input: { query: "pompy ciepła koszt" } },
      { type: "web_search_tool_result", tool_use_id: "s1", content: urls.map((url, i) => ({ type: "web_search_result", url, title: `Źródło ${i + 1}` })) },
      { type: "server_tool_use", id: "f1", name: "web_fetch", input: { url: urls[0] } },
      { type: "web_fetch_tool_result", tool_use_id: "f1", content: { type: "web_fetch_result", url: urls[0], content: { title: "Pompy ciepła — gov.pl" } } },
      { type: "text", text: `Notatki: montaż kosztuje 40–60 tys. zł (${urls[0]}).` },
    ],
  };
}

export const packOutput = (urls = URLS): PackOutput => ({
  claims: [
    { text: "Montaż kosztuje 40–60 tys. zł.", quote: "koszt montażu 40–60 tys. zł", url: urls[0]!, sourceTitle: "gov.pl" },
    { text: "Dopłata do 35 tys. zł.", quote: "dofinansowanie do 35 000 zł", url: urls[1]!, sourceTitle: "URE" },
    { text: "Oszczędność 30–50% rocznie.", quote: "oszczędności 30-50% kosztów ogrzewania", url: urls[2]!, sourceTitle: "Przykład" },
    { text: "Ta strona nie była czytana.", quote: "cytat", url: "https://never-seen.example/x", sourceTitle: "?" },
  ],
});

export function content(over: Partial<ContentOutput> = {}): ContentOutput {
  return {
    title: "Pompy ciepła w Polsce",
    answer: "Pompa ciepła kosztuje 40–60 tys. zł, a dopłaty pokrywają do 35 tys. zł.",
    sections: [
      { heading: "Ile kosztuje montaż?", points: [{ text: "Zwykle 40–60 tys. zł.", claims: ["c1"] }] },
      { heading: "Jakie są dopłaty?", points: [{ text: "Do 35 tys. zł.", claims: ["c2"] }] },
      { heading: "Ile się oszczędza?", points: [{ text: "30–50% rocznie.", claims: ["c3"] }] },
    ],
    disagreements: [],
    confidence: "medium",
    gaps: ["Brak danych dla bloków."],
    infographic: {
      headline: { text: "Do 35 tys. zł dopłaty", claims: ["c2"] },
      facts: [
        { text: "Montaż: 40–60 tys. zł", claims: ["c1"] },
        { text: "Dopłata: do 35 tys. zł", claims: ["c2"] },
        { text: "Oszczędność: 30–50% rocznie", claims: ["c3"] },
      ],
      numbered: false,
      chart: { kind: "bar", title: "Koszt i dopłata", unit: "tys. zł", data: [{ label: "Montaż", value: 50 }, { label: "Dopłata", value: 35 }], claims: ["c1", "c2"] },
      sourceLine: "Źródła: gov.pl, URE",
      altText: "Infografika: pompa ciepła kosztuje 40–60 tys. zł, dopłata do 35 tys. zł.",
    },
    ...over,
  };
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/** An SVG that passes every check for `c` (what render_infographic.py is meant to produce). */
export function goodSvg(c: Pick<RenderContent, "infographic">, extra = ""): string {
  const g = c.infographic;
  const texts = [g.headline.text, ...g.facts.map((f) => f.text), g.sourceLine];
  return `<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1080" height="1350" viewBox="0 0 1080 1350">
<title>Infografika</title><desc>${esc(g.altText)}</desc>
<rect width="1080" height="1350" style="fill: #fff7e9"/>
<g id="text">${texts.map((t, i) => `<text x="60" y="${120 + i * 60}" style="font-size: 28px; font-family: 'DejaVu Sans'; fill: #171715">${esc(t)}</text>`).join("")}</g>
<rect x="60" y="900" width="400" height="40" style="fill: #ff6a00"/>${extra}
</svg>`;
}

export function png(width: number, height: number): Buffer {
  const b = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(b, 0);
  b.writeUInt32BE(13, 8);
  b.write("IHDR", 12, "latin1");
  b.writeUInt32BE(width, 16);
  b.writeUInt32BE(height, 20);
  return b;
}

export const pdf = (extra = "") => Buffer.from(`%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n3 0 obj << /Type /Page /Parent 2 0 R ${extra}>> endobj\n4 0 obj << /Length 5 >> stream\n/JS x\nendstream endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n`, "latin1");

export type MakeFiles = Record<string, Buffer>;
export const goodFiles = (c: Pick<RenderContent, "infographic">): MakeFiles => ({
  "brief.pdf": pdf(), "infographic.svg": Buffer.from(goodSvg(c)), "infographic.png": png(1080, 1350), "infographic-a4.png": png(1240, 1754),
});

/** A scripted Claude. Each step's queue is used first; otherwise the happy path. */
export class FakeStudioApi implements StudioModelApi {
  readonly model = "claude-opus-5-5";
  models: StepModels = { plan: "claude-opus-5-5", research: "claude-opus-5-5", pack: "claude-opus-5-5", write: "claude-opus-5-5", make: "claude-opus-5-5" };
  readonly skills: SkillRef[] = [{ id: "skill_brand", version: "1" }, { id: "skill_docs", version: "1" }, { id: "skill_info", version: "1" }];
  plans: Structured<PlanOutput>[] = [];
  researches: ResearchMessage[] = [];
  packs: Structured<PackOutput>[] = [];
  writes: Structured<ContentOutput>[] = [];
  /** Each make request saves these files (name → bytes) and ends its turn. */
  makes: { files: MakeFiles; stop?: string }[] = [];
  calls: string[] = [];
  researchInputs: ResearchTurn[][] = [];
  writeInputs: string[] = [];
  makeInputs: MakeTurn[][] = [];
  stored = new Map<string, { name: string; bytes: Buffer }>();
  deleted = new Set<string>();
  /** File ids whose delete never takes. */
  stubborn = new Set<string>();
  private nextId = 1;
  onCall?: (step: string) => Promise<void> | void;

  private async step(name: string) {
    this.calls.push(name);
    await this.onCall?.(name);
  }
  async plan(): Promise<Structured<PlanOutput>> {
    await this.step("plan");
    return this.plans.shift() ?? { kind: "ok", value: plan, usage: usage() };
  }
  async research(messages: ResearchTurn[]): Promise<ResearchMessage> {
    await this.step("research");
    this.researchInputs.push(structuredClone(messages));
    return this.researches.shift() ?? researchMessage();
  }
  async pack(): Promise<Structured<PackOutput>> {
    await this.step("pack");
    return this.packs.shift() ?? { kind: "ok", value: packOutput(), usage: usage() };
  }
  async write(input: string): Promise<Structured<ContentOutput>> {
    await this.step("write");
    this.writeInputs.push(input);
    return this.writes.shift() ?? { kind: "ok", value: content(), usage: usage() };
  }
  async make(messages: MakeTurn[], containerId: string | undefined): Promise<MakeMessage> {
    await this.step("make");
    this.makeInputs.push(structuredClone(messages));
    const next = this.makes.shift() ?? { files: goodFiles(content()) };
    const results = Object.entries(next.files).map(([name, bytes]) => {
      const id = `file_${this.nextId++}`;
      this.stored.set(id, { name, bytes });
      return { file_id: id };
    });
    return {
      stop_reason: next.stop ?? "end_turn", usage: usage(5000, 2000), containerId: containerId ?? "container_1",
      content: [
        { type: "server_tool_use", id: "x1", name: "bash_code_execution", input: { command: "python3 render.py" } },
        { type: "bash_code_execution_tool_result", tool_use_id: "x1", content: { type: "bash_code_execution_result", stdout: "", stderr: "", return_code: 0, content: results } },
        { type: "text", text: "Zapisano pliki." },
      ],
    };
  }
  async fileName(id: string) { return this.stored.get(id)?.name ?? "unknown"; }
  async download(id: string) { return this.stored.get(id)!.bytes; }
  async deleteFile(id: string) { if (!this.stubborn.has(id)) this.deleted.add(id); }
  async fileGone(id: string) { return this.deleted.has(id); }
}

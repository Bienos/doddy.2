// Studio's check step (ADR-584, STUDIO.md "The files"): code, not the model, decides whether the
// files Claude rendered are what Doddy promised. Each check is named so the item can show it and a
// failed one can go back to the make step in plain words.
import { createHash } from "node:crypto";
import { XMLParser } from "fast-xml-parser";
import { FILE_NAMES, FILE_SPECS, MAX_FILE_BYTES, type Check, type FileName, type RenderContent } from "./schema.js";

export const BRAND = {
  paper: "#FFF7E9", ink: "#171715", orange: "#FF6A00", accentText: "#A64B00", secondary: "#5E584F",
} as const;
/** Colours text may use. Orange is decoration only (Brand V2.2; `accentText` is the text colour). */
export const TEXT_COLOURS: readonly string[] = [BRAND.ink, BRAND.accentText, BRAND.secondary];
export const MIN_TEXT_PX = 22;
export const MIN_CONTRAST = 4.5;
export const PHONE_PNG = { width: 1080, height: 1350 } as const;
export const PRINT_PNG = { width: 1240, height: 1754 } as const;

export interface MadeFile { name: FileName; bytes: Buffer }

const ok = (name: string): Check => ({ name, passed: true, detail: "" });
const bad = (name: string, detail: string): Check => ({ name, passed: false, detail });

export const sha256 = (b: Buffer) => createHash("sha256").update(b).digest();

// ---------- colour ----------

function rgb(hex: string): [number, number, number] | undefined {
  const m = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return undefined;
  const h = m[1]!.length === 3 ? [...m[1]!].map((c) => c + c).join("") : m[1]!;
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)) as [number, number, number];
}

/** WCAG 2 contrast ratio between two #rrggbb colours. */
export function contrast(a: string, b: string): number {
  const lum = (hex: string) => {
    const [r, g, bl] = rgb(hex)!.map((v) => {
      const c = v / 255;
      return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    }) as [number, number, number];
    return 0.2126 * r + 0.7152 * g + 0.0722 * bl;
  };
  const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p) as [number, number];
  return (x + 0.05) / (y + 0.05);
}

/** `#rgb`/`#rrggbb` as upper-case `#RRGGBB`, or the input when it isn't one. */
export function normaliseColour(value: string): string {
  const c = rgb(value);
  return c ? "#" + c.map((v) => v.toString(16).padStart(2, "0")).join("").toUpperCase() : value.trim();
}

// ---------- SVG ----------

type Node = Record<string, unknown>;
const ATTRS = ":@";

function styleOf(attrs: Record<string, string> | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  for (const part of (attrs?.style ?? "").split(";")) {
    const i = part.indexOf(":");
    if (i > 0) out[part.slice(0, i).trim().toLowerCase()] = part.slice(i + 1).trim();
  }
  return out;
}

interface TextRun { text: string; fill: string; fontSize: number }
interface SvgScan {
  root?: string;
  viewBox?: string;
  texts: TextRun[];
  forbidden: string[];
  title: string;
  desc: string;
}

/** Walks the SVG in document order: every text run with the fill and size it inherits, and anything not allowed. */
export function scanSvg(svg: string): SvgScan | undefined {
  let tree: Node[];
  try {
    tree = new XMLParser({
      preserveOrder: true, ignoreAttributes: false, attributeNamePrefix: "", parseTagValue: false,
      parseAttributeValue: false, trimValues: false, processEntities: true,
    }).parse(svg) as Node[];
  } catch {
    return undefined;
  }
  const scan: SvgScan = { texts: [], forbidden: [], title: "", desc: "" };
  type Inherited = { fill?: string; fontSize?: number };
  const size = (v: string | undefined) => {
    if (!v) return undefined;
    const m = /^([0-9.]+)(px)?$/.exec(v.trim());
    return m ? Number(m[1]) : Number.NaN;
  };
  const walk = (nodes: Node[], inherited: Inherited, inText: boolean, owner: string) => {
    for (const node of nodes) {
      const tag = Object.keys(node).find((k) => k !== ATTRS);
      if (!tag) continue;
      if (tag === "#text") {
        const value = String(node["#text"] ?? "");
        if (owner === "title") scan.title += value;
        else if (owner === "desc") scan.desc += value;
        else if (inText && value.trim()) {
          scan.texts.push({ text: value, fill: normaliseColour(inherited.fill ?? "#000000"), fontSize: inherited.fontSize ?? 16 });
        }
        continue;
      }
      if (tag === "?xml" || tag === "!DOCTYPE" || tag === "#comment") continue;
      const attrs = (node[ATTRS] ?? {}) as Record<string, string>;
      const local = tag.toLowerCase();
      if (["script", "image", "foreignobject", "iframe", "object", "embed", "audio", "video"].includes(local)) scan.forbidden.push(`<${tag}>`);
      for (const [k, v] of Object.entries(attrs)) {
        const key = k.toLowerCase();
        if (key.startsWith("on")) scan.forbidden.push(`${key} handler`);
        if ((key === "href" || key === "xlink:href") && !String(v).startsWith("#")) scan.forbidden.push(`external ${key}`);
        if (/url\(\s*['"]?(?!#)/i.test(String(v))) scan.forbidden.push(`external url() in ${key}`);
      }
      if (local === "svg" && scan.root === undefined) {
        scan.root = tag;
        scan.viewBox = attrs.viewBox;
      }
      const style = styleOf(attrs);
      const next: Inherited = {
        fill: style.fill ?? attrs.fill ?? inherited.fill,
        fontSize: size(style["font-size"] ?? attrs["font-size"]) ?? inherited.fontSize,
      };
      const children = node[tag];
      if (Array.isArray(children)) {
        walk(children as Node[], next, inText || local === "text", local === "title" || local === "desc" ? local : owner);
      }
    }
  };
  walk(tree, {}, false, "");
  return scan;
}

const collapse = (s: string) => s.replace(/\s+/g, " ").trim();

export function checkSvg(svg: Buffer, content: RenderContent): Check[] {
  const scan = scanSvg(svg.toString("utf8"));
  if (!scan || scan.root === undefined) return [bad("svg_parses", "infographic.svg isn't an SVG document")];
  const checks: Check[] = [ok("svg_parses")];
  checks.push(scan.forbidden.length ? bad("svg_safe", [...new Set(scan.forbidden)].join(", ")) : ok("svg_safe"));
  const vb = (scan.viewBox ?? "").trim().split(/[\s,]+/).map(Number);
  checks.push(vb.length === 4 && vb[2] === PHONE_PNG.width && vb[3] === PHONE_PNG.height
    ? ok("svg_size") : bad("svg_size", `viewBox "${scan.viewBox ?? ""}"; needs 0 0 ${PHONE_PNG.width} ${PHONE_PNG.height}`));
  const all = collapse(scan.texts.map((t) => t.text).join(" "));
  const g = content.infographic;
  const missing = [g.headline.text, ...g.facts.map((f) => f.text)].filter((t) => !all.includes(collapse(t)));
  checks.push(missing.length ? bad("svg_text_present", `missing: ${missing.map((m) => `"${m}"`).join(", ")}`) : ok("svg_text_present"));
  const offPalette = [...new Set(scan.texts.map((t) => t.fill).filter((f) => !TEXT_COLOURS.includes(f)))];
  checks.push(offPalette.length ? bad("svg_text_colours", `text in ${offPalette.join(", ")}; text may only be ${TEXT_COLOURS.join(", ")} (orange is never text)`) : ok("svg_text_colours"));
  const small = scan.texts.filter((t) => !(t.fontSize >= MIN_TEXT_PX));
  checks.push(small.length ? bad("svg_min_text_size", `${small.length} text runs under ${MIN_TEXT_PX} px (smallest ${Math.min(...small.map((t) => t.fontSize))})`) : ok("svg_min_text_size"));
  const low = [...new Set(scan.texts.map((t) => t.fill))].filter((f) => rgb(f) && contrast(f, BRAND.paper) < MIN_CONTRAST);
  checks.push(low.length ? bad("svg_contrast", `${low.join(", ")} under ${MIN_CONTRAST}:1 on paper`) : ok("svg_contrast"));
  const alt = collapse(g.altText);
  checks.push(collapse(scan.title) && collapse(scan.desc).includes(alt)
    ? ok("svg_alt_text") : bad("svg_alt_text", "the SVG needs a <title> and the alt text in <desc>"));
  return checks;
}

// ---------- PNG and PDF ----------

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

export function pngSize(b: Buffer): { width: number; height: number } | undefined {
  if (b.length < 24 || !b.subarray(0, 8).equals(PNG_SIGNATURE) || b.toString("latin1", 12, 16) !== "IHDR") return undefined;
  return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
}

function checkPng(name: string, b: Buffer, want: { width: number; height: number }): Check {
  const s = pngSize(b);
  if (!s) return bad(name, "not a PNG");
  return s.width === want.width && s.height === want.height ? ok(name) : bad(name, `${s.width}×${s.height}; needs ${want.width}×${want.height}`);
}

export function checkPdf(b: Buffer): Check[] {
  if (b.toString("latin1", 0, 5) !== "%PDF-") return [bad("pdf_valid", "brief.pdf doesn't start with %PDF-")];
  // Dictionaries only: compressed stream bytes could spell "/JS" by chance.
  const raw = b.toString("latin1").replace(/stream\r?\n[\s\S]*?endstream/g, "");
  const pages = (raw.match(/\/Type\s*\/Page(?![a-zA-Z])/g) ?? []).length;
  const active = ["/JavaScript", "/JS", "/Launch", "/EmbeddedFile"].filter((k) => new RegExp(`${k.replace("/", "\\/")}(?![a-zA-Z])`).test(raw));
  return [
    pages > 0 ? ok("pdf_valid") : bad("pdf_valid", "no pages found"),
    active.length ? bad("pdf_no_active_content", `has ${active.join(", ")}`) : ok("pdf_no_active_content"),
  ];
}

/** Every check on the files a make step returned. All passed means the item can be ready. */
export function checkFiles(files: MadeFile[], content: RenderContent): Check[] {
  const by = new Map(files.map((f) => [f.name, f.bytes]));
  const missing = FILE_NAMES.filter((n) => !by.has(n));
  const checks: Check[] = [missing.length ? bad("files_present", `missing ${missing.join(", ")}`) : ok("files_present")];
  const big = files.filter((f) => f.bytes.length === 0 || f.bytes.length > MAX_FILE_BYTES);
  checks.push(big.length ? bad("file_sizes", big.map((f) => `${f.name} ${f.bytes.length} bytes`).join(", ")) : ok("file_sizes"));
  const pdf = by.get("brief.pdf");
  if (pdf) checks.push(...checkPdf(pdf));
  const svg = by.get("infographic.svg");
  if (svg) checks.push(...checkSvg(svg, content));
  const png = by.get("infographic.png");
  if (png) checks.push(checkPng("png_phone_size", png, PHONE_PNG));
  const print = by.get("infographic-a4.png");
  if (print) checks.push(checkPng("png_print_size", print, PRINT_PNG));
  return checks;
}

export const failed = (checks: Check[]) => checks.filter((c) => !c.passed);
export const isKeptFile = (name: string): name is FileName => Object.hasOwn(FILE_SPECS, name);

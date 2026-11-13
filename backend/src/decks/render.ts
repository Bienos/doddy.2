import { WIDTH_RANGES } from "./fontWidths.js";
import type { DeckImage, ResearchPack, ResearchSource } from "./research.js";
import type { Deck, Slide } from "./spec.js";
import { zip, type ZipEntry } from "./zip.js";

/**
 * Lays out a checked deck as a PowerPoint file (decision 2026-11-10-better-presentations). Plain
 * Office Open XML, written here like the phone's own `PresentationFile.swift`, so the same deck gives
 * the same bytes and nothing needs a renderer, a container or a font file.
 *
 *  - Brand V2.2 (`design/brand-v2.2/`, ADR-556): ink #171715 on paper #FFF7E9, night #16171C for the
 *    title, quote and summary slides, orange #FF6A00 for marks and bars only (never body text on
 *    paper), #A64B00 where orange-ish text is needed, secondary #655F56.
 *  - Arial throughout: it ships with PowerPoint, Keynote (iPhone, iPad, Mac) and Google Slides, so
 *    the deck looks the same wherever it opens. No font is embedded.
 *  - 16:9. Every slide has speaker notes. Charts are drawn as shapes, so every viewer (Quick Look
 *    included) shows them the same; their numbers were checked against the sources (`spec.ts`).
 *  - Pictures only from the research pack (Wikimedia Commons, free licence), cropped to fill their
 *    box, with author and licence under them and on the sources slide.
 *  - Links only on the sources slide, and only to addresses research found.
 *  - One grid: every slide's body starts at BODY_TOP and ends above the source line, at the same
 *    left and right margins. Boxes side by side (cards, columns) share one text size. Text is
 *    measured with Arial's own widths (`fontWidths.ts`) so it fits without a viewer shrinking it.
 */

export const COLORS = {
  ink: "171715",
  paper: "FFF7E9",
  orange: "FF6A00",
  night: "16171C",
  accentText: "A64B00",
  secondary: "655F56",
  card: "F5EAD8",
  line: "C5BCAD",
  nightText: "D9D1C3",
} as const;
export const FONT = "Arial";

const W = 13.333;
const H = 7.5;
/** The body of every content slide: under the title, above the source line, between the margins. */
const LEFT = 0.6;
const RIGHT = 12.7;
const BODY_TOP = 1.95;
const BODY_BOTTOM = 6.4;
const INCH = 914_400;
const emu = (inches: number) => Math.round(inches * INCH);

export interface RenderedDeck {
  bytes: Buffer;
  /** Slides in the file: title, agenda, content, summary, sources. */
  slideCount: number;
  layouts: string[];
}

interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface Rel {
  id: string;
  type: string;
  target: string;
  external: boolean;
}

const OFFICE_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
const PML = "application/vnd.openxmlformats-officedocument.presentationml";

// ------------------------------------------------------------------ the deck

export function renderDeck(deck: Deck, pack: ResearchPack, made: Date): RenderedDeck {
  const ctx = new DeckContext(deck, pack);
  const content = deck.slides;
  const slides: BuiltSlide[] = [];
  const total = content.length + 3 + (ctx.cited.length || ctx.usedImages().length ? 1 : 0);

  slides.push(titleSlide(ctx, made));
  slides.push(agendaSlide(ctx, 2, total));
  content.forEach((s, i) => slides.push(contentSlide(ctx, s, i + 3, total)));
  slides.push(summarySlide(ctx, content.length + 3, total));
  if (total > content.length + 3) slides.push(sourcesSlide(ctx, total, total));

  const entries: ZipEntry[] = [];
  const text = (path: string, xml: string) => entries.push({ path, data: Buffer.from(xml, "utf8") });
  const count = slides.length;
  text("[Content_Types].xml", contentTypes(count));
  text("_rels/.rels", PACKAGE_RELS);
  text("docProps/core.xml", core(deck.title, made));
  text("docProps/app.xml", app(count));
  text("ppt/presentation.xml", presentation(count));
  text("ppt/_rels/presentation.xml.rels", presentationRels(count));
  text("ppt/presProps.xml", PRES_PROPS);
  text("ppt/viewProps.xml", VIEW_PROPS);
  text("ppt/tableStyles.xml", TABLE_STYLES);
  text("ppt/theme/theme1.xml", THEME);
  text("ppt/theme/theme2.xml", THEME);
  text("ppt/slideMasters/slideMaster1.xml", SLIDE_MASTER);
  text("ppt/slideMasters/_rels/slideMaster1.xml.rels", relationships([rel("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"), rel("rId2", "theme", "../theme/theme1.xml")]));
  text("ppt/slideLayouts/slideLayout1.xml", SLIDE_LAYOUT);
  text("ppt/slideLayouts/_rels/slideLayout1.xml.rels", relationships([rel("rId1", "slideMaster", "../slideMasters/slideMaster1.xml")]));
  text("ppt/notesMasters/notesMaster1.xml", NOTES_MASTER);
  text("ppt/notesMasters/_rels/notesMaster1.xml.rels", relationships([rel("rId1", "theme", "../theme/theme2.xml")]));
  slides.forEach((s, i) => {
    const n = i + 1;
    text(`ppt/slides/slide${n}.xml`, s.xml);
    text(`ppt/slides/_rels/slide${n}.xml.rels`, relationships(s.rels.map((r) => (r.id === NOTES_REL ? { ...r, target: `../notesSlides/notesSlide${n}.xml` } : r))));
    text(`ppt/notesSlides/notesSlide${n}.xml`, notesSlide(s.notes, deck.language));
    text(`ppt/notesSlides/_rels/notesSlide${n}.xml.rels`, relationships([rel("rId1", "notesMaster", "../notesMasters/notesMaster1.xml"), rel("rId2", "slide", `../slides/slide${n}.xml`)]));
  });
  for (const media of ctx.media.values()) entries.push({ path: `ppt/media/${media.name}`, data: media.image.bytes, store: true });
  return { bytes: zip(entries), slideCount: count, layouts: slides.map((s) => s.kind) };
}

/** What every slide needs to know about the deck: labels, numbering of cited sources, pictures. */
class DeckContext {
  /** Sources some slide cites, in the order the sources slide lists them (m1 first, then s1…). */
  readonly cited: ResearchSource[];
  readonly media = new Map<string, { name: string; image: DeckImage }>();
  readonly cover: DeckImage | null;
  readonly lang: string;
  private readonly imageSlides: Map<string, number>;

  constructor(readonly deck: Deck, readonly pack: ResearchPack) {
    const ids = new Set(deck.slides.flatMap((s) => s.sources));
    this.cited = pack.sources.filter((s) => ids.has(s.id));
    this.lang = deck.language;
    this.imageSlides = new Map();
    deck.slides.forEach((s, i) => {
      if (s.layout === "image") this.imageSlides.set(s.image, i + 3);
    });
    this.cover = pack.images.find((img) => !this.imageSlides.has(img.id)) ?? null;
  }

  image(id: string): DeckImage | null {
    return this.pack.images.find((i) => i.id === id) ?? null;
  }

  /** The picture's part name, added to the package once. */
  mediaName(image: DeckImage): string {
    let entry = this.media.get(image.id);
    if (!entry) {
      entry = { name: `image${this.media.size + 1}.${image.mime === "image/png" ? "png" : "jpeg"}`, image };
      this.media.set(image.id, entry);
    }
    return entry.name;
  }

  /** Pictures in the deck and the slide each is on (1 is the title slide). */
  usedImages(): { image: DeckImage; slide: number }[] {
    const out: { image: DeckImage; slide: number }[] = [];
    if (this.cover) out.push({ image: this.cover, slide: 1 });
    for (const [id, slide] of this.imageSlides) {
      const image = this.image(id);
      if (image) out.push({ image, slide });
    }
    return out.sort((a, b) => a.slide - b.slide);
  }

  sourceNumber(id: string): number {
    return this.cited.findIndex((s) => s.id === id) + 1;
  }

  sourceName(source: ResearchSource): string {
    if (source.kind === "material") return this.deck.labels.material;
    if (source.kind === "web") return source.site ?? source.title;
    return source.title;
  }

  /** "Źródło: [1] Iława — Wikipedia; [2] visit.ilawa.pl" for a slide's foot. */
  sourceLine(slide: Slide): string {
    const parts = slide.sources
      .map((id) => this.cited.find((s) => s.id === id))
      .filter((s): s is ResearchSource => !!s)
      .map((s) => `[${this.sourceNumber(s.id)}] ${this.sourceName(s)}`);
    if (!parts.length) return "";
    const line = `${this.deck.labels.source}: ${[...new Set(parts)].join("; ")}`;
    return line.length > 150 ? `${line.slice(0, 149).trimEnd()}…` : line;
  }

  number(value: number): string {
    try {
      return new Intl.NumberFormat(this.lang, { maximumFractionDigits: 3 }).format(value);
    } catch {
      return String(value);
    }
  }
}

interface BuiltSlide {
  kind: string;
  xml: string;
  rels: Rel[];
  notes: string;
}

/** The slide's relationship to its notes; its target is set once the slide's number is known. */
const NOTES_REL = "rId2";

/** One slide's shapes, ids and relationships while it is built. rId1 is the layout, rId2 the notes. */
class SlideBuilder {
  private readonly shapes: string[] = [];
  private nextId = 2;
  private readonly rels: Rel[] = [rel("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"), rel(NOTES_REL, "notesSlide", "")];

  constructor(
    private readonly kind: string,
    private readonly background: string,
  ) {}

  id(): number {
    return this.nextId++;
  }

  add(xml: string): void {
    this.shapes.push(xml);
  }

  link(url: string): string {
    const existing = this.rels.find((r) => r.external && r.target === url);
    if (existing) return existing.id;
    const id = `rId${this.rels.length + 1}`;
    this.rels.push({ id, type: `${OFFICE_REL}/hyperlink`, target: url, external: true });
    return id;
  }

  picture(name: string): string {
    const target = `../media/${name}`;
    const existing = this.rels.find((r) => r.target === target);
    if (existing) return existing.id;
    const id = `rId${this.rels.length + 1}`;
    this.rels.push(rel(id, "image", target));
    return id;
  }

  text(box: Box, paragraphs: string[], o: { anchor?: "t" | "ctr" | "b"; name?: string } = {}): void {
    if (!paragraphs.length) return;
    const id = this.id();
    this.add(
      `<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="${o.name ?? `Text ${id}`}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr>${xfrm(box)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>` +
        txBody(paragraphs, o.anchor ?? "t", 0) +
        "</p:sp>",
    );
  }

  shape(geom: "rect" | "roundRect" | "ellipse", box: Box, fill: string, o: { alpha?: number; paragraphs?: string[]; descr?: string } = {}): void {
    const id = this.id();
    const adj = geom === "roundRect" ? '<a:avLst><a:gd name="adj" fmla="val 7000"/></a:avLst>' : "<a:avLst/>";
    const color = o.alpha === undefined ? `<a:srgbClr val="${fill}"/>` : `<a:srgbClr val="${fill}"><a:alpha val="${Math.round(o.alpha * 1000)}"/></a:srgbClr>`;
    this.add(
      `<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="Shape ${id}"${o.descr ? ` descr="${escape(o.descr)}"` : ""}/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>${xfrm(box)}<a:prstGeom prst="${geom}">${adj}</a:prstGeom><a:solidFill>${color}</a:solidFill><a:ln><a:noFill/></a:ln></p:spPr>` +
        (o.paragraphs ? txBody(o.paragraphs, "ctr", 0) : "") +
        "</p:sp>",
    );
  }

  /** A picture cropped to fill the box (centred). */
  image(image: DeckImage, name: string, box: Box): void {
    const id = this.id();
    const rid = this.picture(name);
    const imageAspect = image.width / image.height;
    const boxAspect = box.w / box.h;
    let l = 0, r = 0, t = 0, b = 0;
    if (imageAspect > boxAspect) {
      l = r = Math.round(((1 - boxAspect / imageAspect) / 2) * 100_000);
    } else {
      // Taller than the box: keep a little more of the top, where a subject's head or a skyline usually is.
      const cut = (1 - imageAspect / boxAspect) * 100_000;
      t = Math.round(cut * 0.35);
      b = Math.round(cut * 0.65);
    }
    this.add(
      `<p:pic><p:nvPicPr><p:cNvPr id="${id}" name="Picture ${id}" descr="${escape(image.title)}"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>` +
        `<p:blipFill><a:blip r:embed="${rid}"/><a:srcRect l="${l}" t="${t}" r="${r}" b="${b}"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>` +
        `<p:spPr>${xfrm(box)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>`,
    );
  }

  /** A table whose rows are as tall as their text needs (measured by the caller), so it ends where it should. */
  table(box: { x: number; y: number }, widths: number[], rows: { cells: string[]; fill: string; height: number }[]): void {
    const id = this.id();
    const grid = widths.map((w) => `<a:gridCol w="${emu(w)}"/>`).join("");
    const none = "<a:lnL><a:noFill/></a:lnL><a:lnR><a:noFill/></a:lnR><a:lnT><a:noFill/></a:lnT><a:lnB><a:noFill/></a:lnB>";
    const total = rows.reduce((sum, row) => sum + emu(row.height), 0);
    const body = rows
      .map(
        (row) =>
          `<a:tr h="${emu(row.height)}">` +
          row.cells
            .map(
              (cell) =>
                `<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>${cell}</a:txBody><a:tcPr marL="${emu(0.15)}" marR="${emu(0.15)}" marT="${emu(0.06)}" marB="${emu(0.06)}" anchor="ctr">${none}<a:solidFill><a:srgbClr val="${row.fill}"/></a:solidFill></a:tcPr></a:tc>`,
            )
            .join("") +
          "</a:tr>",
      )
      .join("");
    this.add(
      `<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="${id}" name="Table ${id}"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>` +
        `<p:xfrm><a:off x="${emu(box.x)}" y="${emu(box.y)}"/><a:ext cx="${widths.reduce((sum, w) => sum + emu(w), 0)}" cy="${total}"/></p:xfrm>` +
        `<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblPr firstRow="1" bandRow="1"/><a:tblGrid>${grid}</a:tblGrid>${body}</a:tbl></a:graphicData></a:graphic></p:graphicFrame>`,
    );
  }

  build(notes: string): BuiltSlide {
    const xml =
      XML_HEADER +
      `<p:sld ${NAMESPACES}><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="${this.background}"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree>${GROUP_HEADER}${this.shapes.join("")}</p:spTree></p:cSld>` +
      "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>";
    return { kind: this.kind, xml, rels: this.rels, notes };
  }
}

// ------------------------------------------------------------------ slides

function titleSlide(ctx: DeckContext, made: Date): BuiltSlide {
  const s = new SlideBuilder("title", COLORS.night);
  const { deck } = ctx;
  const cover = ctx.cover;
  const textWidth = cover ? 6.3 : 9.4;
  if (cover) {
    const panel = { x: 7.45, y: 0, w: W - 7.45, h: H };
    s.image(cover, ctx.mediaName(cover), panel);
    s.shape("rect", { x: panel.x, y: H - 0.42, w: panel.w, h: 0.42 }, COLORS.night, { alpha: 72 });
    s.text({ x: panel.x + 0.15, y: H - 0.38, w: panel.w - 0.3, h: 0.34 }, [para([run(credit(cover), { size: 9, color: COLORS.nightText, lang: ctx.lang })])], { anchor: "ctr" });
  } else {
    // No picture: a quiet mark of Doddy's shapes instead (a slightly lighter night disc and an orange dot), never a made-up image.
    s.shape("ellipse", { x: 8.9, y: -1.3, w: 6.2, h: 6.2 }, "22232A");
    s.shape("ellipse", { x: 11.35, y: 4.55, w: 0.95, h: 0.95 }, COLORS.orange);
  }
  // The title sits on the orange rule, the subtitle under it: one line or three, they stay together.
  const titleBox = { x: 0.75, y: 0.9, w: textWidth, h: 3.75 };
  s.text(titleBox, [para([run(deck.title, { size: fitSize([deck.title], titleBox, [72, 64, 56, 48, 44, 40, 36, 32], true), bold: true, color: COLORS.paper, lang: ctx.lang })], { lineSpacing: 90 })], { name: "Title", anchor: "b" });
  s.shape("rect", { x: 0.75, y: 4.85, w: 1.0, h: 0.1 }, COLORS.orange);
  if (deck.subtitle) {
    const box = { x: 0.75, y: 5.15, w: textWidth, h: 1.2 };
    s.text(box, [para([run(deck.subtitle, { size: fitSize([deck.subtitle], box, [26, 24, 22, 20, 18]), color: COLORS.nightText, lang: ctx.lang })])], { name: "Subtitle" });
  }
  s.text({ x: 0.75, y: 6.7, w: 6, h: 0.4 }, [para([run(`Doddy · ${longDate(made, ctx.lang)}`, { size: 12, color: COLORS.nightText, lang: ctx.lang })])], { anchor: "ctr" });
  return s.build(deck.cover_notes || deck.subtitle || deck.title);
}

function agendaSlide(ctx: DeckContext, number: number, total: number): BuiltSlide {
  const s = new SlideBuilder("agenda", COLORS.paper);
  chrome(s, ctx, ctx.deck.labels.agenda, number, total, "");
  const items = ctx.deck.slides.map((slide) => slide.title);
  const columns = items.length > 5 ? 2 : 1;
  const perColumn = Math.ceil(items.length / columns);
  const columnWidth = columns === 2 ? 5.9 : 12.1;
  const rowHeight = Math.min(0.85, 4.4 / perColumn);
  const textBox = { w: columnWidth - 0.75, h: rowHeight };
  const size = fitEach(items.map((t) => [t]), textBox, [22, 20, 18, 16, 14]);
  items.forEach((title, i) => {
    const column = Math.floor(i / perColumn);
    const x = LEFT + column * 6.2;
    const y = BODY_TOP + (i % perColumn) * rowHeight;
    const d = Math.min(0.5, rowHeight - 0.15);
    s.shape("ellipse", { x, y: y + (rowHeight - d) / 2, w: d, h: d }, COLORS.orange, { paragraphs: [para([run(String(i + 1), { size: 15, bold: true, color: COLORS.ink, lang: ctx.lang })], { align: "ctr" })] });
    s.text({ x: x + 0.75, y, w: textBox.w, h: rowHeight }, [para([run(title, { size, color: COLORS.ink, lang: ctx.lang })])], { anchor: "ctr" });
  });
  return s.build(items.map((t, i) => `${i + 1}. ${t}`).join(" "));
}

function summarySlide(ctx: DeckContext, number: number, total: number): BuiltSlide {
  const s = new SlideBuilder("summary", COLORS.night);
  chrome(s, ctx, ctx.deck.labels.summary, number, total, "", true);
  const items = ctx.deck.takeaways;
  const rowHeight = Math.min(1.05, 4.45 / items.length);
  const box = { x: 1.45, y: 0, w: RIGHT - 1.45, h: rowHeight };
  const size = fitEach(items.map((t) => [t]), box, [24, 22, 20, 18, 16]);
  items.forEach((item, i) => {
    const y = BODY_TOP + i * rowHeight;
    const d = Math.min(0.55, rowHeight - 0.2);
    s.shape("ellipse", { x: LEFT, y: y + (rowHeight - d) / 2, w: d, h: d }, COLORS.orange, { paragraphs: [para([run(String(i + 1), { size: 16, bold: true, color: COLORS.ink, lang: ctx.lang })], { align: "ctr" })] });
    s.text({ ...box, y }, [para([run(item, { size, color: COLORS.paper, lang: ctx.lang })])], { anchor: "ctr" });
  });
  return s.build(ctx.deck.summary_notes || items.join(" "));
}

function sourcesSlide(ctx: DeckContext, number: number, total: number): BuiltSlide {
  const s = new SlideBuilder("sources", COLORS.paper);
  chrome(s, ctx, ctx.deck.labels.sources, number, total, "");
  // Each line: its words, and an address for the part that links (only addresses research found).
  type Part = { text: string; color: string; url?: string | null };
  const lines: Part[][] = [];
  ctx.cited.forEach((source, i) => {
    // The address in words too, so a printed or projected deck still says where to look.
    const address = source.url ? readableUrl(source.url) : null;
    lines.push([
      { text: `${i + 1}. `, color: COLORS.ink },
      { text: ctx.sourceName(source), color: source.url ? COLORS.accentText : COLORS.ink, url: source.url },
      ...(address ? [{ text: ` · ${address}`, color: COLORS.secondary }] : []),
    ]);
  });
  for (const { image } of ctx.usedImages()) {
    lines.push([
      { text: image.title, color: COLORS.accentText, url: image.pageUrl },
      { text: ` — ${image.author}, `, color: COLORS.ink },
      { text: image.license, color: image.licenseUrl ? COLORS.accentText : COLORS.ink, url: image.licenseUrl },
      { text: ", Wikimedia Commons", color: COLORS.ink },
    ]);
  }
  const box = { x: LEFT, y: BODY_TOP, w: RIGHT - LEFT, h: 4.9 };
  // A wider gap sets the picture credits apart from the numbered sources.
  const firstCredit = ctx.cited.length;
  const size = fitSize(lines.map((parts) => parts.map((p) => p.text).join("")), { ...box, h: box.h - 0.25 }, [18, 16, 14, 13, 12, 11, 10], false, 0.35);
  s.text(
    box,
    lines.map((parts, i) =>
      para(parts.map((p) => run(p.text, { size, color: p.color, lang: ctx.lang, ...(p.url ? { link: s.link(p.url) } : {}) })), {
        spaceBefore: i === 0 ? 0 : i === firstCredit ? size * 0.35 + 18 : size * 0.35,
      }),
    ),
  );
  const notes = [
    ...ctx.cited.map((source, i) => `${i + 1}. ${ctx.sourceName(source)}${source.url ? ` ${source.url}` : ""}`),
    ...ctx.usedImages().map(({ image }) => `${image.title}: ${credit(image)} ${image.pageUrl}`),
  ];
  return s.build(notes.join(" · "));
}

function contentSlide(ctx: DeckContext, slide: Slide, number: number, total: number): BuiltSlide {
  const dark = slide.layout === "quote";
  const s = new SlideBuilder(slide.layout, dark ? COLORS.night : COLORS.paper);
  chrome(s, ctx, slide.title, number, total, ctx.sourceLine(slide), dark);
  const t = (text: string, size: number, color: string, bold = false) => run(text, { size, color, bold, lang: ctx.lang });
  switch (slide.layout) {
    case "bullets": {
      if (slide.points.length <= 3 && slide.points.every((p) => p.length <= 90)) {
        const height = slide.points.every((p) => p.length <= 50) ? 3.4 : 4.2;
        const text = { w: cardWidth(slide.points.length) - 0.7, h: height - 1.65 };
        const size = fitEach(slide.points.map((p) => [p]), text, [28, 26, 24, 22, 20, 18, 16]);
        cards(s, slide.points.length, (box, i) => {
          s.text({ x: box.x + 0.35, y: box.y + 0.3, w: box.w - 0.7, h: 0.75 }, [para([t(String(i + 1).padStart(2, "0"), 30, COLORS.accentText, true)])]);
          s.shape("rect", { x: box.x + 0.35, y: box.y + 1.1, w: 0.5, h: 0.06 }, COLORS.orange);
          s.text({ x: box.x + 0.35, y: box.y + 1.35, ...text }, [para([t(slide.points[i]!, size, COLORS.ink)])]);
        }, height);
      } else {
        const box = { x: LEFT, y: BODY_TOP, w: RIGHT - LEFT, h: BODY_BOTTOM - BODY_TOP };
        bulletList(s, ctx, slide.points, box, bulletSize([slide.points], box, [28, 26, 24, 22, 20, 18, 16]), COLORS.ink);
      }
      break;
    }
    case "two_column": {
      const columns = [slide.left, slide.right];
      const height = BODY_BOTTOM - BODY_TOP;
      const heading = { w: cardWidth(2) - 0.8, h: 0.7 };
      const list = { w: cardWidth(2) - 0.8, h: height - 1.6 };
      const headingSize = fitEach(columns.map((c) => [c.heading]), heading, [26, 24, 22, 20], true);
      const listSize = bulletSize(columns.map((c) => c.points), list, [24, 22, 20, 18, 16, 14]);
      cards(s, 2, (card, i) => {
        const column = columns[i]!;
        s.text({ x: card.x + 0.4, y: card.y + 0.3, ...heading }, [para([t(column.heading, headingSize, COLORS.accentText, true)])], { anchor: "b" });
        s.shape("rect", { x: card.x + 0.4, y: card.y + 1.1, w: 0.5, h: 0.06 }, COLORS.orange);
        bulletList(s, ctx, column.points, { x: card.x + 0.4, y: card.y + 1.35, ...list }, listSize, COLORS.ink);
      }, height);
      break;
    }
    case "stats": {
      if (slide.items.length === 1) {
        const item = slide.items[0]!;
        const valueBox = { x: LEFT, y: BODY_TOP, w: slide.context ? 7.4 : RIGHT - LEFT, h: 2.25 };
        s.text(valueBox, [para([t(item.value, fitSize([item.value], valueBox, [120, 104, 88, 72, 60], true), COLORS.ink, true)])], { anchor: "b" });
        s.shape("rect", { x: LEFT, y: 4.35, w: 1.2, h: 0.1 }, COLORS.orange);
        const label = { x: LEFT, y: 4.6, w: valueBox.w, h: 1.5 };
        s.text(label, [para([t(item.label, fitSize([item.label], label, [28, 26, 24, 22, 20]), COLORS.secondary)])]);
        if (slide.context) {
          const card = { x: 8.4, y: BODY_TOP, w: RIGHT - 8.4, h: BODY_BOTTOM - BODY_TOP };
          s.shape("roundRect", card, COLORS.card);
          const text = { x: card.x + 0.35, y: card.y + 0.35, w: card.w - 0.7, h: card.h - 0.7 };
          s.text(text, [para([t(slide.context, fitSize([slide.context], text, [22, 20, 18, 16]), COLORS.ink)])], { anchor: "ctr" });
        }
      } else {
        const height = slide.context ? 3.2 : 4.2;
        const value = { w: cardWidth(slide.items.length) - 0.7, h: 1.4 };
        const label = { w: value.w, h: height - 2.35 };
        // One size for every value and one for every label: numbers side by side are compared, so they must look alike.
        const valueSize = fitEach(slide.items.map((item) => [item.value]), value, [66, 60, 54, 48, 40, 34], true);
        const labelSize = fitEach(slide.items.map((item) => [item.label]), label, [22, 20, 18, 16]);
        cards(s, slide.items.length, (box, i) => {
          const item = slide.items[i]!;
          s.text({ x: box.x + 0.35, y: box.y + 0.35, ...value }, [para([t(item.value, valueSize, COLORS.ink, true)])], { anchor: "b" });
          s.shape("rect", { x: box.x + 0.35, y: box.y + 1.9, w: 0.6, h: 0.07 }, COLORS.orange);
          s.text({ x: box.x + 0.35, y: box.y + 2.1, ...label }, [para([t(item.label, labelSize, COLORS.secondary)])]);
        }, height);
        if (slide.context) {
          const top = BODY_TOP + height + 0.2;
          const box = { x: LEFT, y: top, w: RIGHT - LEFT, h: BODY_BOTTOM - top };
          s.text(box, [para([t(slide.context, fitSize([slide.context], box, [22, 20, 18, 16]), COLORS.ink)])], { anchor: "ctr" });
        }
      }
      break;
    }
    case "quote": {
      // The quote and its attribution as one block, centred in the body; the mark sits level with the first line.
      const x = 1.9, w = RIGHT - 0.5 - x, top = 2.1, gap = 0.35;
      const attribution = `— ${slide.attribution}`;
      const attributionSize = fitSize([attribution], { w, h: 0.7 }, [20, 18, 16, 14]);
      const attributionHeight = textHeight(attribution, attributionSize, w);
      const size = fitSize([slide.quote], { w, h: BODY_BOTTOM - top - gap - attributionHeight }, [40, 36, 32, 30, 28, 26, 24, 22]);
      const quoteHeight = textHeight(slide.quote, size, w);
      const y = top + Math.max(0, (BODY_BOTTOM - top - quoteHeight - gap - attributionHeight) / 2);
      const mark = 120;
      s.text({ x: LEFT, y: y + (CAP_GAP * (size - mark)) / 72, w: 1.2, h: 1.9 }, [para([t("“", mark, COLORS.orange, true)])]);
      s.text({ x, y, w, h: quoteHeight + 0.05 }, [para([t(slide.quote, size, COLORS.paper)])]);
      s.text({ x, y: y + quoteHeight + gap, w, h: attributionHeight + 0.05 }, [para([t(attribution, attributionSize, COLORS.nightText)])]);
      break;
    }
    case "timeline": {
      const n = slide.events.length;
      const left = 0.9, width = 11.5, lineY = 4.0;
      const slot = width / n;
      s.shape("rect", { x: left, y: lineY, w: width, h: 0.05 }, COLORS.line);
      const whenSize = fitEach(slide.events.map((e) => [e.when]), { w: slot - 0.15, h: 1.0 }, [30, 26, 24, 22, 20, 18, 16], true);
      const whatSize = fitEach(slide.events.map((e) => [e.what]), { w: slot - 0.15, h: 1.9 }, [20, 18, 16, 15, 14, 13, 12]);
      slide.events.forEach((event, i) => {
        const centre = left + slot * (i + 0.5);
        const d = 0.34;
        s.shape("ellipse", { x: centre - d / 2, y: lineY + 0.025 - d / 2, w: d, h: d }, COLORS.orange);
        s.text({ x: centre - slot / 2 + 0.075, y: 2.75, w: slot - 0.15, h: 1.0 }, [para([t(event.when, whenSize, COLORS.ink, true)], { align: "ctr" })], { anchor: "b" });
        s.text({ x: centre - slot / 2 + 0.075, y: 4.45, w: slot - 0.15, h: 1.9 }, [para([t(event.what, whatSize, COLORS.ink)], { align: "ctr" })]);
      });
      break;
    }
    case "comparison": {
      comparison(s, ctx, slide);
      break;
    }
    case "chart": {
      chart(s, ctx, slide);
      break;
    }
    case "image": {
      const image = ctx.image(slide.image);
      const words = !!slide.caption || slide.points.length > 0;
      let textX = LEFT;
      if (image) {
        // Beside words the picture takes the left part, narrower for a tall picture so less of it is cut;
        // alone it is centred at its own shape.
        const h = 4.25;
        const natural = (h * image.width) / image.height;
        const w = words ? Math.min(7.0, Math.max(3.6, natural)) : Math.min(RIGHT - LEFT, natural);
        const x = words ? LEFT : (W - w) / 2;
        s.image(image, ctx.mediaName(image), { x, y: BODY_TOP, w, h });
        const line = credit(image);
        const creditBox = words ? { x, y: BODY_TOP + h + 0.05, w, h: 0.3 } : { x: LEFT, y: BODY_TOP + h + 0.05, w: RIGHT - LEFT, h: 0.3 };
        s.text(creditBox, [para([t(line, fitSize([line], { w: creditBox.w, h: 0.2 }, [10, 9, 8]), COLORS.secondary)], { align: words ? "l" : "ctr" })], { anchor: "ctr" });
        textX = x + w + 0.4;
      }
      const textW = RIGHT - textX;
      let y = BODY_TOP;
      if (slide.caption) {
        const box = { x: textX, y, w: textW, h: 1.5 };
        const size = fitSize([slide.caption], box, [26, 24, 22, 20, 18], true);
        // As tall as its lines, so the rule and the points follow right under it.
        const height = Math.min(1.5, textHeight(slide.caption, size, textW, true) + 0.05);
        s.text({ ...box, h: height }, [para([t(slide.caption, size, COLORS.ink, true)])], { anchor: "b" });
        s.shape("rect", { x: textX, y: y + height + 0.15, w: 0.5, h: 0.06 }, COLORS.orange);
        y += height + 0.45;
      }
      if (slide.points.length) {
        const box = { x: textX, y, w: textW, h: BODY_BOTTOM - y };
        bulletList(s, ctx, slide.points, box, bulletSize([slide.points], box, [22, 20, 18, 16, 14]), COLORS.ink);
      }
      break;
    }
  }
  return s.build(slide.notes);
}

/** Title, orange mark, source line, deck title and slide number: the frame every content slide shares. */
function chrome(s: SlideBuilder, ctx: DeckContext, title: string, number: number, total: number, sourceLine: string, dark = false): void {
  const quiet = dark ? COLORS.nightText : COLORS.secondary;
  s.shape("rect", { x: LEFT, y: 0.55, w: 0.7, h: 0.07 }, COLORS.orange);
  const titleBox = { x: LEFT, y: 0.72, w: RIGHT - LEFT, h: 1.05 };
  s.text(titleBox, [para([run(title, { size: fitSize([title], titleBox, [36, 32, 28, 26, 24], true), bold: true, color: dark ? COLORS.paper : COLORS.ink, lang: ctx.lang })], { lineSpacing: 95 })], { name: "Title" });
  if (sourceLine) s.text({ x: LEFT, y: 6.6, w: RIGHT - LEFT, h: 0.3 }, [para([run(sourceLine, { size: 10, color: quiet, lang: ctx.lang })])], { anchor: "ctr" });
  s.text({ x: LEFT, y: 6.98, w: 9.5, h: 0.3 }, [para([run(ctx.deck.title, { size: 10, color: quiet, lang: ctx.lang })])], { anchor: "ctr" });
  s.text({ x: 11.3, y: 6.98, w: RIGHT - 11.3, h: 0.3 }, [para([run(`${number} / ${total}`, { size: 10, color: quiet, lang: ctx.lang })], { align: "r" })], { anchor: "ctr" });
}

const CARD_GAP = 0.3;

function cardWidth(n: number): number {
  return (RIGHT - LEFT - CARD_GAP * (n - 1)) / n;
}

/** n cards side by side at the top of the body. */
function cards(s: SlideBuilder, n: number, fill: (box: Box, index: number) => void, height = 4.2): void {
  const w = cardWidth(n);
  for (let i = 0; i < n; i++) {
    const box = { x: LEFT + i * (w + CARD_GAP), y: BODY_TOP, w, h: height };
    s.shape("roundRect", box, COLORS.card);
    fill(box, i);
  }
}

/** A bullet's indent (`para`), and the gap between points as a share of the size. */
const BULLET_INDENT = 0.42;
const BULLET_GAP = 0.55;

/** The size at which each list fits its box as bullets. */
function bulletSize(lists: string[][], box: { w: number; h: number }, sizes: number[]): number {
  return fitEach(lists, { w: box.w - BULLET_INDENT, h: box.h }, sizes, false, BULLET_GAP);
}

function bulletList(s: SlideBuilder, ctx: DeckContext, points: string[], box: Box, size: number, color: string): void {
  s.text(
    box,
    points.map((p, i) => para([run(p, { size, color, lang: ctx.lang })], { bullet: COLORS.orange, spaceBefore: i === 0 ? 0 : size * BULLET_GAP })),
  );
}

/**
 * A table whose rows are as tall as their words need, at the largest size that keeps it inside the
 * body. Columns of figures are right-aligned, so their digits line up.
 */
function comparison(s: SlideBuilder, ctx: DeckContext, slide: Extract<Slide, { layout: "comparison" }>): void {
  const grid = [[slide.row_header, ...slide.columns], ...slide.rows.map((r) => [r.label, ...r.cells])];
  const figures = slide.columns.map((_, c) => {
    const cells = slide.rows.map((r) => r.cells[c] ?? "").filter((v) => v.trim());
    return cells.length > 0 && cells.every(isFigure);
  });
  const margin = 0.15;
  const longestLabel = Math.max(...grid.map((row) => textWidth(row[0]!, 18, true)));
  const first = Math.min(3.6, Math.max(2.4, longestLabel / SLACK + 2 * margin));
  const rest = (RIGHT - LEFT - first) / slide.columns.length;
  const widths = [first, ...slide.columns.map(() => rest)];
  const room = BODY_BOTTOM - BODY_TOP;
  const least = Math.min(0.8, room / grid.length);
  const heights = (size: number) =>
    grid.map((cells, r) => Math.max(least, ...cells.map((c, i) => textHeight(c || " ", size, widths[i]! - 2 * margin, r === 0 || i === 0) + 0.16)));
  const sizes = [18, 16, 15, 14, 13, 12];
  const size = sizes.find((sz) => heights(sz).reduce((a, b) => a + b, 0) <= room) ?? sizes[sizes.length - 1]!;
  const rowHeights = heights(size);
  const cell = (text: string, color: string, bold: boolean, right: boolean) =>
    para([run(text || " ", { size, color, bold, lang: ctx.lang })], { align: right ? "r" : "l" });
  s.table(
    { x: LEFT, y: BODY_TOP },
    widths,
    grid.map((cells, r) => ({
      cells: cells.map((c, i) => cell(c, r === 0 ? COLORS.paper : COLORS.ink, r === 0 || i === 0, i > 0 && figures[i - 1]!)),
      fill: r === 0 ? COLORS.night : r % 2 === 1 ? COLORS.card : COLORS.paper,
      height: rowHeights[r]!,
    })),
  );
}

/** A table cell that is a figure ("31 808", "21,88 km²", "98,7%", "€12.5 bn"), not words. */
export function isFigure(text: string): boolean {
  return /^[-+−±~≈]?\s?[$€£¥]?\s?\d[\d\s.,  ]*\s?[^\s\d]{0,5}$/u.test(text.trim());
}

/** Bars from the slide's numbers: columns for short labels (years, names), horizontal bars for long ones. */
function chart(s: SlideBuilder, ctx: DeckContext, slide: Extract<Slide, { layout: "chart" }>): void {
  const values = slide.points.map((p) => p.value);
  const max = Math.max(...values) || 1;
  const unit = slide.unit ? ` ${slide.unit}` : "";
  const shown = slide.points.map((p) => ctx.number(p.value));
  if (slide.unit) s.text({ x: LEFT, y: BODY_TOP, w: RIGHT - LEFT, h: 0.35 }, [para([run(slide.unit, { size: 16, color: COLORS.secondary, lang: ctx.lang })])], { anchor: "ctr" });
  const columns = slide.points.every((p) => p.label.length <= 10);
  if (columns) {
    const left = 0.9, width = 11.5, base = 5.7, tall = 3.0;
    const slot = width / slide.points.length;
    const barWidth = Math.min(1.3, slot * 0.6);
    // Every value on one line, all at one size, so long numbers never wrap into their bar.
    const valueSize = fitEach(shown.map((v) => [v]), { w: slot - 0.1, h: 0.45 }, [18, 16, 15, 14, 13, 12, 11], true);
    const labelSize = fitEach(slide.points.map((p) => [p.label]), { w: slot - 0.1, h: 0.5 }, [16, 15, 14, 13, 12]);
    slide.points.forEach((p, i) => {
      const centre = left + slot * (i + 0.5);
      const h = Math.max(0.03, (p.value / max) * tall);
      s.shape("rect", { x: centre - barWidth / 2, y: base - h, w: barWidth, h }, COLORS.orange, { descr: `${p.label}: ${shown[i]}${unit}` });
      s.text({ x: centre - slot / 2, y: base - h - 0.5, w: slot, h: 0.45 }, [para([run(shown[i]!, { size: valueSize, bold: true, color: COLORS.ink, lang: ctx.lang })], { align: "ctr" })], { anchor: "b" });
      s.text({ x: centre - slot / 2 + 0.05, y: base + 0.1, w: slot - 0.1, h: 0.5 }, [para([run(p.label, { size: labelSize, color: COLORS.secondary, lang: ctx.lang })], { align: "ctr" })]);
    });
    s.shape("rect", { x: left, y: base, w: width, h: 0.03 }, COLORS.line);
  } else {
    const top = 2.35, height = 3.6;
    const row = Math.min(0.62, height / slide.points.length);
    const labelWidth = 3.5, barLeft = 4.3;
    const labelSize = fitEach(slide.points.map((p) => [p.label]), { w: labelWidth, h: row }, [18, 16, 15, 14, 13, 12]);
    // The longest bar leaves room for its number inside the right margin.
    const valueWidth = Math.max(...shown.map((v) => textWidth(v, 16, true))) / SLACK + 0.1;
    const barMax = Math.min(7.0, RIGHT - barLeft - 0.12 - valueWidth);
    slide.points.forEach((p, i) => {
      const y = top + i * row;
      const w = Math.max(0.03, (p.value / max) * barMax);
      s.text({ x: LEFT, y, w: labelWidth, h: row }, [para([run(p.label, { size: labelSize, color: COLORS.ink, lang: ctx.lang })], { align: "r" })], { anchor: "ctr" });
      s.shape("rect", { x: barLeft, y: y + row * 0.18, w, h: row * 0.64 }, COLORS.orange, { descr: `${p.label}: ${shown[i]}${unit}` });
      s.text({ x: barLeft + w + 0.12, y, w: valueWidth, h: row }, [para([run(shown[i]!, { size: 16, bold: true, color: COLORS.ink, lang: ctx.lang })])], { anchor: "ctr" });
    });
  }
  if (slide.note) {
    const box = { x: LEFT, y: 6.1, w: RIGHT - LEFT, h: 0.42 };
    s.text(box, [para([run(slide.note, { size: fitSize([slide.note], box, [14, 13, 12, 11]), color: COLORS.secondary, lang: ctx.lang })])], { anchor: "ctr" });
  }
}

// ------------------------------------------------------------------ text

/** Arial's widths by code point, in thousandths of an em (`fontWidths.ts`). */
const WIDTHS = (() => {
  const regular = new Map<number, number>();
  const bold = new Map<number, number>();
  for (const [start, r, b] of WIDTH_RANGES) {
    r.forEach((w, i) => regular.set(start + i, w));
    b.forEach((w, i) => bold.set(start + i, w));
  }
  return { regular, bold };
})();

/** Single line height as a share of the size (Arial in PowerPoint and Keynote). */
const LINE = 1.2;
/** The share of a box's width text may fill: viewers set the same words a little differently. */
const SLACK = 0.95;
/** Space above a capital in a line, as a share of the size (Arial: ascent 0.905 em, capitals and quote marks 0.716 em). */
const CAP_GAP = 0.19;

/** The width of one line of text in Arial at a size in points, in inches. */
export function textWidth(text: string, size: number, bold = false): number {
  const table = bold ? WIDTHS.bold : WIDTHS.regular;
  let units = 0;
  for (const ch of text) {
    const code = ch.codePointAt(0)!;
    // Not in the table: a CJK character is an em wide; anything else gets a generous average.
    units += table.get(code) ?? (code >= 0x2e80 ? 1000 : 650);
  }
  return (units / 1000) * (size / 72);
}

/** Lines the text takes in a box this wide (inches), wrapped at spaces; a word longer than a line breaks inside it. */
export function linesAt(text: string, size: number, width: number, bold = false): number {
  const room = width * SLACK;
  const space = textWidth(" ", size, bold);
  let lines = 1;
  let current = 0;
  for (const word of text.split(/\s+/).filter(Boolean)) {
    const w = textWidth(word, size, bold);
    if (current === 0) {
      current = w;
    } else if (current + space + w <= room) {
      current += space + w;
    } else {
      lines++;
      current = w;
    }
    while (current > room) {
      lines++;
      current -= room;
    }
  }
  return lines;
}

/** The height of the text wrapped in a box this wide, in inches. */
function textHeight(text: string, size: number, width: number, bold = false): number {
  return (linesAt(text, size, width, bold) * size * LINE) / 72;
}

/** The largest size at which the paragraphs fit the box, measured with Arial's widths. Never below the last size. */
export function fitSize(texts: string[], box: { w: number; h: number }, sizes: number[], bold = false, paragraphGap = 0.5): number {
  for (const size of sizes) {
    const lines = texts.reduce((sum, text) => sum + linesAt(text, size, box.w, bold), 0);
    const needed = lines * size * LINE + Math.max(0, texts.length - 1) * size * paragraphGap;
    if (needed <= box.h * 72) return size;
  }
  return sizes[sizes.length - 1]!;
}

/** One size for boxes side by side (cards, columns): the largest at which each box's text fits its own box. */
export function fitEach(texts: string[][], box: { w: number; h: number }, sizes: number[], bold = false, paragraphGap = 0.5): number {
  if (!texts.length) return sizes[0]!;
  return Math.min(...texts.map((t) => fitSize(t, box, sizes, bold, paragraphGap)));
}

function para(runs: string[], o: { align?: "l" | "ctr" | "r"; bullet?: string; spaceBefore?: number; lineSpacing?: number } = {}): string {
  const attrs = o.bullet ? ` marL="${emu(BULLET_INDENT)}" indent="-${emu(BULLET_INDENT)}"` : "";
  const parts: string[] = [];
  if (o.lineSpacing) parts.push(`<a:lnSpc><a:spcPct val="${o.lineSpacing * 1000}"/></a:lnSpc>`);
  if (o.spaceBefore) parts.push(`<a:spcBef><a:spcPts val="${Math.round(o.spaceBefore * 100)}"/></a:spcBef>`);
  if (o.bullet) parts.push(`<a:buClr><a:srgbClr val="${o.bullet}"/></a:buClr><a:buSzPct val="80000"/><a:buFont typeface="${FONT}"/><a:buChar char="■"/>`);
  else parts.push("<a:buNone/>");
  return `<a:p><a:pPr${attrs} algn="${o.align ?? "l"}">${parts.join("")}</a:pPr>${runs.join("")}</a:p>`;
}

function run(text: string, o: { size: number; color: string; lang: string; bold?: boolean; link?: string }): string {
  return (
    `<a:r><a:rPr lang="${escape(o.lang)}" sz="${Math.round(o.size * 100)}" b="${o.bold ? 1 : 0}" dirty="0"><a:solidFill><a:srgbClr val="${o.color}"/></a:solidFill>` +
    `<a:latin typeface="${FONT}"/><a:cs typeface="${FONT}"/>${o.link ? `<a:hlinkClick r:id="${o.link}"/>` : ""}</a:rPr><a:t>${escape(text)}</a:t></a:r>`
  );
}

function txBody(paragraphs: string[], anchor: "t" | "ctr" | "b", inset: number): string {
  const i = emu(inset);
  return `<p:txBody><a:bodyPr wrap="square" lIns="${i}" tIns="${i}" rIns="${i}" bIns="${i}" anchor="${anchor}" rtlCol="0"><a:normAutofit/></a:bodyPr><a:lstStyle/>${paragraphs.join("")}</p:txBody>`;
}

function xfrm(box: Box): string {
  return `<a:xfrm><a:off x="${emu(box.x)}" y="${emu(box.y)}"/><a:ext cx="${emu(box.w)}" cy="${emu(box.h)}"/></a:xfrm>`;
}

/** "pl.wikipedia.org/wiki/Iława": an address as people read it, at most 90 characters. */
export function readableUrl(url: string): string {
  let text = url;
  try {
    const u = new URL(url);
    text = `${u.hostname.replace(/^www\./, "")}${decodeURIComponent(u.pathname).replace(/\/$/, "")}`;
  } catch {
    // Kept as it is.
  }
  return text.length > 90 ? `${text.slice(0, 89)}…` : text;
}

function credit(image: DeckImage): string {
  return `${image.author} · ${image.license} · Wikimedia Commons`;
}

function longDate(date: Date, lang: string): string {
  try {
    return new Intl.DateTimeFormat(lang, { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" }).format(date);
  } catch {
    return date.toISOString().slice(0, 10);
  }
}

/** Text for an XML element or attribute: the five special characters escaped; characters XML 1.0 can't hold left out. */
export function escape(text: string): string {
  let out = "";
  for (const ch of text) {
    const code = ch.codePointAt(0)!;
    if (ch === "&") out += "&amp;";
    else if (ch === "<") out += "&lt;";
    else if (ch === ">") out += "&gt;";
    else if (ch === '"') out += "&quot;";
    else if (ch === "'") out += "&apos;";
    else if (code === 0x9 || code === 0xa || code === 0xd || (code >= 0x20 && code <= 0xd7ff) || (code >= 0xe000 && code <= 0xfffd) || code >= 0x10000) out += ch;
  }
  return out;
}

// ------------------------------------------------------------------ package parts

const XML_HEADER = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const NAMESPACES =
  'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
const GROUP_HEADER =
  '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';

function rel(id: string, type: string, target: string): Rel {
  return { id, type: `${OFFICE_REL}/${type}`, target, external: false };
}

function relationships(items: Rel[]): string {
  return (
    XML_HEADER +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    items.map((r) => `<Relationship Id="${r.id}" Type="${r.type}" Target="${escape(r.target)}"${r.external ? ' TargetMode="External"' : ""}/>`).join("") +
    "</Relationships>"
  );
}

const PACKAGE_RELS = relationships([
  rel("rId1", "officeDocument", "ppt/presentation.xml"),
  { id: "rId2", type: "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties", target: "docProps/core.xml", external: false },
  rel("rId3", "extended-properties", "docProps/app.xml"),
]);

function contentTypes(slides: number): string {
  const overrides: [string, string][] = [
    ["/ppt/presentation.xml", `${PML}.presentation.main+xml`],
    ["/ppt/presProps.xml", `${PML}.presProps+xml`],
    ["/ppt/viewProps.xml", `${PML}.viewProps+xml`],
    ["/ppt/tableStyles.xml", `${PML}.tableStyles+xml`],
    ["/ppt/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml"],
    ["/ppt/theme/theme2.xml", "application/vnd.openxmlformats-officedocument.theme+xml"],
    ["/ppt/slideMasters/slideMaster1.xml", `${PML}.slideMaster+xml`],
    ["/ppt/slideLayouts/slideLayout1.xml", `${PML}.slideLayout+xml`],
    ["/ppt/notesMasters/notesMaster1.xml", `${PML}.notesMaster+xml`],
    ["/docProps/core.xml", "application/vnd.openxmlformats-package.core-properties+xml"],
    ["/docProps/app.xml", "application/vnd.openxmlformats-officedocument.extended-properties+xml"],
  ];
  for (let n = 1; n <= slides; n++) {
    overrides.push([`/ppt/slides/slide${n}.xml`, `${PML}.slide+xml`]);
    overrides.push([`/ppt/notesSlides/notesSlide${n}.xml`, `${PML}.notesSlide+xml`]);
  }
  return (
    XML_HEADER +
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
    '<Default Extension="xml" ContentType="application/xml"/>' +
    '<Default Extension="jpeg" ContentType="image/jpeg"/>' +
    '<Default Extension="png" ContentType="image/png"/>' +
    overrides.map(([part, type]) => `<Override PartName="${part}" ContentType="${type}"/>`).join("") +
    "</Types>"
  );
}

function core(title: string, made: Date): string {
  const stamp = made.toISOString().replace(/\.\d{3}Z$/, "Z");
  return (
    XML_HEADER +
    '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
    `<dc:title>${escape(title)}</dc:title><dc:creator>Doddy</dc:creator>` +
    `<dcterms:created xsi:type="dcterms:W3CDTF">${stamp}</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${stamp}</dcterms:modified>` +
    "</cp:coreProperties>"
  );
}

function app(slides: number): string {
  return (
    XML_HEADER +
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">' +
    `<Application>Doddy</Application><PresentationFormat>Widescreen</PresentationFormat><Slides>${slides}</Slides><Notes>${slides}</Notes></Properties>`
  );
}

function presentation(slides: number): string {
  const ids = Array.from({ length: slides }, (_, i) => `<p:sldId id="${256 + i}" r:id="rId${7 + i}"/>`).join("");
  return (
    XML_HEADER +
    `<p:presentation ${NAMESPACES} saveSubsetFonts="1">` +
    '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>' +
    '<p:notesMasterIdLst><p:notesMasterId r:id="rId2"/></p:notesMasterIdLst>' +
    `<p:sldIdLst>${ids}</p:sldIdLst>` +
    `<p:sldSz cx="${emu(W)}" cy="${emu(H)}"/><p:notesSz cx="6858000" cy="9144000"/>` +
    "</p:presentation>"
  );
}

function presentationRels(slides: number): string {
  const items = [
    rel("rId1", "slideMaster", "slideMasters/slideMaster1.xml"),
    rel("rId2", "notesMaster", "notesMasters/notesMaster1.xml"),
    rel("rId3", "presProps", "presProps.xml"),
    rel("rId4", "viewProps", "viewProps.xml"),
    rel("rId5", "theme", "theme/theme1.xml"),
    rel("rId6", "tableStyles", "tableStyles.xml"),
  ];
  for (let n = 1; n <= slides; n++) items.push(rel(`rId${6 + n}`, "slide", `slides/slide${n}.xml`));
  return relationships(items);
}

function notesSlide(notes: string, lang: string): string {
  return (
    XML_HEADER +
    `<p:notes ${NAMESPACES}><p:cSld><p:spTree>${GROUP_HEADER}` +
    '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>' +
    '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr/>' +
    `<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="${escape(lang)}" dirty="0"/><a:t>${escape(notes)}</a:t></a:r></a:p></p:txBody></p:sp>` +
    "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>"
  );
}

const PRES_PROPS = `${XML_HEADER}<p:presentationPr ${NAMESPACES}/>`;
const VIEW_PROPS = `${XML_HEADER}<p:viewPr ${NAMESPACES}><p:gridSpacing cx="76200" cy="76200"/></p:viewPr>`;
const TABLE_STYLES = `${XML_HEADER}<a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>`;
const CLR_MAP =
  '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>';
const DEF_RPR = (size: number) => `<a:defRPr sz="${size}"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mn-lt"/><a:cs typeface="+mn-cs"/></a:defRPr>`;

const SLIDE_MASTER =
  XML_HEADER +
  `<p:sldMaster ${NAMESPACES}><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="${COLORS.paper}"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>` +
  `<p:spTree>${GROUP_HEADER}</p:spTree></p:cSld>${CLR_MAP}` +
  '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>' +
  `<p:txStyles><p:titleStyle><a:lvl1pPr>${DEF_RPR(3600).replace("+mn-lt", "+mj-lt").replace("+mn-cs", "+mj-cs")}</a:lvl1pPr></p:titleStyle>` +
  `<p:bodyStyle><a:lvl1pPr>${DEF_RPR(2400)}</a:lvl1pPr></p:bodyStyle><p:otherStyle><a:lvl1pPr>${DEF_RPR(1800)}</a:lvl1pPr></p:otherStyle></p:txStyles></p:sldMaster>`;

const SLIDE_LAYOUT =
  XML_HEADER +
  `<p:sldLayout ${NAMESPACES} type="blank" preserve="1"><p:cSld name="Blank"><p:spTree>${GROUP_HEADER}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>`;

const NOTES_MASTER =
  XML_HEADER +
  `<p:notesMaster ${NAMESPACES}><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree>${GROUP_HEADER}` +
  '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg" idx="2"/></p:nvPr></p:nvSpPr>' +
  '<p:spPr><a:xfrm><a:off x="381000" y="685800"/><a:ext cx="6096000" cy="3429000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln w="12700"><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln></p:spPr></p:sp>' +
  '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" sz="quarter" idx="3"/></p:nvPr></p:nvSpPr>' +
  '<p:spPr><a:xfrm><a:off x="685800" y="4343400"/><a:ext cx="5486400" cy="4114800"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>' +
  '<p:txBody><a:bodyPr vert="horz" lIns="91440" tIns="45720" rIns="91440" bIns="45720" rtlCol="0"/><a:lstStyle/><a:p><a:pPr lvl="0"/><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>' +
  `</p:spTree></p:cSld>${CLR_MAP}` +
  `<p:notesStyle><a:lvl1pPr marL="0" algn="l" defTabSz="914400" rtl="0" eaLnBrk="1" latinLnBrk="0" hangingPunct="1">${DEF_RPR(1200)}</a:lvl1pPr></p:notesStyle></p:notesMaster>`;

const THEME = (() => {
  const color = (name: string, hex: string) => `<a:${name}><a:srgbClr val="${hex}"/></a:${name}>`;
  const fonts = (tag: string) => `<a:${tag}><a:latin typeface="${FONT}"/><a:ea typeface=""/><a:cs typeface="${FONT}"/></a:${tag}>`;
  const solid = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>';
  const line = (w: number) => `<a:ln w="${w}" cap="flat" cmpd="sng" algn="ctr">${solid}<a:prstDash val="solid"/></a:ln>`;
  const effect = "<a:effectStyle><a:effectLst/></a:effectStyle>";
  return (
    XML_HEADER +
    '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Doddy"><a:themeElements>' +
    '<a:clrScheme name="Doddy">' +
    color("dk1", COLORS.ink) + color("lt1", COLORS.paper) + color("dk2", COLORS.night) + color("lt2", COLORS.card) +
    color("accent1", COLORS.orange) + color("accent2", COLORS.accentText) + color("accent3", "326746") +
    color("accent4", COLORS.secondary) + color("accent5", COLORS.line) + color("accent6", "A3342E") +
    color("hlink", COLORS.accentText) + color("folHlink", COLORS.secondary) +
    "</a:clrScheme>" +
    `<a:fontScheme name="Doddy">${fonts("majorFont")}${fonts("minorFont")}</a:fontScheme>` +
    '<a:fmtScheme name="Doddy">' +
    `<a:fillStyleLst>${solid}${solid}${solid}</a:fillStyleLst>` +
    `<a:lnStyleLst>${line(6350)}${line(12700)}${line(19050)}</a:lnStyleLst>` +
    `<a:effectStyleLst>${effect}${effect}${effect}</a:effectStyleLst>` +
    `<a:bgFillStyleLst>${solid}${solid}${solid}</a:bgFillStyleLst>` +
    "</a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"
  );
})();

/** For callers that need to know whether a slide part carries visible text (the deck's own read-back check). */
export function slideText(xml: string): string {
  return [...xml.matchAll(/<a:t>([^<]*)<\/a:t>/g)].map((m) => m[1]).join(" ").trim();
}

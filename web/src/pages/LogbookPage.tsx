import { type KeyboardEvent, type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import { useLocation } from "react-router";
import { api, ApiError } from "../api/client.js";
import { useResource } from "../api/useResource.js";
import { useSession } from "../auth/session.js";
import { DoddyFigure } from "../components/Brand.js";
import { saveFile } from "../components/DocumentItem.js";
import { PageHeader } from "../components/PageHeader.js";
import { ErrorState, errorText, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";
import type { MessageKey } from "../i18n/messages.js";
import { defaultWeekIndex, fillGaps, glanceWeeks, isoWeek, ran, sumDays, weekdayHourGrid, type Totals } from "../logbook/aggregate.js";
import { ENDINGS, JOBS, KINDS, LENGTHS, SOURCES, WAYS, isKnownTool, toolInfo } from "../logbook/catalog.js";
import {
  ChartRoot,
  type ColumnItem,
  Columns,
  DotStrip,
  Facts,
  HBars,
  Heatmap,
  Icon,
  StackBar,
  type BarRow,
  type TipRow,
} from "../logbook/charts.js";
import { IPHONE_SENDS_LOGBOOK } from "../logbook/config.js";
import { logbookCsv } from "../logbook/csv.js";
import { exampleLogbook } from "../logbook/exampleData.js";
import { type Formats, makeFormats } from "../logbook/format.js";
import type { DaySummary } from "../logbook/schema.js";

/**
 * Logbook (ADR-593, docs/product/WEB_LOGBOOK.md): how a person uses Doddy, counted on the iPhone.
 * Two tabs: At a glance (the week, free) and Closer look (7, 30, 90 days or a year, a paid plan later).
 *
 * The numbers are what the iPhone sent to Doddy's server, read through GET /v1/web/logbook. Four
 * honest states come before them: loading, the server can't be reached (the last numbers stay,
 * dimmed, with the error), Logbook off, and on with nothing sent yet. An example with made-up
 * numbers is there to look at, only when the person asks for it, and says so in a banner. The
 * iPhone can't send days yet (IPHONE_SENDS_LOGBOOK), so the copy never tells anyone to switch on
 * something that isn't built. Counts only, no trend arrows, streaks or scores (ADR-306, DOD-10).
 */

/** After this long without a day from the iPhone, the page says when it last sent one. */
export const STALE_AFTER_MS = 2 * 86_400_000;

type Tab = "glance" | "closer";
type SortKey = "name" | "app" | "times" | "done" | "declined" | "unsure" | "failed" | "undone";

export function LogbookPage() {
  const { t } = useI18n();
  const location = useLocation();
  const { resource, reload } = useResource(api.logbook);
  const [preview, setPreview] = useState(location.hash.includes("example"));
  const example = useMemo(() => (preview ? exampleLogbook() : null), [preview]);
  const [toast, setToast] = useState<string | null>(null);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(toastTimer.current), []);
  const say = (message: string) => {
    setToast(message);
    clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(null), 4500);
  };

  const live = resource.data;
  let content: ReactNode;
  if (example) {
    content = (
      <>
        <p className="lb-banner" role="note">
          <strong>{t("logbook.exampleTitle")}</strong>{" "}
          <span>{IPHONE_SENDS_LOGBOOK ? t("logbook.exampleBody") : `${t("logbook.exampleBody")} ${t("logbook.exampleSoon")}`}</span>
          <span className="lb-gap" />
          <button type="button" className="button button-small" onClick={() => setPreview(false)}>
            {t("logbook.exampleHide")}
          </button>
        </p>
        <LogbookBody days={example.days} updatedAt={example.updatedAt} example say={say} onChanged={reload} />
      </>
    );
  } else if (live) {
    const failed = resource.status === "error";
    content = (
      <>
        {failed ? <ErrorState error={resource.error} onRetry={reload} /> : null}
        {!live.enabled || live.days.length === 0 ? (
          <LogbookEmpty off={!live.enabled} onExample={() => setPreview(true)} />
        ) : (
          <div className={failed ? "lb-dimmed" : undefined}>
            <LogbookBody days={live.days} updatedAt={live.updatedAt} example={false} say={say} onChanged={reload} />
          </div>
        )}
      </>
    );
  } else if (resource.status === "error") {
    content = <ErrorState error={resource.error} onRetry={reload} />;
  } else {
    content = <Loading />;
  }

  return (
    <>
      <PageHeader title={t("logbook.title")} lead={t("logbook.lead")} />
      {content}
      <div className="lb-toast" role="status" aria-live="polite" hidden={!toast}>
        {toast}
      </div>
    </>
  );
}

/** Logbook off, or on with nothing sent yet: one calm card, and the way to look at an example. */
function LogbookEmpty({ off, onExample }: { off: boolean; onExample: () => void }) {
  const { t } = useI18n();
  const body = off ? (IPHONE_SENDS_LOGBOOK ? t("logbook.off.body") : t("logbook.off.soon")) : t("logbook.empty.body");
  return (
    <section className="lb-empty" aria-labelledby="lb-h-empty">
      <DoddyFigure pose={off ? "shush" : "kneeling-inspect"} size={120} className="lb-empty-pose" />
      <div className="lb-empty-body">
        <h2 id="lb-h-empty">{off ? t("logbook.off.title") : t("logbook.empty.title")}</h2>
        <p>{body}</p>
        <button type="button" className="button button-quiet" onClick={onExample}>
          {t("logbook.exampleShow")}
        </button>
      </div>
    </section>
  );
}

/** The two tabs and the privacy panel, for real days or for the example. */
function LogbookBody({
  days: sent,
  updatedAt,
  example,
  say,
  onChanged,
}: {
  days: DaySummary[];
  updatedAt: string | null;
  example: boolean;
  say: (message: string) => void;
  onChanged: () => void;
}) {
  const { t, language, dateTime, date } = useI18n();
  const location = useLocation();
  const formats = useMemo(() => makeFormats(language, t), [language, t]);
  // A day the iPhone sent nothing for is a day with nothing counted: weeks and periods stay calendar-true.
  const days = useMemo(() => fillGaps(sent), [sent]);
  const [tab, setTab] = useState<Tab>(location.hash.includes("closer") ? "closer" : "glance");
  const [tables, setTables] = useState(location.hash.includes("tables"));
  const tabRefs = { glance: useRef<HTMLButtonElement>(null), closer: useRef<HTMLButtonElement>(null) };
  const stale = !example && updatedAt !== null && Date.now() - Date.parse(updatedAt) > STALE_AFTER_MS;

  const choose = (next: Tab, focus = false) => {
    setTab(next);
    if (focus) tabRefs[next].current?.focus();
  };
  const onTabKey = (event: KeyboardEvent) => {
    if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
      event.preventDefault();
      choose(tab === "glance" ? "closer" : "glance", true);
    }
  };

  return (
    <ChartRoot tables={tables}>
      {stale && updatedAt ? (
        <p className="lb-stale" role="note">
          {t("logbook.stale", { time: date(updatedAt) })}
        </p>
      ) : null}

      <div className="lb-tabs" role="tablist" aria-label={t("logbook.tabs")}>
        <button
          type="button"
          role="tab"
          className="lb-tab"
          id="lb-tab-glance"
          ref={tabRefs.glance}
          aria-controls="lb-panel"
          aria-selected={tab === "glance"}
          tabIndex={tab === "glance" ? 0 : -1}
          onClick={() => choose("glance")}
          onKeyDown={onTabKey}
        >
          {t("logbook.tab.glance")}
        </button>
        <button
          type="button"
          role="tab"
          className="lb-tab"
          id="lb-tab-closer"
          ref={tabRefs.closer}
          aria-controls="lb-panel"
          aria-selected={tab === "closer"}
          tabIndex={tab === "closer" ? 0 : -1}
          onClick={() => choose("closer")}
          onKeyDown={onTabKey}
        >
          {t("logbook.tab.closer")} <span className="lb-tab-chip">{t("logbook.tab.closerChip")}</span>
        </button>
      </div>

      <div className={`lb-panel ${tab === "closer" ? "lb-panel-closer" : ""}`} role="tabpanel" id="lb-panel" aria-labelledby={`lb-tab-${tab}`}>
        {tab === "glance" ? (
          <GlancePanel days={days} updatedAt={updatedAt} example={example} f={formats} dateTime={dateTime} />
        ) : (
          <CloserPanel days={days} example={example} f={formats} tables={tables} setTables={setTables} say={say} />
        )}
      </div>

      <PrivacyPanel example={example} say={say} onChanged={onChanged} />
    </ChartRoot>
  );
}

// ---------------------------------------------------------------- shared bits

function useNames(f: Formats) {
  const { t } = useI18n();
  return {
    tool: (id: string) => (isKnownTool(id) ? t(`logbook.tool.${id}`) : id.replace(/_/g, " ")),
    app: (id: string) => t(`logbook.app.${toolInfo(id).app}`),
    job: (id: (typeof JOBS)[number]["id"]) => t(`logbook.job.${id}`),
    kind: (id: (typeof KINDS)[number]) => t(`logbook.kind.${id}`),
    source: (id: (typeof SOURCES)[number]) => t(`logbook.source.${id}`),
    ended: (id: (typeof ENDINGS)[number]) => t(`logbook.ended.${id}`),
    length: (id: (typeof LENGTHS)[number]) => t(`logbook.len.${id}`),
    way: (id: (typeof WAYS)[number]) => t(`logbook.way.${id}`),
    language: f.language,
  };
}

function jobRows(totals: Totals, names: ReturnType<typeof useNames>, nothing: string): BarRow[] {
  return JOBS.map((job) => {
    const entry = totals.jobs[job.id];
    const top = Object.entries(entry.tools)
      .filter(([, n]) => n > 0)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 4)
      .map(([id, n]): TipRow => [names.tool(id), n]);
    return { key: job.id, label: names.job(job.id), icon: job.icon, value: entry.count, tip: top.length ? top : ([[nothing, ""]] as TipRow[]) };
  })
    .filter((row) => row.value > 0 || row.key !== "other")
    .sort((a, b) => b.value - a.value);
}

// ---------------------------------------------------------------- AT A GLANCE

function GlancePanel({ days, updatedAt, example, f, dateTime }: { days: DaySummary[]; updatedAt: string | null; example: boolean; f: Formats; dateTime: (iso: string) => string }) {
  const { t } = useI18n();
  const names = useNames(f);
  const weeks = useMemo(() => glanceWeeks(days), [days]);
  const [index, setIndex] = useState(() => defaultWeekIndex(weeks));
  const week = weeks[index] ?? [];
  const totals = useMemo(() => sumDays(week), [week]);
  const first = week[0]?.day ?? "";
  const last = week[week.length - 1]?.day ?? "";
  // Only the newest week is "so far"; a first week that started mid-week is a short week, not an unfinished one.
  const partial = week.length < 7 && index === weeks.length - 1;
  const weekNumber = t("logbook.week.number", { n: first ? isoWeek(first) : 0 });
  const range = first ? f.range(first, last, true) : "";

  const receipt: { label: string; value: string | number; cls?: string }[] = [
    { label: t("logbook.conversations"), value: totals.conversations },
    { label: t("logbook.timeTalking"), value: f.minutes(totals.seconds) },
    { label: t("logbook.notesSaved"), value: totals.notesSaved },
    { label: t("logbook.listItems"), value: totals.listAdded },
    { label: t("logbook.did"), value: totals.done, cls: "lb-space" },
    { label: t("logbook.didNow"), value: totals.doneNow, cls: "lb-sub" },
    { label: t("logbook.didAfter"), value: totals.doneAfterYes, cls: "lb-sub" },
    { label: t("logbook.asked"), value: totals.asked, cls: "lb-space" },
    { label: t("logbook.yes"), value: totals.yes, cls: "lb-sub" },
    { label: t("logbook.no"), value: totals.no, cls: "lb-sub" },
    { label: t("logbook.unsure"), value: totals.unsure, cls: "lb-space" },
    { label: t("logbook.failed"), value: totals.failed },
    { label: t("logbook.errands"), value: totals.errands.handedOver },
  ];

  const peak = totals.byHour.indexOf(Math.max(...totals.byHour));
  const span = (a: number, b: number) => totals.byHour.slice(a, b).reduce((s, n) => s + n, 0);
  const night = span(0, 6);
  const dayparts = [
    { label: `${t("logbook.part.morning")} · 06–12`, n: span(6, 12) },
    { label: `${t("logbook.part.afternoon")} · 12–18`, n: span(12, 18) },
    { label: `${t("logbook.part.evening")} · 18–24`, n: span(18, 24) },
    ...(night > 0 ? [{ label: `${t("logbook.part.night")} · 00–06`, n: night }] : []),
  ];

  const kinds = KINDS.map((k) => ({ id: k, n: totals.notesByKind[k] })).filter((k) => k.n > 0).sort((a, b) => b.n - a.n);
  const how = SOURCES.map((s) => ({ s, n: totals.notesBySource[s] })).filter((x) => x.n > 0).map((x) => `${names.source(x.s).toLowerCase()} ${x.n}`);

  const dayItems: ColumnItem[] = week.map((d) => ({
    key: d.day,
    label: f.dayLong(d.day),
    short: f.weekdayShort(d.day),
    value: d.conversations.count,
    tip: [[t("logbook.conversations"), d.conversations.count], [t("logbook.timeTalking"), f.minutes(d.conversations.seconds)]],
    cells: [d.conversations.count, f.minutes(d.conversations.seconds)],
  }));

  const label = partial ? t("logbook.week.soFar") : weekNumber;
  return (
    <>
      <div className="lb-week-row">
        <div className="lb-week-nav" role="group" aria-label={t("logbook.week.choose")}>
          <button type="button" className="lb-icon-btn" aria-label={t("logbook.week.prev")} disabled={index === 0} onClick={() => setIndex(index - 1)}>
            <Icon name="left" />
          </button>
          <p className="lb-week-label" aria-live="polite">
            <span>{label}</span>
            {range}
          </p>
          <button type="button" className="lb-icon-btn" aria-label={t("logbook.week.next")} disabled={index >= weeks.length - 1} onClick={() => setIndex(index + 1)}>
            <Icon name="right" />
          </button>
        </div>
        {updatedAt ? <p className="lb-fresh">{t(example ? "logbook.fresh.example" : "logbook.fresh", { time: dateTime(updatedAt) })}</p> : null}
      </div>

      <section className="lb-week" aria-labelledby="lb-week-title">
        <div className="lb-week-copy">
          <p className="lb-eyebrow">{partial ? t("logbook.week.soFar") : index === weeks.length - 2 ? t("logbook.week.last") : weekNumber}</p>
          <h2 className="lb-week-title" id="lb-week-title">
            {partial ? t("logbook.glance.titleSoFar") : t("logbook.glance.title")}
          </h2>
          <p className="lb-week-lede">{t("logbook.glance.lede")}</p>
          <p className="says">{t("logbook.glance.hand")}</p>
          <DoddyFigure pose="belly-reading" size={170} className="lb-week-pose" />
        </div>
        <figure className="lb-receipt" aria-labelledby="lb-rc-title">
          <div className="lb-receipt-paper">
            <p className="lb-rc-head" id="lb-rc-title">
              {t("logbook.receipt.head")}
            </p>
            <p className="lb-rc-sub">{partial ? t("logbook.receipt.soFar", { range }) : t("logbook.receipt.week", { n: first ? isoWeek(first) : 0, range })}</p>
            <dl className="lb-rc-lines">
              {receipt.map((line) => (
                <div key={line.label} className={`lb-rc-line ${line.cls ?? ""}`}>
                  <dt>{line.label}</dt>
                  <span className="lb-rc-dots" aria-hidden="true" />
                  <dd>{line.value}</dd>
                </div>
              ))}
            </dl>
            <p className="lb-rc-foot">{t("logbook.receipt.foot")}</p>
            <p className="lb-rc-stamp" aria-hidden="true">
              {t("logbook.receipt.stamp")}
            </p>
          </div>
        </figure>
      </section>

      <div className="lb-grid-2">
        <section className="lb-card" aria-labelledby="lb-h-uses">
          <h2 id="lb-h-uses">{t("logbook.uses.title")}</h2>
          <p className="lb-card-sub">{t("logbook.uses.sub")}</p>
          <HBars rows={jobRows(totals, names, t("logbook.uses.nothing"))} caption={t("logbook.uses.caption")} head={t("logbook.uses.head")} valueHead={t("logbook.uses.value")} />
        </section>
        <section className="lb-card" aria-labelledby="lb-h-when">
          <h2 id="lb-h-when">{t("logbook.when.title")}</h2>
          <p className="lb-card-sub">{totals.conversations ? t("logbook.when.sub", { from: f.hour(peak), to: f.hour(peak + 1) }) : t("logbook.when.none")}</p>
          <DotStrip
            byHour={totals.byHour}
            aria={t("logbook.when.aria")}
            caption={t("logbook.when.caption")}
            head={[t("logbook.when.head"), t("logbook.conversations")]}
            countLabel={t("logbook.conversations")}
            hourText={f.hour}
            hourRangeText={f.hourRange}
          />
          <dl className="lb-dayparts">
            {dayparts.map((p) => (
              <div key={p.label}>
                <dt>{p.label}</dt>
                <dd>{p.n}</dd>
              </div>
            ))}
          </dl>
        </section>
      </div>

      <div className="lb-grid-2">
        <section className="lb-card" aria-labelledby="lb-h-slips">
          <h2 id="lb-h-slips">{t("logbook.slips.title")}</h2>
          <p className="lb-card-sub">{totals.notesSaved ? t("logbook.slips.sub") : t("logbook.slips.none")}</p>
          <div className="lb-slips">
            {kinds.map((k) => (
              <div className="lb-slip-row" key={k.id}>
                <div className="lb-slip-name">
                  <span>{names.kind(k.id)}</span>
                  <b>{k.n}</b>
                </div>
                <div className="lb-slip-stack" role="img" aria-label={`${names.kind(k.id)}: ${k.n}`}>
                  {Array.from({ length: k.n }, (_, i) => (
                    <span className="lb-slip" key={i} />
                  ))}
                </div>
              </div>
            ))}
            {how.length ? <p className="lb-slips-how">{t("logbook.slips.how", { list: how.join(", ") })}</p> : null}
          </div>
        </section>
        <section className="lb-card" aria-labelledby="lb-h-days">
          <h2 id="lb-h-days">{t("logbook.days.title")}</h2>
          <p className="lb-card-sub">{t("logbook.days.sub")}</p>
          <Columns items={dayItems} height={190} valueAll aria={t("logbook.days.aria")} head={[t("logbook.days.head"), t("logbook.conversations"), t("logbook.timeTalking")]} />
        </section>
      </div>
    </>
  );
}

// ---------------------------------------------------------------- CLOSER LOOK

const STATUS_PARTS = [
  { cls: "lb-s-done", icon: "check", iconCls: "lb-done" },
  { cls: "lb-s-unsure", icon: "question", iconCls: "lb-unsure" },
  { cls: "lb-s-failed", icon: "cross", iconCls: "lb-failed" },
  { cls: "lb-s-no", icon: "no", iconCls: "lb-no" },
] as const;

function CloserPanel({
  days,
  example,
  f,
  tables,
  setTables,
  say,
}: {
  days: DaySummary[];
  example: boolean;
  f: Formats;
  tables: boolean;
  setTables: (on: boolean) => void;
  say: (message: string) => void;
}) {
  const { t } = useI18n();
  const names = useNames(f);
  const [range, setRange] = useState<7 | 30 | 90 | 365>(30);
  const [sort, setSort] = useState<{ key: SortKey; dir: "ascending" | "descending" }>({ key: "times", dir: "descending" });
  const shown = useMemo(() => days.slice(-range), [days, range]);
  const totals = useMemo(() => sumDays(shown), [shown]);
  const weekly = range > 31;
  const first = shown[0]?.day ?? "";
  const last = shown[shown.length - 1]?.day ?? "";
  const average = totals.conversations ? totals.seconds / totals.conversations : 0;

  const groups = useMemo(() => {
    if (range <= 7) return shown.map((d) => [d]);
    const out: DaySummary[][] = [];
    for (const d of shown) {
      const current = out[out.length - 1];
      if (!current || new Date(`${d.day}T00:00:00Z`).getUTCDay() === 1) out.push([d]);
      else current.push(d);
    }
    return out;
  }, [shown, range]);

  const convItems: ColumnItem[] = (weekly ? groups : shown.map((d) => [d])).map((group) => {
    const a = group[0]?.day ?? "";
    const b = group[group.length - 1]?.day ?? "";
    const count = group.reduce((s, d) => s + d.conversations.count, 0);
    const seconds = group.reduce((s, d) => s + d.conversations.seconds, 0);
    const tip: TipRow[] = [[t("logbook.conversations"), count], [t("logbook.timeTalking"), f.minutes(seconds)]];
    if (weekly) tip.push([t("logbook.conv.days"), group.length]);
    return {
      key: a,
      label: weekly ? f.range(a, b) : f.dayLong(a),
      short: weekly || range > 7 ? f.dayShort(a) : f.weekdayShort(a),
      value: count,
      tip,
      cells: [count, f.minutes(seconds)],
    };
  });

  const noteItems: ColumnItem[] = groups.map((group) => {
    const a = group[0]?.day ?? "";
    const b = group[group.length - 1]?.day ?? "";
    const by = Object.fromEntries(SOURCES.map((s) => [s, group.reduce((sum, d) => sum + d.notes.by_source[s], 0)])) as Record<(typeof SOURCES)[number], number>;
    const value = SOURCES.reduce((sum, s) => sum + by[s], 0);
    return {
      key: a,
      label: group.length === 1 ? f.dayLong(a) : f.range(a, b),
      short: group.length === 1 ? f.weekdayShort(a) : f.dayShort(a),
      value,
      parts: SOURCES.map((s, i) => ({ cls: `lb-f${i + 1}`, value: by[s] })),
      tip: [[t("logbook.notes.head"), value], ...SOURCES.map((s): TipRow => [names.source(s), by[s]])],
      cells: [value, ...SOURCES.map((s) => by[s])],
    };
  });

  const toolRows = Object.entries(totals.tools)
    .map(([id, o]) => ({
      id,
      name: names.tool(id),
      app: names.app(id),
      ask: toolInfo(id).ask,
      times: ran(o) + o.declined,
      done: o.done,
      declined: o.declined,
      unsure: o.unsure,
      failed: o.failed,
      undone: o.undone,
    }))
    .filter((r) => r.times > 0);
  toolRows.sort((a, b) => {
    const x = a[sort.key];
    const y = b[sort.key];
    const c = typeof x === "string" && typeof y === "string" ? x.localeCompare(y) : Number(x) - Number(y);
    return sort.dir === "ascending" ? c : -c;
  });
  const maxTimes = Math.max(1, ...toolRows.map((r) => r.times));
  const columns: { key: SortKey; label: string; numeric: boolean }[] = [
    { key: "name", label: t("logbook.tools.tool"), numeric: false },
    { key: "app", label: t("logbook.tools.app"), numeric: false },
    { key: "times", label: t("logbook.tools.times"), numeric: true },
    { key: "done", label: t("logbook.tools.done"), numeric: true },
    { key: "declined", label: t("logbook.tools.declined"), numeric: true },
    { key: "unsure", label: t("logbook.unsure"), numeric: true },
    { key: "failed", label: t("logbook.failed"), numeric: true },
    { key: "undone", label: t("logbook.tools.undone"), numeric: true },
  ];
  const onSort = (key: SortKey, numeric: boolean) =>
    setSort((s) => ({ key, dir: s.key === key ? (s.dir === "descending" ? "ascending" : "descending") : numeric ? "descending" : "ascending" }));

  const statusParts = [
    { ...STATUS_PARTS[0], value: totals.askDone, label: t("logbook.askedCard.done") },
    { ...STATUS_PARTS[1], value: totals.askUnsure, label: t("logbook.unsure") },
    { ...STATUS_PARTS[2], value: totals.askFailed, label: t("logbook.failed") },
    { ...STATUS_PARTS[3], value: totals.no, label: t("logbook.no") },
  ];
  const languageTotal = Object.values(totals.languages).reduce((s, n) => s + n, 0) || 1;
  const languages = Object.entries(totals.languages).sort((a, b) => b[1] - a[1]);
  const e = totals.errands;

  // The numbers shown for this period, as a file. The example only says what the button will do.
  const onCsv = async () => {
    if (example) {
      say(t("logbook.demo.csv"));
      return;
    }
    await saveFile(new Blob([logbookCsv(shown)], { type: "text/csv;charset=utf-8" }), `doddy-logbook-${first}-to-${last}.csv`);
    say(t("logbook.csvSaved"));
  };

  return (
    <>
      <div className="lb-filters" role="group" aria-label={t("logbook.period")}>
        <div className="lb-seg" role="group" aria-label={t("logbook.range.label")}>
          {([7, 30, 90, 365] as const).map((n) => (
            <button key={n} type="button" className="lb-seg-btn" aria-pressed={range === n} onClick={() => setRange(n)}>
              {n === 365 ? t("logbook.range.year") : t("logbook.range.days", { n })}
            </button>
          ))}
        </div>
        <p className="lb-range" aria-live="polite">
          {first ? f.range(first, last, true) : ""}
        </p>
        <span className="lb-gap" />
        <label className="lb-switch">
          <input type="checkbox" checked={tables} onChange={(event) => setTables(event.target.checked)} />
          <span>{t("logbook.tables")}</span>
        </label>
        <button type="button" className="button button-quiet button-small" onClick={() => void onCsv()}>
          {t("logbook.csv")}
        </button>
      </div>

      <div className="lb-kpis">
        {[
          [t("logbook.conversations"), totals.conversations],
          [t("logbook.timeTalking"), f.minutes(totals.seconds)],
          [t("logbook.avg"), f.average(average)],
          [t("logbook.notesSaved"), totals.notesSaved],
          [t("logbook.did"), totals.done],
        ].map(([label, value]) => (
          <div className="lb-kpi" key={label}>
            <p className="lb-kpi-label">{label}</p>
            <p className="lb-kpi-value">{value}</p>
          </div>
        ))}
      </div>

      <section className="lb-card" aria-labelledby="lb-h-conv">
        <h2 id="lb-h-conv">{t("logbook.conversations")}</h2>
        <p className="lb-card-sub">{weekly ? t("logbook.conv.subWeek") : t("logbook.conv.subDay")}</p>
        <Columns
          items={convItems}
          height={220}
          aria={weekly ? t("logbook.conv.ariaWeek") : t("logbook.conv.ariaDay")}
          head={[weekly ? t("logbook.conv.headWeek") : t("logbook.days.head"), t("logbook.conversations"), t("logbook.timeTalking")]}
        />
      </section>

      <div className="lb-grid-2">
        <section className="lb-card" aria-labelledby="lb-h-heat">
          <h2 id="lb-h-heat">{t("logbook.heat.title")}</h2>
          <p className="lb-card-sub">{t("logbook.heat.sub")}</p>
          <Heatmap
            grid={weekdayHourGrid(shown)}
            aria={t("logbook.heat.aria")}
            caption={t("logbook.heat.caption")}
            head={[t("logbook.heat.head"), t("logbook.conversations")]}
            countLabel={t("logbook.conversations")}
            noneLabel={t("logbook.heat.none")}
            maxLabel={(n) => t("logbook.heat.max", { n })}
            weekdayShort={f.weekdayShortByIndex}
            weekdayLong={f.weekdayLongByIndex}
            hourText={f.hour}
            hourRangeText={f.hourRange}
          />
        </section>
        <section className="lb-card" aria-labelledby="lb-h-len">
          <h2 id="lb-h-len">{t("logbook.len.title")}</h2>
          <p className="lb-card-sub">{t("logbook.len.sub")}</p>
          <HBars compact rows={LENGTHS.map((k) => ({ key: k, label: names.length(k), value: totals.lengths[k] }))} caption={t("logbook.len.caption")} head={t("logbook.len.head")} valueHead={t("logbook.conversations")} />
          <h3 className="lb-card-h3">{t("logbook.ended.title")}</h3>
          <HBars compact rows={ENDINGS.map((k) => ({ key: k, label: names.ended(k), value: totals.ended[k] }))} caption={t("logbook.ended.caption")} head={t("logbook.ended.head")} valueHead={t("logbook.conversations")} />
        </section>
      </div>

      <section className="lb-card" aria-labelledby="lb-h-tools">
        <h2 id="lb-h-tools">{t("logbook.tools.title")}</h2>
        <p className="lb-card-sub">{t("logbook.tools.sub")}</p>
        <div className="lb-table-wrap">
          <table>
            <caption className="lb-sr">{t("logbook.tools.caption")}</caption>
            <thead>
              <tr>
                {columns.map((c) => (
                  <th key={c.key} scope="col" className={c.numeric ? "lb-n" : undefined} aria-sort={sort.key === c.key ? sort.dir : undefined}>
                    <button type="button" onClick={() => onSort(c.key, c.numeric)}>
                      {c.label}
                    </button>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {toolRows.map((r) => (
                <tr key={r.id}>
                  <td className="lb-tool">{r.name}</td>
                  <td className="lb-app">{r.app}</td>
                  <td className="lb-n">
                    <span className="lb-mini" aria-hidden="true" style={{ width: `${Math.max(2, (r.times / maxTimes) * 64)}px` }} />
                    {r.times}
                  </td>
                  <td className={`lb-n ${r.done ? "" : "lb-none"}`}>{r.done}</td>
                  {r.ask ? (
                    <td className={`lb-n ${r.declined ? "" : "lb-none"}`}>{r.declined}</td>
                  ) : (
                    <td className="lb-n lb-none" title={t("logbook.tools.noAsk")}>
                      –
                    </td>
                  )}
                  <td className={`lb-n ${r.unsure ? "" : "lb-none"}`}>{r.unsure}</td>
                  <td className={`lb-n ${r.failed ? "" : "lb-none"}`}>{r.failed}</td>
                  <td className={`lb-n ${r.undone ? "" : "lb-none"}`}>{r.undone}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <div className="lb-grid-2">
        <section className="lb-card" aria-labelledby="lb-h-asked">
          <h2 id="lb-h-asked">{t("logbook.askedCard.title")}</h2>
          <p className="lb-card-sub">{t("logbook.askedCard.sub")}</p>
          <p className="lb-big-line">{totals.asked ? t("logbook.askedCard.line", { asked: totals.asked, yes: totals.yes, no: totals.no }) : t("logbook.askedCard.none")}</p>
          <StackBar parts={statusParts.map((p) => ({ cls: p.cls, value: p.value }))} aria={t("logbook.askedCard.aria")} />
          <ul className="lb-legend lb-rows">
            {statusParts.map((p) => (
              <li key={p.cls}>
                <span>
                  <Icon name={p.icon} className={p.iconCls} />
                  <span>{p.label}</span>
                </span>
                <b>{p.value}</b>
              </li>
            ))}
          </ul>
          <p className="lb-fine">{t("logbook.askedCard.note")}</p>
        </section>
        <section className="lb-card" aria-labelledby="lb-h-notes">
          <h2 id="lb-h-notes">{t("logbook.notes.title")}</h2>
          <p className="lb-card-sub">{range <= 7 ? t("logbook.notes.subDay", { n: totals.notesSaved }) : t("logbook.notes.subWeek", { n: totals.notesSaved })}</p>
          <ul className="lb-legend">
            {SOURCES.map((s, i) => (
              <li key={s}>
                <span className={`lb-key lb-c${i + 1}`} />
                <span>{names.source(s)}</span>
                <b>{totals.notesBySource[s]}</b>
              </li>
            ))}
          </ul>
          <Columns items={noteItems} height={190} aria={t("logbook.notes.aria")} head={[range <= 7 ? t("logbook.days.head") : t("logbook.conv.headWeek"), t("logbook.notes.head"), ...SOURCES.map((s) => names.source(s))]} />
          <h3 className="lb-card-h3">{t("logbook.notes.byType")}</h3>
          <HBars
            compact
            rows={KINDS.map((k) => ({ key: k, label: names.kind(k), value: totals.notesByKind[k] })).filter((r) => r.value > 0).sort((a, b) => b.value - a.value)}
            caption={t("logbook.notes.typeCaption")}
            head={t("logbook.notes.typeHead")}
            valueHead={t("logbook.notes.head")}
          />
        </section>
      </div>

      <div className="lb-grid-4">
        <section className="lb-card lb-small" aria-labelledby="lb-h-errands">
          <h2 id="lb-h-errands">{t("logbook.errands")}</h2>
          {e.handedOver ? (
            <Facts
              items={[
                { label: t("logbook.errandsCard.handed"), value: e.handedOver },
                { label: t("logbook.errandsCard.finished"), value: e.finished },
                { label: t("logbook.errandsCard.avg"), value: Math.round(e.minutes / e.handedOver), unit: t("logbook.unit.min") },
                { label: t("logbook.errandsCard.stopped"), value: e.stopped },
                { label: t("logbook.errandsCard.searches"), value: e.searches },
                { label: t("logbook.errandsCard.pages"), value: e.pages },
              ]}
            />
          ) : (
            <p className="lb-card-sub">{t("logbook.errandsCard.none")}</p>
          )}
        </section>
        <section className="lb-card lb-small" aria-labelledby="lb-h-langs">
          <h2 id="lb-h-langs">{t("logbook.langs.title")}</h2>
          <StackBar parts={languages.map(([code, n], i) => ({ cls: `lb-c${i + 1}`, value: n }))} aria={t("logbook.langs.title")} />
          <ul className="lb-legend lb-rows">
            {languages.map(([code, n], i) => (
              <li key={code}>
                <span>
                  <span className={`lb-key lb-c${i + 1}`} />
                  <span>{names.language(code)}</span>
                </span>
                <b>
                  {Math.round((n / languageTotal) * 100)}% · {n}
                </b>
              </li>
            ))}
          </ul>
        </section>
        <section className="lb-card lb-small" aria-labelledby="lb-h-ways">
          <h2 id="lb-h-ways">{t("logbook.ways.title")}</h2>
          <HBars
            compact
            rows={WAYS.map((w) => ({ key: w, label: names.way(w), value: totals.waysIn[w] })).sort((a, b) => b.value - a.value)}
            caption={t("logbook.ways.caption")}
            head={t("logbook.ways.head")}
            valueHead={t("logbook.uses.value")}
          />
        </section>
        <section className="lb-card lb-small" aria-labelledby="lb-h-lists">
          <h2 id="lb-h-lists">{t("logbook.lists.title")}</h2>
          <Facts
            items={[
              { label: t("logbook.lists.added"), value: totals.listAdded },
              { label: t("logbook.lists.ticked"), value: totals.listsTicked },
              { label: t("logbook.lists.byVoice"), value: totals.addedVoice },
              { label: t("logbook.lists.typed"), value: totals.addedTyped },
              { label: t("logbook.lists.translator"), value: totals.translator.sessions },
              { label: t("logbook.lists.translating"), value: totals.translator.minutes, unit: t("logbook.unit.min") },
            ]}
          />
        </section>
      </div>
    </>
  );
}

// ---------------------------------------------------------------- what Logbook will know

function PrivacyPanel({ example, say, onChanged }: { example: boolean; say: (message: string) => void; onChanged: () => void }) {
  const { t } = useI18n();
  const { expired } = useSession();
  const [armed, setArmed] = useState(false);
  const [busy, setBusy] = useState<"download" | "delete" | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);

  /** A signed-out answer signs the page out; anything else is said once, in words. */
  const fail = (caught: unknown) => {
    if (caught instanceof ApiError && caught.code === "unauthenticated") {
      expired();
      return;
    }
    say(errorText(caught instanceof ApiError ? caught : new ApiError("network", String(caught), 0), t));
  };

  // Download and delete are never paywalled. The example only says what they will do.
  const onDownload = async () => {
    if (example) {
      say(t("logbook.demo.download"));
      return;
    }
    setBusy("download");
    try {
      await saveFile(await api.logbookFile(), `doddy-logbook-${new Date().toISOString().slice(0, 10)}.json`);
      say(t("logbook.downloaded"));
    } catch (caught) {
      fail(caught);
    } finally {
      setBusy(null);
    }
  };

  const onDelete = async () => {
    clearTimeout(timer.current);
    if (!armed) {
      setArmed(true);
      timer.current = setTimeout(() => setArmed(false), 5000);
      return;
    }
    setArmed(false);
    if (example) {
      say(t("logbook.demo.delete"));
      return;
    }
    setBusy("delete");
    try {
      // "Deleted" is said only after the server has answered with how many days it removed.
      const { deletedDays } = await api.deleteLogbook();
      say(deletedDays > 0 ? t("logbook.deleted", { n: deletedDays }) : t("logbook.deletedNone"));
      onChanged();
    } catch (caught) {
      fail(caught);
    } finally {
      setBusy(null);
    }
  };

  const list = (keys: MessageKey[], cls: string) => (
    <ul className={cls}>
      {keys.map((k) => (
        <li key={k}>{t(k)}</li>
      ))}
    </ul>
  );

  return (
    <section className="lb-privacy" aria-labelledby="lb-h-privacy">
      <DoddyFigure pose="shush" size={110} className="lb-privacy-pose" />
      <div className="lb-privacy-body">
        <h2 id="lb-h-privacy" className="lb-privacy-title">
          {t("logbook.privacy.title")}
        </h2>
        <div className="lb-privacy-cols">
          <div>
            <h3 className="lb-privacy-h">{t("logbook.privacy.on")}</h3>
            {list(["logbook.privacy.on1", "logbook.privacy.on2", "logbook.privacy.on3"], "lb-ticks")}
          </div>
          <div>
            <h3 className="lb-privacy-h">{t("logbook.privacy.never")}</h3>
            {list(["logbook.privacy.never1", "logbook.privacy.never2", "logbook.privacy.never3", "logbook.privacy.never4"], "lb-crosses")}
          </div>
          <div>
            <h3 className="lb-privacy-h">{t("logbook.privacy.yours")}</h3>
            {list(["logbook.privacy.yours1", "logbook.privacy.yours2", "logbook.privacy.yours3", "logbook.privacy.yours4"], "lb-plain")}
            <div className="lb-privacy-actions">
              <button type="button" className="button button-quiet button-small" onClick={() => void onDownload()} disabled={busy !== null}>
                {t("logbook.download")}
              </button>
              <button type="button" className={`button button-quiet button-small lb-danger ${armed ? "is-armed" : ""}`} onClick={() => void onDelete()} disabled={busy !== null}>
                {armed ? t("logbook.deleteAgain") : t("logbook.delete")}
              </button>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}


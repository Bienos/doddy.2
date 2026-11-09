import { type CSSProperties, type KeyboardEvent, type PointerEvent, type ReactNode, useRef, useState } from "react";
import { useI18n } from "../i18n/i18n.js";

/**
 * The admin dashboard's charts, drawn by hand in SVG and HTML (no chart library). Rules from the
 * data-viz method: thin marks, a 4px rounded data end on a square baseline, 2px lines, a hairline
 * recessive grid, text in text colors (never the series color), a legend for two or more series,
 * a tooltip on hover and on keyboard focus, and a table twin for every chart, so no value is only
 * in a tooltip. Colors come from `admin.css` and are validated for light and dark.
 */

// -------------------------------------------------------------------------------- tooltip

/** One tooltip per chart: it follows the pointer inside the chart's frame and stays within it. */
export function useTooltip() {
  const ref = useRef<HTMLDivElement>(null);
  const [tip, setTip] = useState<{ x: number; y: number; node: ReactNode } | null>(null);
  const show = (point: { clientX: number; clientY: number }, node: ReactNode) => {
    const box = ref.current?.getBoundingClientRect();
    if (!box) return;
    const x = Math.min(Math.max(point.clientX - box.left, 90), Math.max(box.width - 90, 90));
    setTip({ x, y: point.clientY - box.top, node });
  };
  const hide = () => setTip(null);
  const box = tip ? (
    <div className="adm-tip" style={{ left: tip.x, top: tip.y }} aria-hidden="true">
      {tip.node}
    </div>
  ) : null;
  return { ref, show, hide, box };
}

/** A tooltip row: a short line or square key, the value first (the reader has the series, wants the number), then the name. */
export function TipRow({ color, value, label, square }: { color?: string; value: ReactNode; label: ReactNode; square?: boolean }) {
  return (
    <div className="adm-tip-row">
      {color ? <span className={square ? "adm-key-square" : "adm-key-line"} style={{ background: color }} /> : null}
      <strong>{value}</strong>
      <span>{label}</span>
    </div>
  );
}

// -------------------------------------------------------------------------------- frames

/** A chart in a card with a switch to its table (every value reachable without hovering). */
export function ChartCard({ title, sub, chart, table, legend, wide }: { title: string; sub?: string; chart: ReactNode; table: ReactNode; legend?: ReactNode; wide?: boolean }) {
  const { t } = useI18n();
  const [asTable, setAsTable] = useState(false);
  return (
    <section className={`adm-card ${wide ? "is-wide" : ""}`}>
      <header className="adm-card-head">
        <div>
          <h2>{title}</h2>
          {sub ? <p className="adm-sub">{sub}</p> : null}
        </div>
        <button type="button" className="adm-ghost" aria-pressed={asTable} onClick={() => setAsTable((v) => !v)}>
          {asTable ? t("admin.chart.chart") : t("admin.chart.table")}
        </button>
      </header>
      {legend && !asTable ? legend : null}
      {asTable ? <div className="adm-table-wrap">{table}</div> : chart}
    </section>
  );
}

export interface LegendItem {
  label: string;
  color: string;
  /** line, square (bars and areas), or a glyph for statuses (never color alone). */
  kind?: "line" | "square";
  glyph?: string;
}

export function Legend({ items }: { items: LegendItem[] }) {
  return (
    <ul className="adm-legend">
      {items.map((item) => (
        <li key={item.label}>
          {item.glyph ? (
            <span className="adm-glyph" style={{ background: item.color }} aria-hidden="true">
              {item.glyph}
            </span>
          ) : (
            <span className={item.kind === "line" ? "adm-key-line" : "adm-key-square"} style={{ background: item.color }} aria-hidden="true" />
          )}
          {item.label}
        </li>
      ))}
    </ul>
  );
}

// -------------------------------------------------------------------------------- numbers

/** A round maximum at or above `value`, even, so the middle gridline is a whole number. */
export function niceMax(value: number): number {
  if (value <= 4) return 4;
  const pow = 10 ** Math.floor(Math.log10(value));
  const n = value / pow;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * pow;
}

/** "2026-11-09" as "9.11". */
export const shortDay = (day: string): string => `${Number(day.slice(8))}.${day.slice(5, 7)}`;

/** A column with a 4px rounded data end and a square baseline. */
function columnPath(x: number, top: number, width: number, base: number): string {
  const height = base - top;
  const r = Math.min(4, width / 2, height / 2);
  if (height <= 0) return "";
  return `M${x} ${base} V${top + r} Q${x} ${top} ${x + r} ${top} H${x + width - r} Q${x + width} ${top} ${x + width} ${top + r} V${base} Z`;
}

// -------------------------------------------------------------------------------- sparkline

/** Fourteen days of one account at a glance: a 2px line and an end dot, no axes. */
export function Sparkline({ values, label }: { values: number[]; label: string }) {
  const w = 92;
  const h = 26;
  const pad = 3;
  const max = Math.max(1, ...values);
  const step = values.length > 1 ? (w - pad * 2) / (values.length - 1) : 0;
  const points = values.map((v, i) => [pad + i * step, h - pad - (v / max) * (h - pad * 2)] as const);
  const path = points.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)} ${y.toFixed(1)}`).join(" ");
  const last = points[points.length - 1];
  const flat = values.every((v) => v === 0);
  return (
    <svg className={`adm-spark ${flat ? "is-flat" : ""}`} viewBox={`0 0 ${w} ${h}`} width={w} height={h} role="img" aria-label={label}>
      <path d={path} className="adm-spark-line" />
      {last ? <circle cx={last[0]} cy={last[1]} r="3" className="adm-spark-dot" /> : null}
    </svg>
  );
}

// -------------------------------------------------------------------------------- line + columns over days

export interface DayPoint {
  day: string;
  /** The line. */
  active: number;
  /** The columns; null when the account list isn't available. */
  fresh: number | null;
}

/** Accounts using Doddy each day (the line) and new accounts (the columns), one axis, one tooltip for both. */
export function ActiveChart({ points }: { points: DayPoint[] }) {
  const { t } = useI18n();
  const tip = useTooltip();
  const [at, setAt] = useState<number | null>(null);
  const W = 760;
  const H = 300;
  const L = 36;
  const R = 44;
  const T = 14;
  const B = 28;
  const n = points.length;
  const max = niceMax(Math.max(1, ...points.map((p) => Math.max(p.active, p.fresh ?? 0))));
  const band = (W - L - R) / Math.max(n, 1);
  const x = (i: number) => L + band * (i + 0.5);
  const y = (v: number) => T + (H - T - B) * (1 - v / max);
  const base = y(0);
  const line = points.map((p, i) => `${i ? "L" : "M"}${x(i).toFixed(1)} ${y(p.active).toFixed(1)}`).join(" ");
  const area = n > 0 ? `${line} L${x(n - 1).toFixed(1)} ${base} L${x(0).toFixed(1)} ${base} Z` : "";
  const barWidth = Math.min(Math.max(band * 0.5, 2), 20);
  const labelEvery = Math.max(1, Math.ceil(n / 8));
  const last = points[n - 1];

  const indexFrom = (event: PointerEvent<SVGRectElement>) => {
    const box = event.currentTarget.getBoundingClientRect();
    const ratio = (event.clientX - box.left) / box.width;
    return Math.min(n - 1, Math.max(0, Math.floor(ratio * n)));
  };
  const describe = (i: number) => {
    const p = points[i]!;
    return (
      <>
        <div className="adm-tip-date">{p.day}</div>
        <TipRow color="var(--adm-line)" value={p.active} label={t("admin.legend.active")} />
        {p.fresh !== null ? <TipRow color="var(--adm-new)" value={p.fresh} label={t("admin.legend.new")} square /> : null}
      </>
    );
  };
  const onKey = (event: KeyboardEvent<SVGSVGElement>) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    const next = Math.min(n - 1, Math.max(0, (at ?? n - 1) + (event.key === "ArrowRight" ? 1 : -1)));
    setAt(next);
    const box = event.currentTarget.getBoundingClientRect();
    tip.show({ clientX: box.left + (x(next) / W) * box.width, clientY: box.top + (y(points[next]!.active) / H) * box.height }, describe(next));
  };

  return (
    <div className="adm-chart" ref={tip.ref} onPointerLeave={() => (setAt(null), tip.hide())}>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="adm-svg"
        role="img"
        tabIndex={0}
        aria-label={`${t("admin.chart.active.title")}. ${t("admin.chart.active.sub")}`}
        onKeyDown={onKey}
        onBlur={() => (setAt(null), tip.hide())}
      >
        {[0, max / 2, max].map((tick) => (
          <g key={tick}>
            <line x1={L} x2={W - R} y1={y(tick)} y2={y(tick)} className="adm-grid" />
            <text x={L - 8} y={y(tick) + 4} textAnchor="end" className="adm-axis">{tick}</text>
          </g>
        ))}
        {points.map((p, i) =>
          p.fresh ? <path key={p.day} d={columnPath(x(i) - barWidth / 2, y(p.fresh), barWidth, base)} className="adm-new" /> : null,
        )}
        <path d={area} className="adm-area" />
        <path d={line} className="adm-line" />
        {points.map((p, i) =>
          (i % labelEvery === 0 && n - 1 - i >= labelEvery) || i === n - 1 ? (
            <text key={p.day} x={x(i)} y={H - 8} textAnchor="middle" className="adm-axis">{shortDay(p.day)}</text>
          ) : null,
        )}
        {last ? (
          <g>
            <circle cx={x(n - 1)} cy={y(last.active)} r="5" className="adm-dot" />
            <text x={x(n - 1) + 10} y={y(last.active) + 4} className="adm-end-label">{last.active}</text>
          </g>
        ) : null}
        {at !== null ? (
          <g>
            <line x1={x(at)} x2={x(at)} y1={T} y2={base} className="adm-cross" />
            <circle cx={x(at)} cy={y(points[at]!.active)} r="5" className="adm-dot" />
          </g>
        ) : null}
        <rect
          x={L}
          y={T}
          width={W - L - R}
          height={H - T - B}
          fill="transparent"
          onPointerMove={(event) => {
            const i = indexFrom(event);
            setAt(i);
            tip.show(event, describe(i));
          }}
        />
      </svg>
      {tip.box}
    </div>
  );
}

// -------------------------------------------------------------------------------- heatmap

/** Conversations by weekday (rows, Monday first) and hour (columns): one hue, light to dark. */
export function Heatmap({ grid }: { grid: number[][] }) {
  const { t } = useI18n();
  const tip = useTooltip();
  const cell = 24;
  const gap = 2;
  const left = 30;
  const top = 18;
  const W = left + 24 * (cell + gap);
  const H = top + 7 * (cell + gap);
  const max = Math.max(1, ...grid.flat());
  const [hot, setHot] = useState<string | null>(null);
  return (
    <div className="adm-chart" ref={tip.ref} onPointerLeave={() => (setHot(null), tip.hide())}>
      <svg viewBox={`0 0 ${W} ${H}`} className="adm-svg" role="img" aria-label={t("admin.conv.heat.title")}>
        {Array.from({ length: 24 }, (_, h) =>
          h % 3 === 0 ? (
            <text key={h} x={left + h * (cell + gap) + cell / 2} y={11} textAnchor="middle" className="adm-axis">{h}</text>
          ) : null,
        )}
        {grid.map((row, d) => (
          <g key={d}>
            <text x={left - 6} y={top + d * (cell + gap) + cell / 2 + 4} textAnchor="end" className="adm-axis">{t(`admin.weekday.${d}` as "admin.weekday.0")}</text>
            {row.map((n, h) => {
              const id = `${d}-${h}`;
              return (
                <rect
                  key={h}
                  x={left + h * (cell + gap)}
                  y={top + d * (cell + gap)}
                  width={cell}
                  height={cell}
                  rx="4"
                  className={`adm-cell ${hot === id ? "is-hot" : ""}`}
                  style={{ ["--i" as string]: n === 0 ? 0 : 0.14 + 0.86 * (n / max) } as CSSProperties}
                  onPointerMove={(event) => {
                    setHot(id);
                    tip.show(event, <div className="adm-tip-row"><strong>{t("admin.conv.heat.tip", { day: t(`admin.weekday.${d}` as "admin.weekday.0"), hour: h, n })}</strong></div>);
                  }}
                />
              );
            })}
          </g>
        ))}
      </svg>
      <div className="adm-scale" aria-hidden="true">
        <span>{t("admin.conv.less")}</span>
        <span className="adm-scale-bar" />
        <span>{t("admin.conv.more")}</span>
      </div>
      {tip.box}
    </div>
  );
}

/** The heatmap as numbers: weekdays down, hours across. */
export function HeatTable({ grid }: { grid: number[][] }) {
  const { t } = useI18n();
  return (
    <table className="adm-table is-compact">
      <thead>
        <tr>
          <th scope="col" />
          {Array.from({ length: 24 }, (_, h) => (
            <th key={h} scope="col">{h}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {grid.map((row, d) => (
          <tr key={d}>
            <th scope="row">{t(`admin.weekday.${d}` as "admin.weekday.0")}</th>
            {row.map((n, h) => (
              <td key={h}>{n || ""}</td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// -------------------------------------------------------------------------------- horizontal bars

export interface BarRow {
  key: string;
  label: string;
  value: number;
  /** A CSS color; defaults to the dashboard's one-series color. */
  color?: string;
  note?: string;
}

/** A label, a bar up to 20px thick with a rounded tip, and the value at the tip. */
export function HBars({ rows, max }: { rows: BarRow[]; max?: number }) {
  const top = max ?? Math.max(1, ...rows.map((r) => r.value));
  return (
    <ul className="adm-hbars">
      {rows.map((row) => (
        <li key={row.key}>
          <span className="adm-hbar-label">{row.label}</span>
          <span className="adm-hbar-track">
            <span className="adm-hbar-fill" style={{ width: `${Math.max(row.value > 0 ? 1.5 : 0, (row.value / top) * 100)}%`, background: row.color ?? "var(--adm-line)" }} />
          </span>
          <span className="adm-hbar-value">
            <strong>{row.value}</strong>
            {row.note ? <span>{row.note}</span> : null}
          </span>
        </li>
      ))}
    </ul>
  );
}

// -------------------------------------------------------------------------------- stacked bar

export interface Segment {
  key: string;
  label: string;
  value: number;
  color: string;
  glyph?: string;
}

/** One bar cut into segments with a 2px surface gap; its width is `value / scale`, so bars in a list compare. */
export function StackedBar({ segments, scale, caption }: { segments: Segment[]; scale?: number; caption: string }) {
  const tip = useTooltip();
  const total = segments.reduce((sum, s) => sum + s.value, 0);
  const full = scale ?? Math.max(1, total);
  return (
    <div className="adm-stack-frame" ref={tip.ref} onPointerLeave={tip.hide}>
      <div className="adm-stack" style={{ width: `${Math.max(total > 0 ? 2 : 0, (total / full) * 100)}%` }} role="img" aria-label={caption}>
        {segments
          .filter((s) => s.value > 0)
          .map((s) => (
            <span
              key={s.key}
              className="adm-seg"
              style={{ flexGrow: s.value, background: s.color }}
              onPointerMove={(event) => tip.show(event, <TipRow color={s.color} value={s.value} label={s.label} square />)}
            >
              {s.glyph && s.value / Math.max(total, 1) > 0.12 ? <i aria-hidden="true">{s.glyph}</i> : null}
            </span>
          ))}
      </div>
      {tip.box}
    </div>
  );
}

// -------------------------------------------------------------------------------- columns

/** One series of columns over days (new accounts, one account's conversations): 4px rounded tips on a square baseline. */
export function ColumnChart({ points, label, color }: { points: { day: string; value: number }[]; label: string; color?: string }) {
  const tip = useTooltip();
  const [at, setAt] = useState<number | null>(null);
  const W = 760;
  const H = 200;
  const L = 36;
  const R = 12;
  const T = 12;
  const B = 28;
  const n = points.length;
  const max = niceMax(Math.max(1, ...points.map((p) => p.value)));
  const band = (W - L - R) / Math.max(n, 1);
  const x = (i: number) => L + band * (i + 0.5);
  const y = (v: number) => T + (H - T - B) * (1 - v / max);
  const base = y(0);
  const barWidth = Math.min(Math.max(band * 0.6, 2), 22);
  const labelEvery = Math.max(1, Math.ceil(n / 8));
  const fill = color ?? "var(--adm-line)";
  const describe = (i: number) => (
    <>
      <div className="adm-tip-date">{points[i]!.day}</div>
      <TipRow color={fill} value={points[i]!.value} label={label} square />
    </>
  );
  const onKey = (event: KeyboardEvent<SVGSVGElement>) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    const next = Math.min(n - 1, Math.max(0, (at ?? n - 1) + (event.key === "ArrowRight" ? 1 : -1)));
    setAt(next);
    const box = event.currentTarget.getBoundingClientRect();
    tip.show({ clientX: box.left + (x(next) / W) * box.width, clientY: box.top + (y(points[next]!.value) / H) * box.height }, describe(next));
  };
  return (
    <div className="adm-chart" ref={tip.ref} onPointerLeave={() => (setAt(null), tip.hide())}>
      <svg viewBox={`0 0 ${W} ${H}`} className="adm-svg" role="img" tabIndex={0} aria-label={label} onKeyDown={onKey} onBlur={() => (setAt(null), tip.hide())}>
        {[0, max / 2, max].map((tick) => (
          <g key={tick}>
            <line x1={L} x2={W - R} y1={y(tick)} y2={y(tick)} className="adm-grid" />
            <text x={L - 8} y={y(tick) + 4} textAnchor="end" className="adm-axis">{tick}</text>
          </g>
        ))}
        {points.map((p, i) => (
          <path key={p.day} d={columnPath(x(i) - barWidth / 2, y(p.value), barWidth, base)} style={{ fill }} opacity={at === i ? 1 : 0.85} />
        ))}
        {points.map((p, i) =>
          (i % labelEvery === 0 && n - 1 - i >= labelEvery) || i === n - 1 ? (
            <text key={p.day} x={x(i)} y={H - 8} textAnchor="middle" className="adm-axis">{shortDay(p.day)}</text>
          ) : null,
        )}
        <rect
          x={L}
          y={T}
          width={W - L - R}
          height={H - T - B}
          fill="transparent"
          onPointerMove={(event: PointerEvent<SVGRectElement>) => {
            const box = event.currentTarget.getBoundingClientRect();
            const i = Math.min(n - 1, Math.max(0, Math.floor(((event.clientX - box.left) / box.width) * n)));
            setAt(i);
            tip.show(event, describe(i));
          }}
        />
      </svg>
      {tip.box}
    </div>
  );
}

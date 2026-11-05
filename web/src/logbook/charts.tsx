import {
  createContext,
  type ReactNode,
  type RefObject,
  useCallback,
  useContext,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";

/**
 * The charts Logbook draws, by hand in SVG and HTML (no chart library). Rules from the dataviz
 * method: one axis, thin marks (columns at most 24 px wide, rounded data end), a 2 px gap between
 * stacked parts, labels only on the busiest and the latest, a table twin for every chart
 * ("Show as tables"), and the same tooltip on keyboard focus as on hover. Every label is text
 * React sets, never markup. Sizes are SVG attributes or CSSOM, so the page's CSP (no inline
 * styles in markup) is not touched.
 */

export type TipRow = [label: string, value: string | number];

// ---------------------------------------------------------------- view (charts or tables)

const ViewContext = createContext<{ tables: boolean }>({ tables: false });
export const ViewProvider = ViewContext.Provider;
export const useView = () => useContext(ViewContext);

// ---------------------------------------------------------------- tooltip

interface TipState {
  target: Element;
  title: string;
  rows: TipRow[];
  x: number | null;
  y: number | null;
}
interface TipApi {
  show(target: Element, title: string, rows: TipRow[], at?: { clientX: number; clientY: number } | null): void;
  hide(target: Element): void;
}
const TipContext = createContext<TipApi | null>(null);

export function TipProvider({ children }: { children: ReactNode }) {
  const [tip, setTip] = useState<TipState | null>(null);
  const box = useRef<HTMLDivElement>(null);
  const api = useMemo<TipApi>(
    () => ({
      show: (target, title, rows, at) => setTip({ target, title, rows, x: at?.clientX ?? null, y: at?.clientY ?? null }),
      hide: (target) => setTip((current) => (current && current.target === target ? null : current)),
    }),
    [],
  );

  useLayoutEffect(() => {
    const el = box.current;
    if (!tip || !el) return;
    const rect = tip.target.getBoundingClientRect();
    const w = el.offsetWidth;
    const h = el.offsetHeight;
    let x = tip.x !== null ? tip.x + 14 : rect.left + rect.width / 2 - w / 2;
    let y = tip.y !== null ? tip.y - h - 14 : rect.top - h - 10;
    x = Math.max(8, Math.min(window.innerWidth - w - 8, x));
    if (y < 8) y = (tip.y ?? rect.bottom) + 16;
    el.style.left = `${x}px`;
    el.style.top = `${y}px`;
  }, [tip]);

  // A scroll leaves the tooltip behind; drop it.
  useLayoutEffect(() => {
    const drop = () => setTip(null);
    window.addEventListener("scroll", drop, { passive: true });
    return () => window.removeEventListener("scroll", drop);
  }, []);

  return (
    <TipContext.Provider value={api}>
      {children}
      {tip ? (
        <div className="lb-tip" role="tooltip" ref={box}>
          <strong>{tip.title}</strong>
          {tip.rows.map(([label, value]) => (
            <div className="lb-tip-row" key={label}>
              <span>{label}</span>
              <b>{value}</b>
            </div>
          ))}
        </div>
      ) : null}
    </TipContext.Provider>
  );
}

/** Pointer and keyboard handlers that show a tooltip for the element they are spread on. */
function useTipProps() {
  const api = useContext(TipContext);
  return useCallback(
    (title: string, rows: TipRow[]) => {
      if (!api) return {};
      return {
        onPointerMove: (e: React.PointerEvent<Element>) => api.show(e.currentTarget, title, rows, e),
        onPointerLeave: (e: React.PointerEvent<Element>) => api.hide(e.currentTarget),
        onClick: (e: React.MouseEvent<Element>) => api.show(e.currentTarget, title, rows, e),
        onFocus: (e: React.FocusEvent<Element>) => api.show(e.currentTarget, title, rows, null),
        onBlur: (e: React.FocusEvent<Element>) => api.hide(e.currentTarget),
      };
    },
    [api],
  );
}

const readout = (label: string, rows: TipRow[]) => `${label}: ${rows.map(([k, v]) => `${k} ${v}`).join(", ")}`;

// ---------------------------------------------------------------- sizing

/** The width of an element, kept up to date. Before it is measured (or without layout, as in tests) `fallback`. */
function useWidth<T extends HTMLElement>(fallback = 560): [RefObject<T | null>, number] {
  const ref = useRef<T>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    setWidth(Math.round(el.clientWidth));
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver((entries) => {
      const next = Math.round(entries[0]?.contentRect.width ?? 0);
      setWidth((current) => (Math.abs(next - current) < 8 ? current : next));
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);
  return [ref, Math.max(280, width || fallback)];
}

// ---------------------------------------------------------------- icons

const SYMBOLS: Record<string, ReactNode> = {
  note: <path d="M6 3.5h9l3.5 3.5v13.5H6zM14.5 3.5V7.5h4M9 12h6M9 15.5h6" />,
  clock: <path d="M12 3.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17zM12 7.5V12l3 2" />,
  list: <path d="M9.5 7h10M9.5 12h10M9.5 17h10M4.5 7l1 1 2-2M4.5 12l1 1 2-2M5.8 16a1 1 0 1 0 0 2 1 1 0 0 0 0-2z" />,
  search: <path d="M10.5 4.5a6 6 0 1 0 0 12 6 6 0 0 0 0-12zM15 15l5 5" />,
  mail: <path d="M5.5 5.5h13a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2v-9a2 2 0 0 1 2-2zM4 7l8 6 8-6" />,
  hand: <path d="M4 14.5h3.5l3.8 2.6c.7.5 1.7.4 2.3-.2l5.6-5.6a1.4 1.4 0 0 0-2-2l-3.4 3.4M4 14.5V20h3.5M9 11.5l2.6-2.6c.6-.6 1.5-.6 2.1 0l1.1 1.1" />,
  translate: <path d="M3.5 6h9M8 4v2c0 4-2.2 7-4.5 8.5M6 9.5c1.2 2 3 3.6 5 4.5M12.5 20l4-9 4 9M14 17h5" />,
  dots: <path d="M6 12h.01M12 12h.01M18 12h.01" />,
  check: <path d="M5 12.5l4.5 4.5L19 7.5" />,
  question: <path d="M9 9.2a3 3 0 1 1 4.5 2.6c-.9.5-1.5 1.2-1.5 2.2v.5M12 17.6v.01" />,
  cross: <path d="M6.5 6.5l11 11M17.5 6.5l-11 11" />,
  no: <path d="M12 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16zM8 12h8" />,
  left: <path d="M14.5 6l-6 6 6 6" />,
  right: <path d="M9.5 6l6 6-6 6" />,
};

export function Icon({ name, className }: { name: string; className?: string }) {
  return (
    <svg className={`lb-ico ${className ?? ""}`} viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      {SYMBOLS[name] ?? null}
    </svg>
  );
}

// ---------------------------------------------------------------- tables

export function DataTable({ caption, head, rows }: { caption: string; head: string[]; rows: (string | number)[][] }) {
  return (
    <div className="lb-tview">
      <table>
        <caption>{caption}</caption>
        <thead>
          <tr>
            {head.map((h, i) => (
              <th key={`${h}-${i}`} scope="col" className={i ? "lb-n" : undefined}>
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, r) => (
            <tr key={r}>
              {row.map((cell, i) =>
                i === 0 ? (
                  <th key={i} scope="row">
                    {cell}
                  </th>
                ) : (
                  <td key={i} className="lb-n">
                    {cell}
                  </td>
                ),
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ---------------------------------------------------------------- horizontal bars

export interface BarRow {
  key: string;
  label: string;
  icon?: string;
  value: number;
  tip?: TipRow[];
}

export function HBars({ rows, compact = false, caption, head, valueHead }: { rows: BarRow[]; compact?: boolean; caption: string; head: string; valueHead: string }) {
  const { tables } = useView();
  const tipProps = useTipProps();
  const max = Math.max(1, ...rows.map((r) => r.value));
  if (tables) return <DataTable caption={caption} head={[head, valueHead]} rows={rows.map((r) => [r.label, r.value])} />;
  return (
    <div className={`lb-hbars ${compact ? "lb-compact" : ""}`}>
      {rows.map((r) => (
        <div
          className="lb-hrow"
          key={r.key}
          {...(r.tip ? { tabIndex: 0, "aria-label": readout(`${r.label} ${r.value}`, r.tip), ...tipProps(r.label, r.tip) } : {})}
        >
          <div className="lb-hlabel">
            {r.icon ? <Icon name={r.icon} /> : null}
            <span>{r.label}</span>
          </div>
          <div className="lb-htrack">
            <div className={`lb-hfill ${r.value ? "" : "lb-zero"}`} style={{ width: `${(r.value / max) * 100}%` }} />
          </div>
          <div className="lb-hval">{r.value}</div>
        </div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------- columns

export interface ColumnItem {
  key: string;
  label: string;
  /** The label under the column when there is room. */
  short: string;
  value: number;
  /** Stacked parts, bottom first; each part's class picks its colour (lb-f1 … lb-f4). */
  parts?: { cls: string; value: number }[];
  tip: TipRow[];
  /** The values after the label in this column's row of the table. */
  cells: (string | number)[];
}

function niceMax(v: number): number {
  if (v <= 4) return 4;
  for (const step of [5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 80, 100, 150, 200]) if (v <= step) return step;
  return Math.ceil(v / 50) * 50;
}

export function Columns({
  items,
  height = 200,
  valueAll = false,
  aria,
  head,
}: {
  items: ColumnItem[];
  height?: number;
  valueAll?: boolean;
  aria: string;
  /** The table's column titles: the label's, then one per cell. */
  head: string[];
}) {
  const { tables } = useView();
  const tipProps = useTipProps();
  const [ref, width] = useWidth<HTMLDivElement>();
  const pad = { t: 22, r: 8, b: 26, l: 30 };
  const pw = width - pad.l - pad.r;
  const ph = height - pad.t - pad.b;
  const maxV = niceMax(Math.max(1, ...items.map((i) => i.value)));
  const band = pw / Math.max(1, items.length);
  const bw = Math.max(3, Math.min(24, band * 0.62));
  const y = (v: number) => pad.t + ph - (v / maxV) * ph;
  const busiest = items.reduce((best, it, i) => (it.value > (items[best]?.value ?? -1) ? i : best), 0);
  const labelEvery = Math.ceil(items.length / Math.max(2, Math.floor(pw / 64)));

  return (
    <div className="lb-chart" ref={ref}>
      {tables ? (
        <DataTable caption={aria} head={head} rows={items.map((it) => [it.label, ...it.cells])} />
      ) : (
        <svg viewBox={`0 0 ${width} ${height}`} width={width} height={height} role="group" aria-label={aria}>
          {[0, maxV / 2, maxV].map((g) => (
            <g key={g}>
              <line className={g === 0 ? "lb-base" : "lb-grid"} x1={pad.l} x2={width - pad.r} y1={y(g)} y2={y(g)} />
              <text x={pad.l - 8} y={y(g) + 4} textAnchor="end">
                {Math.round(g)}
              </text>
            </g>
          ))}
          {items.map((it, i) => {
            const cx = pad.l + band * i + band / 2;
            const x0 = cx - bw / 2;
            const parts = (it.parts ?? [{ cls: "lb-mark", value: it.value }]).filter((p) => p.value > 0);
            let base = 0;
            const shapes = parts.map((p, pi) => {
              const top = base + p.value;
              const gap = pi > 0 ? 2 : 0;
              const y0 = y(base);
              const y1 = y(top);
              base = top;
              const h = Math.max(0, y0 - y1 - gap);
              if (h <= 0) return null;
              if (pi === parts.length - 1) {
                const r = Math.min(4, h, bw / 2);
                const d = `M${x0},${y0 - gap} V${y1 + r} Q${x0},${y1} ${x0 + r},${y1} H${x0 + bw - r} Q${x0 + bw},${y1} ${x0 + bw},${y1 + r} V${y0 - gap} Z`;
                return <path key={pi} className={p.cls} d={d} />;
              }
              return <rect key={pi} className={p.cls} x={x0} y={y1} width={bw} height={h} />;
            });
            const showValue = (valueAll || i === busiest || i === items.length - 1) && (it.value > 0 || valueAll);
            const showLabel = (i % labelEvery === 0 && items.length - 1 - i >= labelEvery * 0.6) || i === items.length - 1;
            return (
              <g className="lb-col" key={it.key}>
                <rect className="lb-col-hl" x={pad.l + band * i + 1} y={pad.t - 6} width={Math.max(1, band - 2)} height={ph + 6} rx={6} />
                {shapes}
                {showValue ? (
                  <text className="lb-val" x={cx} y={y(it.value) - 6} textAnchor="middle">
                    {it.value}
                  </text>
                ) : null}
                {showLabel ? (
                  <text x={cx} y={height - 8} textAnchor="middle">
                    {it.short}
                  </text>
                ) : null}
                <rect
                  className="lb-hit"
                  x={pad.l + band * i}
                  y={pad.t - 6}
                  width={band}
                  height={ph + 6}
                  tabIndex={0}
                  aria-label={readout(it.label, it.tip)}
                  {...tipProps(it.label, it.tip)}
                />
              </g>
            );
          })}
        </svg>
      )}
    </div>
  );
}

// ---------------------------------------------------------------- dots by hour

export function DotStrip({
  byHour,
  aria,
  caption,
  head,
  countLabel,
  hourText,
  hourRangeText,
}: {
  byHour: number[];
  aria: string;
  caption: string;
  head: [string, string];
  countLabel: string;
  hourText: (hour: number) => string;
  hourRangeText: (hour: number) => string;
}) {
  const { tables } = useView();
  const tipProps = useTipProps();
  const [ref, width] = useWidth<HTMLDivElement>();
  const firstHour = byHour.slice(0, 6).some((v) => v > 0) ? 0 : 6;
  const hours = Array.from({ length: 24 - firstHour }, (_, i) => firstHour + i);
  const maxStack = Math.max(6, ...hours.map((h) => byHour[h] ?? 0));
  const pad = { t: 12, r: 10, b: 28, l: 10 };
  const band = (width - pad.l - pad.r) / hours.length;
  const r = Math.max(3.5, Math.min(7, band * 0.34));
  const step = r * 2 + 3;
  const height = pad.t + maxStack * step + pad.b;
  const baseY = height - pad.b;
  return (
    <div className="lb-chart" ref={ref}>
      {tables ? (
        <DataTable caption={caption} head={head} rows={hours.filter((h) => (byHour[h] ?? 0) > 0).map((h) => [hourText(h), byHour[h] ?? 0])} />
      ) : (
        <svg viewBox={`0 0 ${width} ${height}`} width={width} height={height} role="group" aria-label={aria}>
          <line className="lb-base" x1={pad.l} x2={width - pad.r} y1={baseY + 4} y2={baseY + 4} />
          {hours.map((h, i) => {
            const cx = pad.l + band * i + band / 2;
            const n = byHour[h] ?? 0;
            const rows: TipRow[] = [[countLabel, n]];
            return (
              <g className="lb-col" key={h}>
                <rect className="lb-col-hl" x={pad.l + band * i + 1} y={pad.t - 4} width={band - 2} height={baseY - pad.t + 8} rx={6} />
                {Array.from({ length: n }, (_, k) => (
                  <circle key={k} className="lb-dot" cx={cx} cy={baseY - r - k * step} r={r} />
                ))}
                {h % 3 === 0 ? (
                  <text x={cx - band / 2} y={height - 8} textAnchor="middle">
                    {hourText(h)}
                  </text>
                ) : null}
                <rect
                  className="lb-hit"
                  x={pad.l + band * i}
                  y={pad.t - 4}
                  width={band}
                  height={baseY - pad.t + 8}
                  tabIndex={0}
                  aria-label={readout(hourRangeText(h), rows)}
                  {...tipProps(hourRangeText(h), rows)}
                />
              </g>
            );
          })}
        </svg>
      )}
    </div>
  );
}

// ---------------------------------------------------------------- heatmap

export function Heatmap({
  grid,
  aria,
  caption,
  head,
  countLabel,
  noneLabel,
  maxLabel,
  weekdayShort,
  weekdayLong,
  hourText,
  hourRangeText,
}: {
  grid: number[][];
  aria: string;
  caption: string;
  head: [string, string];
  countLabel: string;
  noneLabel: string;
  maxLabel: (n: number) => string;
  weekdayShort: (index: number) => string;
  weekdayLong: (index: number) => string;
  hourText: (hour: number) => string;
  hourRangeText: (hour: number) => string;
}) {
  const { tables } = useView();
  const tipProps = useTipProps();
  const [ref, width] = useWidth<HTMLDivElement>(520);
  const max = Math.max(1, ...grid.flat());
  const pad = { t: 4, r: 4, b: 22, l: 46 };
  const cw = (width - pad.l - pad.r) / 24;
  const ch = Math.max(16, Math.min(30, cw * 1.3));
  const height = pad.t + ch * 7 + pad.b;
  const shade = (v: number) => (v === 0 ? 0 : Math.min(6, 1 + Math.floor(((v - 1) / Math.max(1, max - 1)) * 5.999)));
  const rows: (string | number)[][] = [];
  grid.forEach((row, d) => row.forEach((v, h) => v > 0 && rows.push([`${weekdayLong(d)} ${hourText(h)}`, v])));

  return (
    <div className="lb-chart" ref={ref}>
      {tables ? (
        <DataTable caption={caption} head={head} rows={rows} />
      ) : (
        <>
          <svg viewBox={`0 0 ${width} ${height}`} width={width} height={height} role="group" aria-label={aria}>
            {grid.map((row, d) => (
              <g key={d}>
                <text x={pad.l - 8} y={pad.t + ch * d + ch / 2 + 4} textAnchor="end">
                  {weekdayShort(d)}
                </text>
                {row.map((v, h) => (
                  <rect
                    key={h}
                    className={`lb-cell lb-q${shade(v)}`}
                    x={pad.l + cw * h}
                    y={pad.t + ch * d}
                    width={cw}
                    height={ch}
                    rx={3}
                    {...tipProps(`${weekdayLong(d)}, ${hourRangeText(h)}`, [[countLabel, v]])}
                  />
                ))}
              </g>
            ))}
            {[0, 6, 12, 18].map((h) => (
              <text key={h} x={pad.l + cw * h} y={height - 6}>
                {hourText(h)}
              </text>
            ))}
          </svg>
          <ul className="lb-legend lb-heat-legend" aria-hidden="true">
            <li>
              <span className="lb-key lb-k0" />
              <span>{noneLabel}</span>
            </li>
            <li>
              <span>1</span>
              {[1, 2, 3, 4, 5, 6].map((i) => (
                <span key={i} className={`lb-key lb-k${i}`} />
              ))}
              <span>{maxLabel(max)}</span>
            </li>
          </ul>
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------- stacked bar and legend

export function StackBar({ parts, aria }: { parts: { cls: string; value: number }[]; aria: string }) {
  return (
    <div className="lb-stack-wrap">
      <div className="lb-stack" role="img" aria-label={aria}>
        {parts
          .filter((p) => p.value > 0)
          .map((p) => (
            <span key={p.cls} className={p.cls} style={{ flexGrow: p.value }} />
          ))}
      </div>
    </div>
  );
}

export function Facts({ items }: { items: { label: string; value: string | number; unit?: string }[] }) {
  return (
    <dl className="lb-facts">
      {items.map((it) => (
        <div key={it.label}>
          <dt>{it.label}</dt>
          <dd>
            {it.value}
            {it.unit ? <small>{it.unit}</small> : null}
          </dd>
        </div>
      ))}
    </dl>
  );
}

/** The sprite for the icons is inline in Icon; this wrapper only exists so a page can place one tip root. */
export function ChartRoot({ children, tables }: { children: ReactNode; tables: boolean }) {
  return (
    <ViewProvider value={{ tables }}>
      <TipProvider>{children}</TipProvider>
    </ViewProvider>
  );
}

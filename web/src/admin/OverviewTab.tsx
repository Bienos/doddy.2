import { useState } from "react";
import { useI18n } from "../i18n/i18n.js";
import type { OwnerAccount, OwnerOverview } from "../owner/schema.js";
import { toolRows } from "../owner/schema.js";
import { ActiveChart, ChartCard, HBars, Legend, StackedBar } from "./charts.js";
import { type Insight, type Tab, type UserFilter, insights, minutesOf, percent, sumOutcomes } from "./logic.js";
import { Kpi, useMethodLabel, useOutcomes } from "./parts.js";

type Go = (tab: Tab, filter?: UserFilter) => void;

/** The first screen: how many people use Doddy, whether it works, and what needs a look. */
export function OverviewTab({ o, accounts, go }: { o: OwnerOverview; accounts: OwnerAccount[]; go: Go }) {
  const { t } = useI18n();
  const methodLabel = useMethodLabel();
  const base = o.accounts.total ?? o.logbook.sending;
  const totals = o.logbook.totals;
  const tools = sumOutcomes(totals.tools);
  const toolUses = tools.done + tools.declined + tools.unsure + tools.failed;
  const trouble = tools.failed + tools.unsure;
  const methods = Object.entries(o.accounts.byMethod).sort((a, b) => b[1] - a[1]);
  const { joined, activated } = o.activation;
  const funnel = [
    { key: "all", label: o.accounts.total === null ? t("admin.funnel.sending") : t("admin.funnel.all"), value: base },
    { key: "month", label: t("admin.funnel.month"), value: o.engagement.month },
    { key: "week", label: t("admin.funnel.week"), value: o.engagement.week },
    { key: "today", label: t("admin.funnel.today"), value: o.engagement.today },
  ].map((row) => ({ ...row, note: `${percent(row.value, base)}%` }));
  const points = o.logbook.activeByDay.map((d, i) => ({ day: d.day, active: d.accounts, fresh: o.directory ? (o.accounts.newByDay[i]?.count ?? 0) : null }));
  const top = toolRows(totals.tools).slice(0, 6);

  return (
    <>
      <ul className="adm-kpis" aria-label={t("admin.tab.overview")}>
        <Kpi
          label={t("admin.kpi.accounts")}
          value={o.accounts.total ?? t("admin.kpi.accountsUnknown")}
          hint={
            methods.length > 0
              ? methods.map(([m, n], i) => (
                  <span key={m} className="nowrap">
                    {i > 0 ? " · " : ""}
                    {methodLabel(m)} {n}
                  </span>
                ))
              : undefined
          }
        />
        <Kpi label={t("admin.kpi.today")} value={o.engagement.today} hint={t("admin.kpi.share", { percent: percent(o.engagement.today, base) })} />
        <Kpi label={t("admin.kpi.week")} value={o.engagement.week} hint={t("admin.kpi.share", { percent: percent(o.engagement.week, base) })} />
        <Kpi label={t("admin.kpi.month")} value={o.engagement.month} hint={t("admin.kpi.share", { percent: percent(o.engagement.month, base) })} />
        <Kpi label={t("admin.kpi.conversations")} value={totals.conversations} hint={t("admin.kpi.avgDaily", { n: o.engagement.dailyAverage })} />
        <Kpi label={t("admin.kpi.minutes")} value={minutesOf(totals.seconds)} />
        <Kpi
          label={t("admin.kpi.activation")}
          value={o.directory && joined > 0 ? `${percent(activated, joined)}%` : "—"}
          hint={o.directory && joined > 0 ? t("admin.kpi.activationHint", { activated, joined }) : t("admin.kpi.activationNone")}
        />
        <Kpi
          label={t("admin.kpi.trouble")}
          value={toolUses > 0 ? `${percent(trouble, toolUses)}%` : "—"}
          hint={toolUses > 0 ? t("admin.kpi.troubleHint", { n: trouble, total: toolUses }) : undefined}
        />
      </ul>

      <div className="adm-cols">
        <div className="adm-stack-cards">
          <ChartCard
            title={t("admin.chart.active.title")}
            sub={t("admin.chart.active.sub")}
            legend={
              <Legend
                items={[
                  { label: t("admin.legend.active"), color: "var(--adm-line)", kind: "line" },
                  ...(o.directory ? [{ label: t("admin.legend.new"), color: "var(--adm-new)", kind: "square" as const }] : []),
                ]}
              />
            }
            chart={<ActiveChart points={points} />}
            table={
              <table className="adm-table">
                <thead>
                  <tr>
                    <th scope="col">{t("admin.col.day")}</th>
                    <th scope="col" className="num">{t("admin.legend.active")}</th>
                    {o.directory ? <th scope="col" className="num">{t("admin.legend.new")}</th> : null}
                  </tr>
                </thead>
                <tbody>
                  {[...points].reverse().map((p) => (
                    <tr key={p.day}>
                      <td>{p.day}</td>
                      <td className="num">{p.active}</td>
                      {o.directory ? <td className="num">{p.fresh}</td> : null}
                    </tr>
                  ))}
                </tbody>
              </table>
            }
          />
          <section className="adm-card">
            <header className="adm-card-head">
              <h2>{t("admin.top.title")}</h2>
              <button type="button" className="adm-ghost" onClick={() => go("tools")}>{t("admin.top.seeAll")}</button>
            </header>
            {top.length === 0 ? <p className="adm-empty">{t("admin.tools.none")}</p> : <TopTools rows={top} />}
          </section>
        </div>
        <div className="adm-stack-cards">
          <Attention items={insights(o, accounts)} go={go} />
          <section className="adm-card">
            <header className="adm-card-head">
              <h2>{t("admin.funnel.title")}</h2>
            </header>
            <HBars rows={funnel} max={base} />
          </section>
        </div>
      </div>
    </>
  );
}

function TopTools({ rows }: { rows: ReturnType<typeof toolRows> }) {
  const { t } = useI18n();
  const { legend, segments } = useOutcomes();
  const max = Math.max(1, ...rows.map((r) => r.total));
  return (
    <>
      <Legend items={legend} />
      <div>
        {rows.map((row) => (
          <div key={row.tool} className={`adm-tool ${row.failRate >= 0.2 && row.total >= 5 ? "is-warn" : ""}`}>
            <span className="adm-tool-name">{row.tool}</span>
            <StackedBar
              scale={max}
              caption={`${row.tool}: ${t("admin.tools.uses", { n: row.total })}`}
              segments={segments(row)}
            />
            <span className="adm-tool-meta">{t("admin.tools.uses", { n: row.total })}</span>
          </div>
        ))}
      </div>
    </>
  );
}

const LEVEL_GLYPH = { bad: "✕", warn: "!", good: "✓", info: "i" } as const;
const LEVEL_COLOR = { bad: "var(--c-failed)", warn: "var(--c-unsure)", good: "var(--c-done)", info: "var(--c-declined)" } as const;

/** The first few findings; the rest behind one button. */
const SHOWN = 6;

function Attention({ items, go }: { items: Insight[]; go: Go }) {
  const { t } = useI18n();
  const [all, setAll] = useState(false);
  const shown = all ? items : items.slice(0, SHOWN);
  return (
    <section className="adm-card">
      <header className="adm-card-head">
        <h2>{t("admin.attention.title")}</h2>
      </header>
      {items.length === 0 ? (
        <p className="adm-empty">{t("admin.attention.empty")}</p>
      ) : (
        <ul className="adm-attention">
          {shown.map((item) => (
            <li key={item.id}>
              <span className="adm-badge">
                <span className="adm-glyph" style={{ background: LEVEL_COLOR[item.level] }} aria-hidden="true">{LEVEL_GLYPH[item.level]}</span>
                <span className="visually-hidden">{t(`admin.level.${item.level}` as "admin.level.bad")}</span>
              </span>
              <span>{t(item.text, item.values)}</span>
              {item.tab ? (
                <button type="button" className="adm-row-btn" onClick={() => go(item.tab!, item.filter)} aria-label={`${t(item.text, item.values)}: ${t(`admin.tab.${item.tab}` as "admin.tab.users")}`}>
                  →
                </button>
              ) : (
                <span />
              )}
            </li>
          ))}
        </ul>
      )}
      {items.length > SHOWN ? (
        <button type="button" className="adm-ghost adm-more" aria-expanded={all} onClick={() => setAll((v) => !v)}>
          {all ? t("admin.attention.less") : t("admin.attention.more", { n: items.length })}
        </button>
      ) : null}
    </section>
  );
}

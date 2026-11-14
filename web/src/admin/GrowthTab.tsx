import type { ReactNode } from "react";
import { useI18n } from "../i18n/i18n.js";
import type { OwnerOverview } from "../owner/schema.js";
import { ChartCard, ColumnChart, HBars } from "./charts.js";
import { percent, retention, valueRow } from "./logic.js";
import { METHOD_COLOR, useMethodLabel } from "./parts.js";

/** A share 0 to 100, or a dash when there was nothing to divide by. */
const shown = (share: number | null) => (share === null ? "—" : `${share}%`);

/** Who joined, how they sign in, whether they start using Doddy, whether they stay, and whether it works out for them. */
export function GrowthTab({ o }: { o: OwnerOverview }) {
  const { t } = useI18n();
  const methodLabel = useMethodLabel();
  const { joined, activated } = o.activation;
  const methods = Object.entries(o.accounts.byMethod)
    .sort((a, b) => b[1] - a[1])
    .map(([key, value]) => ({ key, label: methodLabel(key), value, color: METHOD_COLOR[key] ?? "var(--c-declined)" }));
  const newPoints = o.accounts.newByDay.map((d) => ({ day: d.day, value: d.count }));

  return (
    <>
      {!o.directory ? <p className="adm-note" role="note">{t("admin.noDirectory")}</p> : null}
      <ValueCard o={o} />
      <div className="adm-cols is-even">
        <ChartCard
          title={t("admin.growth.new.title")}
          chart={<ColumnChart points={newPoints} label={t("admin.legend.new")} color="var(--adm-new)" />}
          table={
            <table className="adm-table">
              <thead><tr><th scope="col">{t("admin.col.day")}</th><th scope="col" className="num">{t("admin.legend.new")}</th></tr></thead>
              <tbody>{[...newPoints].reverse().map((p) => (<tr key={p.day}><td>{p.day}</td><td className="num">{p.value}</td></tr>))}</tbody>
            </table>
          }
        />
        <div className="adm-stack-cards">
          <section className="adm-card">
            <header className="adm-card-head"><h2>{t("admin.growth.methods.title")}</h2></header>
            {methods.length === 0 ? <p className="adm-empty">—</p> : <HBars rows={methods} />}
          </section>
          <section className="adm-card">
            <header className="adm-card-head">
              <div>
                <h2>{t("admin.growth.activation.title")}</h2>
                <p className="adm-sub">{t("admin.growth.activation.sub")}</p>
              </div>
            </header>
            {o.directory && joined > 0 ? (
              <>
                <p className="adm-kpi-value" style={{ margin: "0 0 10px" }}>{percent(activated, joined)}%</p>
                <HBars rows={[{ key: "joined", label: t("admin.legend.new"), value: joined }, { key: "activated", label: t("admin.growth.activated"), value: activated, color: "var(--c-done)" }]} max={joined} />
              </>
            ) : (
              <p className="adm-empty">{t("admin.kpi.activationNone")}</p>
            )}
          </section>
        </div>
      </div>

      <section className="adm-card">
        <header className="adm-card-head">
          <div>
            <h2>{t("admin.growth.cohorts.title")}</h2>
            <p className="adm-sub">{t("admin.growth.cohorts.sub")}</p>
            <p className="adm-sub">{t("admin.growth.w4.note")}</p>
          </div>
        </header>
        {o.cohorts.length === 0 ? (
          <p className="adm-empty">{t("admin.growth.cohorts.none")}</p>
        ) : (
          <CohortTable
            rows={o.cohorts}
            weekLabel={t("admin.growth.cohorts.week")}
            firstLabel={t("admin.growth.cohorts.this")}
            from={0}
            extra={{ label: t("admin.growth.w4"), cell: (c) => <td title={`${c.w4.kept} / ${c.w4.eligible}`}>{shown(retention(c.w4.eligible, c.w4.kept))}</td> }}
          />
        )}
      </section>

      <section className="adm-card">
        <header className="adm-card-head">
          <div>
            <h2>{t("admin.growth.first.title")}</h2>
            <p className="adm-sub">{t("admin.growth.first.sub")}</p>
          </div>
        </header>
        {o.value.firstTaskCohorts.every((c) => c.size === 0) ? (
          <p className="adm-empty">{t("admin.growth.first.none")}</p>
        ) : (
          // Week 0 is the first task itself, so every member has one: only the weeks after it are shown.
          <CohortTable rows={o.value.firstTaskCohorts} weekLabel={t("admin.growth.first.week")} firstLabel="" from={1} />
        )}
      </section>
    </>
  );
}

/** Tasks that worked out per account each week, with the results that guard it beside it. */
function ValueCard({ o }: { o: OwnerOverview }) {
  const { t } = useI18n();
  const rows = o.value.weeks.map(valueRow);
  const current = rows[rows.length - 1];
  const previous = rows[rows.length - 2];
  const kpi = (label: string, value: number | null | undefined) => (
    <div>
      <p className="adm-sub">{label}</p>
      <p className="adm-kpi-value" style={{ margin: 0 }}>{value === null || value === undefined ? "—" : value} <span className="adm-sub">{t("admin.growth.value.perAccount")}</span></p>
    </div>
  );
  return (
    <section className="adm-card">
      <header className="adm-card-head">
        <div>
          <h2>{t("admin.growth.value.title")}</h2>
          <p className="adm-sub">{t("admin.growth.value.sub")}</p>
        </div>
      </header>
      <div className="adm-cols is-even" style={{ marginBottom: 12 }}>
        {kpi(t("admin.growth.value.thisWeek"), current?.perAccount)}
        {kpi(t("admin.growth.value.lastWeek"), previous?.perAccount)}
      </div>
      <div className="adm-table-wrap">
        <table className="adm-table">
          <thead>
            <tr>
              <th scope="col">{t("admin.growth.value.week")}</th>
              <th scope="col" className="num">{t("admin.growth.value.active")}</th>
              <th scope="col" className="num">{t("admin.growth.value.workedOut")}</th>
              <th scope="col" className="num">{t("admin.growth.value.per")}</th>
              <th scope="col" className="num">{t("admin.growth.value.withOne")}</th>
              <th scope="col" className="num">{t("admin.growth.value.notSure")}</th>
              <th scope="col" className="num">{t("admin.growth.value.failed")}</th>
              <th scope="col" className="num">{t("admin.growth.value.undone")}</th>
              <th scope="col" className="num">{t("admin.growth.value.declined")}</th>
            </tr>
          </thead>
          <tbody>
            {[...rows].reverse().map((row) => (
              <tr key={row.week}>
                <th scope="row">{row === current ? t("admin.growth.value.soFar", { week: row.week }) : row.week}</th>
                <td className="num">{row.active}</td>
                <td className="num">{row.workedOut}</td>
                <td className="num">{row.perAccount ?? "—"}</td>
                <td className="num">{shown(row.withWorkedOut)}</td>
                <td className="num">{shown(row.notSure)}</td>
                <td className="num">{shown(row.failed)}</td>
                <td className="num">{shown(row.undone)}</td>
                <td className="num">{shown(row.declined)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="adm-sub">{t("admin.growth.value.guardrails")}</p>
    </section>
  );
}

/**
 * Weekly cohorts as a table: one row per week, the cohort's size, then the share active in each week after.
 * `from` is the first week shown (1 drops week 0); `extra` adds one column at the end.
 */
function CohortTable<Row extends { week: string; size: number; active: number[] }>({ rows, weekLabel, firstLabel, from, extra }: {
  rows: Row[];
  weekLabel: string;
  firstLabel: string;
  from: 0 | 1;
  extra?: { label: string; cell: (row: Row) => ReactNode };
}) {
  const { t } = useI18n();
  const weeks = rows.reduce((max, c) => Math.max(max, c.active.length), 0);
  const ks = Array.from({ length: Math.max(0, weeks - from) }, (_, i) => i + from);
  return (
    <div className="adm-table-wrap">
      <table className="adm-cohort">
        <thead>
          <tr>
            <th scope="col">{weekLabel}</th>
            <th scope="col">{t("admin.growth.cohorts.size")}</th>
            {ks.map((k) => (
              <th key={k} scope="col">{k === 0 ? firstLabel : t("admin.growth.cohorts.after", { k })}</th>
            ))}
            {extra ? <th scope="col">{extra.label}</th> : null}
          </tr>
        </thead>
        <tbody>
          {rows.map((cohort) => (
            <tr key={cohort.week}>
              <th scope="row">{cohort.week}</th>
              <td style={{ textAlign: "center" }}>{cohort.size}</td>
              {ks.map((k) => {
                const active = cohort.active[k];
                if (active === undefined) return <td key={k} className="is-future" />;
                const share = retention(cohort.size, active);
                return (
                  <td
                    key={k}
                    className={share !== null && share >= 60 ? "is-strong" : undefined}
                    style={{ ["--i" as string]: share === null ? 0 : share === 0 ? 0 : 0.14 + 0.86 * (share / 100) } as React.CSSProperties}
                    title={`${active} / ${cohort.size}`}
                  >
                    {shown(share)}
                  </td>
                );
              })}
              {extra ? extra.cell(cohort) : null}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

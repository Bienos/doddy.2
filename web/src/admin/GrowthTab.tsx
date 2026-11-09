import { useI18n } from "../i18n/i18n.js";
import type { OwnerOverview } from "../owner/schema.js";
import { ChartCard, ColumnChart, HBars } from "./charts.js";
import { percent, retention } from "./logic.js";
import { METHOD_COLOR, useMethodLabel } from "./parts.js";

/** Who joined, how they sign in, whether they start using Doddy, and whether they stay. */
export function GrowthTab({ o }: { o: OwnerOverview }) {
  const { t } = useI18n();
  const methodLabel = useMethodLabel();
  const { joined, activated } = o.activation;
  const methods = Object.entries(o.accounts.byMethod)
    .sort((a, b) => b[1] - a[1])
    .map(([key, value]) => ({ key, label: methodLabel(key), value, color: METHOD_COLOR[key] ?? "var(--c-declined)" }));
  const newPoints = o.accounts.newByDay.map((d) => ({ day: d.day, value: d.count }));
  const weeks = o.cohorts.reduce((max, c) => Math.max(max, c.active.length), 0);

  return (
    <>
      {!o.directory ? <p className="adm-note" role="note">{t("admin.noDirectory")}</p> : null}
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
          </div>
        </header>
        {o.cohorts.length === 0 ? (
          <p className="adm-empty">{t("admin.growth.cohorts.none")}</p>
        ) : (
          <div className="adm-table-wrap">
            <table className="adm-cohort">
              <thead>
                <tr>
                  <th scope="col">{t("admin.growth.cohorts.week")}</th>
                  <th scope="col">{t("admin.growth.cohorts.size")}</th>
                  {Array.from({ length: weeks }, (_, k) => (
                    <th key={k} scope="col">{k === 0 ? t("admin.growth.cohorts.this") : t("admin.growth.cohorts.after", { k })}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {o.cohorts.map((cohort) => (
                  <tr key={cohort.week}>
                    <th scope="row">{cohort.week}</th>
                    <td style={{ textAlign: "center" }}>{cohort.size}</td>
                    {Array.from({ length: weeks }, (_, k) => {
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
                          {share === null ? "—" : `${share}%`}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}

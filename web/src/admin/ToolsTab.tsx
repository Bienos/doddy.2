import { useState } from "react";
import { useI18n } from "../i18n/i18n.js";
import type { OwnerOverview } from "../owner/schema.js";
import { toolRows } from "../owner/schema.js";
import { ChartCard, Legend, StackedBar } from "./charts.js";
import { MIN_USES } from "./logic.js";
import { useOutcomes } from "./parts.js";

/** Does it work? Every tool, as one bar: how often it ran, and how each run ended. */
export function ToolsTab({ o }: { o: OwnerOverview }) {
  const { t } = useI18n();
  const { legend, segments } = useOutcomes();
  const [query, setQuery] = useState("");
  const [onlyTrouble, setOnlyTrouble] = useState(false);
  const all = toolRows(o.logbook.totals.tools);
  const needle = query.trim().toLowerCase();
  const rows = all.filter((r) => (!needle || r.tool.includes(needle)) && (!onlyTrouble || (r.total >= MIN_USES && r.failRate >= 0.2)));
  const max = Math.max(1, ...all.map((r) => r.total));

  return (
    <>
      <div className="adm-bar">
        <input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder={t("admin.tools.search")} aria-label={t("admin.tools.search")} />
        <button type="button" className="adm-chip" aria-pressed={onlyTrouble} onClick={() => setOnlyTrouble((v) => !v)}>
          {t("admin.tools.onlyTrouble")}
        </button>
        <span className="adm-count">{rows.length} / {all.length}</span>
      </div>
      <ChartCard
        title={t("admin.tools.title")}
        sub={t("admin.tools.lead")}
        wide
        legend={<Legend items={legend} />}
        chart={
          rows.length === 0 ? (
            <p className="adm-empty">{t("admin.tools.none")}</p>
          ) : (
            <div>
              {rows.map((row) => {
                const warn = row.total >= MIN_USES && row.failRate >= 0.2;
                return (
                  <div key={row.tool} className={`adm-tool ${warn ? "is-warn" : ""}`}>
                    <span className="adm-tool-name">{row.tool}</span>
                    <StackedBar scale={max} caption={`${row.tool}: ${t("admin.tools.uses", { n: row.total })}, ${t("admin.tools.trouble", { percent: Math.round(row.failRate * 100) })}`} segments={segments(row)} />
                    <span className="adm-tool-meta">
                      <span>{t("admin.tools.uses", { n: row.total })}</span>
                      <span>{t("admin.tools.trouble", { percent: Math.round(row.failRate * 100) })}</span>
                    </span>
                  </div>
                );
              })}
            </div>
          )
        }
        table={
          <table className="adm-table">
            <thead>
              <tr>
                <th scope="col">{t("admin.tools.tool")}</th>
                <th scope="col" className="num">{t("admin.tools.total")}</th>
                <th scope="col" className="num">{t("admin.out.done")}</th>
                <th scope="col" className="num">{t("admin.out.declined")}</th>
                <th scope="col" className="num">{t("admin.out.unsure")}</th>
                <th scope="col" className="num">{t("admin.out.failed")}</th>
                <th scope="col" className="num">{t("admin.out.undone")}</th>
                <th scope="col" className="num">{t("admin.col.trouble")}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.tool} className={row.total >= MIN_USES && row.failRate >= 0.2 ? "is-warn" : undefined}>
                  <td>{row.tool}</td>
                  <td className="num">{row.total}</td>
                  <td className="num">{row.done}</td>
                  <td className="num">{row.declined}</td>
                  <td className="num">{row.unsure}</td>
                  <td className="num">{row.failed}</td>
                  <td className="num">{row.undone}</td>
                  <td className="num">{Math.round(row.failRate * 100)}%</td>
                </tr>
              ))}
            </tbody>
          </table>
        }
      />
    </>
  );
}

import { useI18n } from "../i18n/i18n.js";
import type { OwnerOverview } from "../owner/schema.js";
import { ChartCard, HBars, HeatTable, Heatmap } from "./charts.js";
import { percent } from "./logic.js";

/** When people talk, for how long, how it ends, in which language, and what they hand over. */
export function ConversationsTab({ o }: { o: OwnerOverview }) {
  const { t } = useI18n();
  const c = o.conversations;
  const total = c.ended.you + c.ended.doddy + c.ended.quiet + c.ended.dropped;
  if (total === 0) {
    return (
      <section className="adm-card">
        <p className="adm-empty">{t("admin.conv.empty")}</p>
      </section>
    );
  }
  const lengths = (["under_1", "1_3", "3_5", "5_10"] as const).map((key) => ({
    key,
    label: t(`admin.conv.length.${key}` as "admin.conv.length.under_1"),
    value: c.lengths[key],
    note: `${percent(c.lengths[key], total)}%`,
  }));
  // How a conversation ended: the person's own choice is neutral, a dropped connection is the one to watch.
  const ended = [
    { key: "you", color: "var(--c-done)" },
    { key: "doddy", color: "var(--c-done)" },
    { key: "quiet", color: "var(--c-unsure)" },
    { key: "dropped", color: "var(--c-failed)" },
  ] as const;
  const endedRows = ended.map(({ key, color }) => ({
    key,
    label: t(`admin.conv.ended.${key}` as "admin.conv.ended.you"),
    value: c.ended[key],
    color,
    note: `${percent(c.ended[key], total)}%`,
  }));
  const languages = Object.entries(c.languages)
    .sort((a, b) => b[1] - a[1])
    .map(([code, value]) => ({ key: code, label: code.toUpperCase(), value, note: `${percent(value, total)}%` }));
  const errands = o.errands;

  return (
    <>
      <div style={{ marginBottom: 16 }}>
        <ChartCard title={t("admin.conv.heat.title")} sub={t("admin.conv.heat.sub", { n: total })} wide chart={<Heatmap grid={c.heatmap} />} table={<HeatTable grid={c.heatmap} />} />
      </div>
      <div className="adm-cols is-even">
        <section className="adm-card">
          <header className="adm-card-head"><h2>{t("admin.conv.length.title")}</h2></header>
          <HBars rows={lengths} />
        </section>
        <section className="adm-card">
          <header className="adm-card-head"><h2>{t("admin.conv.ended.title")}</h2></header>
          <HBars rows={endedRows} />
        </section>
      </div>
      <div className="adm-cols is-even">
        <section className="adm-card">
          <header className="adm-card-head"><h2>{t("admin.conv.lang.title")}</h2></header>
          {languages.length === 0 ? <p className="adm-empty">—</p> : <HBars rows={languages} />}
        </section>
        <section className="adm-card">
          <header className="adm-card-head"><h2>{t("admin.conv.errands.title")}</h2></header>
          <HBars
            rows={[
              { key: "handedOver", label: t("admin.conv.errands.handedOver"), value: errands.handedOver },
              { key: "finished", label: t("admin.conv.errands.finished"), value: errands.finished, color: "var(--c-done)" },
              { key: "stopped", label: t("admin.conv.errands.stopped"), value: errands.stopped, color: "var(--c-unsure)" },
            ]}
          />
        </section>
      </div>
    </>
  );
}

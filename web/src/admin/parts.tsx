import type { ReactNode } from "react";
import { useI18n } from "../i18n/i18n.js";
import type { Outcomes } from "../owner/schema.js";
import type { LegendItem, Segment } from "./charts.js";

/** Results keep one color each everywhere in the dashboard, with a glyph so color is never alone. */
export const OUTCOME_COLOR = {
  done: "var(--c-done)",
  declined: "var(--c-declined)",
  unsure: "var(--c-unsure)",
  failed: "var(--c-failed)",
} as const;
export const OUTCOME_GLYPH = { done: "✓", declined: "–", unsure: "?", failed: "✕" } as const;
export const OUTCOME_ORDER = ["done", "declined", "unsure", "failed"] as const;

/** One color per sign-in method (the entity), whatever the order of the list. */
export const METHOD_COLOR: Record<string, string> = {
  apple: "var(--adm-apple)",
  google: "var(--adm-google)",
  email: "var(--adm-email)",
};

export function Kpi({ label, value, hint }: { label: string; value: ReactNode; hint?: ReactNode }) {
  return (
    <li className="adm-kpi">
      <span className="adm-kpi-label">{label}</span>
      <span className="adm-kpi-value">{value}</span>
      {hint ? <span className="adm-kpi-hint">{hint}</span> : null}
    </li>
  );
}

export function useOutcomes() {
  const { t } = useI18n();
  const labels = {
    done: t("admin.out.done"),
    declined: t("admin.out.declined"),
    unsure: t("admin.out.unsure"),
    failed: t("admin.out.failed"),
  } as const;
  const segments = (o: Outcomes): Segment[] =>
    OUTCOME_ORDER.map((key) => ({ key, label: labels[key], value: o[key], color: OUTCOME_COLOR[key], glyph: OUTCOME_GLYPH[key] }));
  const legend: LegendItem[] = OUTCOME_ORDER.map((key) => ({ label: labels[key], color: OUTCOME_COLOR[key], glyph: OUTCOME_GLYPH[key] }));
  return { labels, segments, legend };
}

export function useMethodLabel() {
  const { t } = useI18n();
  return (method: string | null): string => {
    switch (method) {
      case "apple": return t("admin.method.apple");
      case "google": return t("admin.method.google");
      case "email": return t("admin.method.email");
      default: return method ?? t("admin.method.unknown");
    }
  };
}

/** "today", "yesterday" or "n days ago"; "never" without a day. */
export function useAgo() {
  const { t } = useI18n();
  return (days: number | null): string => {
    if (days === null) return t("admin.ago.never");
    if (days <= 0) return t("admin.ago.today");
    if (days === 1) return t("admin.ago.yesterday");
    return t("admin.ago.days", { n: days });
  };
}

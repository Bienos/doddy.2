import { useCallback, useState } from "react";
import { Navigate, NavLink, useSearchParams } from "react-router";
import { api } from "../api/client.js";
import { useResource } from "../api/useResource.js";
import { ConversationsTab } from "../admin/ConversationsTab.js";
import { GrowthTab } from "../admin/GrowthTab.js";
import { type Tab, type UserFilter, TABS } from "../admin/logic.js";
import { OverviewTab } from "../admin/OverviewTab.js";
import { ToolsTab } from "../admin/ToolsTab.js";
import { UsersTab } from "../admin/UsersTab.js";
import { ErrorState, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";
import { OWNER_PERIODS } from "../owner/schema.js";
import "../styles/admin.css";

/**
 * The admin dashboard (decision 2026-11-09-usage-counts-on-by-default): its own page outside the
 * workspace menu, in its own chunk (nobody else downloads it). The server answers it only for the
 * accounts in DODDY_OWNER_ACCOUNTS; for anyone else the answer is "not found" and this page sends
 * them back to Home. Counts only: no word anyone said exists in any number shown here.
 */
export default function AdminPage() {
  const { t } = useI18n();
  const [params, setParams] = useSearchParams();
  const asked = params.get("tab");
  const tab: Tab = (TABS as string[]).includes(asked ?? "") ? (asked as Tab) : "overview";
  const [days, setDays] = useState<number>(30);
  const [filter, setFilter] = useState<UserFilter>("all");

  const loadOverview = useCallback((signal: AbortSignal) => api.ownerOverview(days, signal), [days]);
  const loadAccounts = useCallback((signal: AbortSignal) => api.ownerAccounts(days, signal), [days]);
  const overview = useResource(loadOverview);
  const accounts = useResource(loadAccounts);
  const reload = () => {
    overview.reload();
    accounts.reload();
  };
  // The loaders read `days` at render time, so changing it and reloading in one step asks for the new period.
  const changePeriod = (next: number) => {
    setDays(next);
    reload();
  };
  const go = (next: Tab, nextFilter?: UserFilter) => {
    if (nextFilter) setFilter(nextFilter);
    setParams({ tab: next });
    window.scrollTo?.({ top: 0 });
  };

  if (overview.resource.error?.code === "not_found") return <Navigate to="/" replace />;

  const o = overview.resource.data;
  const list = accounts.resource.data?.accounts ?? [];
  const stale = Boolean(o && o.periodDays !== days);
  const updated = o ? new Date(o.generatedAt).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" }) : null;

  return (
    <div className="adm">
      <header className="adm-top">
        <div className="adm-brand">
          <strong>{t("admin.title")}</strong>
          <span>{t("admin.privacy")}</span>
        </div>
        <label>
          {t("admin.period")}
          <select value={days} onChange={(event) => changePeriod(Number(event.target.value))}>
            {OWNER_PERIODS.map((n) => (
              <option key={n} value={n}>{t("admin.days", { days: n })}</option>
            ))}
          </select>
        </label>
        <button type="button" className="adm-btn" onClick={reload}>{t("common.refresh")}</button>
        {updated ? <span className="adm-muted">{t("admin.updated", { time: updated })}</span> : null}
        <NavLink to="/" className="adm-btn">{t("admin.back")}</NavLink>
      </header>

      <main id="main" className={`adm-main ${stale ? "is-stale" : ""}`} aria-busy={stale}>
        <div className="adm-tabs" role="tablist" aria-label={t("admin.tabs")}>
          {TABS.map((id) => (
            <button key={id} type="button" role="tab" id={`adm-tab-${id}`} aria-selected={tab === id} aria-controls="adm-panel" className="adm-tab" onClick={() => go(id)}>
              {t(`admin.tab.${id}` as "admin.tab.overview")}
            </button>
          ))}
        </div>

        {overview.resource.status === "error" && !o ? <ErrorState error={overview.resource.error} onRetry={reload} /> : null}
        {!o && overview.resource.status !== "error" ? <Loading /> : null}
        {o ? (
          <div id="adm-panel" role="tabpanel" aria-labelledby={`adm-tab-${tab}`}>
            {!o.directory && tab !== "growth" ? <p className="adm-note" role="note">{t("admin.noDirectory")}</p> : null}
            {tab === "overview" ? <OverviewTab o={o} accounts={list} go={go} /> : null}
            {tab === "users" ? <UsersTab accounts={list} today={o.generatedAt.slice(0, 10)} filter={filter} onFilter={setFilter} /> : null}
            {tab === "tools" ? <ToolsTab o={o} /> : null}
            {tab === "conversations" ? <ConversationsTab o={o} /> : null}
            {tab === "growth" ? <GrowthTab o={o} /> : null}
          </div>
        ) : null}
      </main>
    </div>
  );
}

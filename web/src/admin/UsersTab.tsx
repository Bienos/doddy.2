import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api } from "../api/client.js";
import { useResource } from "../api/useResource.js";
import { ErrorState, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";
import { type OwnerAccount, toolRows } from "../owner/schema.js";
import { ChartCard, ColumnChart, Sparkline, StackedBar } from "./charts.js";
import { type AccountState, type UserFilter, USER_FILTERS, daysBetween, dayOf, matchesFilter, minutesOf, percent, stateOf, sumOutcomes } from "./logic.js";
import { Kpi, METHOD_COLOR, useAgo, useMethodLabel, useOutcomes } from "./parts.js";

type Sort = "recent" | "joined" | "conversations" | "trouble";
const SORTS: Sort[] = ["recent", "joined", "conversations", "trouble"];

interface Row {
  account: OwnerAccount;
  state: AccountState;
  ago: number | null;
  done: number;
  trouble: number;
  uses: number;
}

/** Every account, searchable and sortable, with a sparkline of its last 14 days. A row opens its own days. */
export function UsersTab({ accounts, today, filter, onFilter }: { accounts: OwnerAccount[]; today: string; filter: UserFilter; onFilter: (filter: UserFilter) => void }) {
  const { t } = useI18n();
  const methodLabel = useMethodLabel();
  const ago = useAgo();
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<Sort>("recent");
  const [open, setOpen] = useState<OwnerAccount | null>(null);

  const rows: Row[] = useMemo(
    () =>
      accounts.map((account) => {
        const o = sumOutcomes(account.period.tools);
        return {
          account,
          state: stateOf(account, today),
          ago: account.lastActiveDay ? daysBetween(account.lastActiveDay, today) : null,
          done: o.done,
          trouble: o.failed + o.unsure,
          uses: o.done + o.declined + o.unsure + o.failed,
        };
      }),
    [accounts, today],
  );

  const needle = query.trim().toLowerCase();
  const shown = rows
    .filter((r) => matchesFilter(r.state, filter))
    .filter((r) => !needle || `${r.account.email ?? ""} ${r.account.name ?? ""}`.toLowerCase().includes(needle))
    .sort((a, b) => {
      switch (sort) {
        case "joined": return (b.account.createdAt ?? "").localeCompare(a.account.createdAt ?? "");
        case "conversations": return b.account.period.conversations - a.account.period.conversations;
        case "trouble": return b.trouble - a.trouble || b.uses - a.uses;
        default: return (b.account.lastActiveDay ?? "").localeCompare(a.account.lastActiveDay ?? "");
      }
    });

  return (
    <section className="adm-card">
      <header className="adm-card-head">
        <h2>{t("admin.users.title")}</h2>
      </header>
      <div className="adm-bar">
        <input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder={t("admin.users.search")} aria-label={t("admin.users.search")} />
        <label className="adm-muted">
          {t("admin.users.sort")}{" "}
          <select value={sort} onChange={(event) => setSort(event.target.value as Sort)}>
            {SORTS.map((s) => (
              <option key={s} value={s}>{t(`admin.sort.${s}` as "admin.sort.recent")}</option>
            ))}
          </select>
        </label>
        <span className="adm-count">{t("admin.users.count", { shown: shown.length, total: rows.length })}</span>
      </div>
      <div className="adm-chips" role="group" aria-label={t("admin.filters")} style={{ marginBottom: 12 }}>
        {USER_FILTERS.map((f) => (
          <button key={f} type="button" className="adm-chip" aria-pressed={filter === f} onClick={() => onFilter(f)}>
            {t(`admin.filter.${f}` as "admin.filter.all")} <span className="adm-muted">{rows.filter((r) => matchesFilter(r.state, f)).length}</span>
          </button>
        ))}
      </div>
      {shown.length === 0 ? (
        <p className="adm-empty">{t("admin.users.none")}</p>
      ) : (
        <div className="adm-table-wrap">
          <table className="adm-table">
            <thead>
              <tr>
                <th scope="col">{t("admin.col.account")}</th>
                <th scope="col">{t("admin.col.method")}</th>
                <th scope="col">{t("admin.col.joined")}</th>
                <th scope="col">{t("admin.col.lastUse")}</th>
                <th scope="col">{t("admin.col.trend")}</th>
                <th scope="col" className="num">{t("admin.col.conversations")}</th>
                <th scope="col" className="num">{t("admin.col.done")}</th>
                <th scope="col" className="num">{t("admin.col.trouble")}</th>
                <th scope="col">{t("admin.col.state")}</th>
              </tr>
            </thead>
            <tbody>
              {shown.map((r) => {
                const a = r.account;
                const name = a.email ?? a.name ?? a.userId.slice(0, 8);
                return (
                  <tr key={a.userId} className={`is-click ${r.uses >= 5 && r.trouble / r.uses >= 0.2 ? "is-warn" : ""}`} onClick={() => setOpen(a)}>
                    <td className="wrap">
                      <span className="adm-person">
                        <span className="adm-avatar" aria-hidden="true">{(a.name ?? a.email ?? "?").slice(0, 1)}</span>
                        <span>
                          <button type="button" className="adm-row-btn" style={{ color: "var(--adm-ink)", fontSize: "0.875rem", padding: 0, textAlign: "start" }} onClick={(event) => { event.stopPropagation(); setOpen(a); }}>
                            {a.email ?? <span className="adm-muted">{t("admin.noEmail")}</span>}
                          </button>
                          {a.name ? <div className="adm-muted">{a.name}</div> : null}
                        </span>
                      </span>
                    </td>
                    <td>
                      <span className="adm-method" style={{ ["--m" as string]: METHOD_COLOR[a.method ?? ""] } as React.CSSProperties}>{methodLabel(a.method)}</span>
                    </td>
                    <td>{dayOf(a.createdAt) ?? "—"}</td>
                    <td>{r.state === "off" ? "—" : ago(r.ago)}</td>
                    <td><Sparkline values={a.trend} label={`${name}: ${t("admin.col.trend")}`} /></td>
                    <td className="num">{a.period.conversations}</td>
                    <td className="num">{r.done}</td>
                    <td className="num">{r.uses > 0 ? `${percent(r.trouble, r.uses)}%` : "—"}</td>
                    <td><span className="adm-pill" data-state={r.state}>{t(`admin.state.${r.state}` as "admin.state.today")}</span></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      {open ? <Drawer account={open} today={today} onClose={() => setOpen(null)} /> : null}
    </section>
  );
}

/** One account's own days: its numbers, a column per day and what Doddy did for it. */
function Drawer({ account, today, onClose }: { account: OwnerAccount; today: string; onClose: () => void }) {
  const { t } = useI18n();
  const methodLabel = useMethodLabel();
  const { legend, segments } = useOutcomes();
  const load = useCallback((signal: AbortSignal) => api.ownerAccountLogbook(account.userId, signal), [account.userId]);
  const { resource, reload } = useResource(load);
  const closeRef = useRef<HTMLButtonElement>(null);
  const state = stateOf(account, today);
  const title = account.email ?? account.name ?? account.userId.slice(0, 8);

  // Focus moves to Close once, and Escape closes; the handler is read through a ref so a re-render never refocuses.
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;
  useEffect(() => {
    closeRef.current?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onCloseRef.current();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, []);

  // The last 30 days up to today, a day the iPhone sent nothing for counted as nothing.
  const counts = new Map((resource.data?.days ?? []).map((d) => [d.day, d.conversations.count]));
  const points = Array.from({ length: 30 }, (_, i) => {
    const ms = Date.parse(`${today}T00:00:00Z`) - (29 - i) * 86_400_000;
    const day = new Date(ms).toISOString().slice(0, 10);
    return { day, value: counts.get(day) ?? 0 };
  });
  const tools = sumOutcomes(account.period.tools);
  const uses = tools.done + tools.declined + tools.unsure + tools.failed;
  const rows = toolRows(account.period.tools);
  const max = Math.max(1, ...rows.map((r) => r.total));

  return (
    <>
      <div className="adm-scrim" onClick={onClose} aria-hidden="true" />
      <aside className="adm-drawer" role="dialog" aria-modal="true" aria-labelledby="adm-drawer-title">
        <div className="adm-drawer-head">
          <div>
            <h2 id="adm-drawer-title">{title}</h2>
            <p className="adm-muted" style={{ margin: "4px 0 8px" }}>
              {[account.name, methodLabel(account.method), dayOf(account.createdAt)].filter(Boolean).join(" · ")}
            </p>
            <span className="adm-pill" data-state={state}>{t(`admin.state.${state}` as "admin.state.today")}</span>
          </div>
          <button ref={closeRef} type="button" className="adm-btn" onClick={onClose}>{t("admin.drawer.close")}</button>
        </div>
        <ul className="adm-kpis">
          <Kpi label={t("admin.col.conversations")} value={account.period.conversations} />
          <Kpi label={t("admin.kpi.minutes")} value={minutesOf(account.period.seconds)} />
          <Kpi label={t("admin.col.done")} value={tools.done} />
          <Kpi label={t("admin.col.trouble")} value={uses > 0 ? `${percent(tools.failed + tools.unsure, uses)}%` : "—"} />
        </ul>
        {resource.status === "loading" ? <Loading /> : null}
        {resource.status === "error" ? <ErrorState error={resource.error} onRetry={reload} /> : null}
        {resource.data ? (
          resource.data.days.length === 0 ? (
            <p className="adm-empty">{t("admin.drawer.none")}</p>
          ) : (
            <section>
              <ChartCard
                title={t("admin.drawer.days")}
                chart={<ColumnChart points={points} label={t("admin.col.conversations")} />}
                table={
                  <table className="adm-table">
                    <thead><tr><th scope="col">{t("admin.col.day")}</th><th scope="col" className="num">{t("admin.col.conversations")}</th></tr></thead>
                    <tbody>{[...points].reverse().map((p) => (<tr key={p.day}><td>{p.day}</td><td className="num">{p.value}</td></tr>))}</tbody>
                  </table>
                }
              />
            </section>
          )
        ) : null}
        {rows.length > 0 ? (
          <section>
            <h3>{t("admin.drawer.tools")}</h3>
            <ul className="adm-legend">{legend.map((item) => (<li key={item.label}><span className="adm-glyph" style={{ background: item.color }} aria-hidden="true">{item.glyph}</span>{item.label}</li>))}</ul>
            {rows.map((row) => (
              <div key={row.tool} className="adm-tool">
                <span className="adm-tool-name">{row.tool}</span>
                <StackedBar scale={max} caption={`${row.tool}: ${t("admin.tools.uses", { n: row.total })}`} segments={segments(row)} />
                <span className="adm-tool-meta">{row.total}</span>
              </div>
            ))}
          </section>
        ) : null}
        <p className="adm-muted" style={{ marginTop: 24 }}>{t("admin.drawer.id")}: {account.userId}</p>
      </aside>
    </>
  );
}

import { useCallback, useState } from "react";
import { api } from "../api/client.js";
import { useResource } from "../api/useResource.js";
import { PageHeader } from "../components/PageHeader.js";
import { Empty, ErrorState, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";
import type { DaySummary } from "../logbook/schema.js";
import { OWNER_PERIODS, type OwnerAccount, type Outcomes, toolRows } from "../owner/schema.js";

/**
 * The owner panel (decision 2026-11-09-usage-counts-on-by-default): totals of every account's
 * Logbook, how people sign in, what Doddy did and what didn't work, and each account with its own
 * days. The server answers only the accounts in DODDY_OWNER_ACCOUNTS; anyone else reaching this
 * address gets "not found" from it, shown as an error.
 */
export function OwnerPage() {
  const { t } = useI18n();
  const [days, setDays] = useState<number>(30);
  const [open, setOpen] = useState<OwnerAccount | null>(null);
  const loadOverview = useCallback((signal: AbortSignal) => api.ownerOverview(days, signal), [days]);
  const loadAccounts = useCallback((signal: AbortSignal) => api.ownerAccounts(days, signal), [days]);
  const overview = useResource(loadOverview);
  const accounts = useResource(loadAccounts);
  const reload = () => {
    overview.reload();
    accounts.reload();
  };

  if (open) return <AccountDetail account={open} onBack={() => setOpen(null)} />;

  const o = overview.resource.data?.periodDays === days ? overview.resource.data : undefined;
  const list = accounts.resource.data?.periodDays === days ? accounts.resource.data : undefined;
  const totals = o?.logbook.totals;
  const newAccounts = o ? o.accounts.newByDay.reduce((sum, d) => sum + d.count, 0) : 0;

  return (
    <>
      <PageHeader
        title={t("owner.title")}
        lead={t("owner.lead")}
        actions={
          <div className="owner-actions">
            <label>
              {t("owner.period")}{" "}
              <select value={days} onChange={(event) => setDays(Number(event.target.value))} aria-label={t("owner.period")}>
                {OWNER_PERIODS.map((n) => (
                  <option key={n} value={n}>
                    {t("owner.days", { days: n })}
                  </option>
                ))}
              </select>
            </label>
            <button type="button" className="button button-quiet" onClick={reload}>
              {t("common.refresh")}
            </button>
          </div>
        }
      />
      {overview.resource.status === "loading" || !o ? (overview.resource.status === "error" ? null : <Loading />) : null}
      {overview.resource.status === "error" ? <ErrorState error={overview.resource.error} onRetry={reload} /> : null}
      {o && totals ? (
        <>
          {!o.directory ? <p className="fine-print" role="note">{t("owner.noDirectory")}</p> : null}
          <ul className="owner-tiles" aria-label={t("owner.title")}>
            <Tile label={t("owner.tiles.accounts")} value={o.accounts.total === null ? t("owner.tiles.accountsUnknown") : o.accounts.total} />
            <Tile label={t("owner.tiles.newAccounts")} value={o.directory ? newAccounts : t("owner.never")} />
            <Tile label={t("owner.tiles.logbookOn")} value={o.logbook.on} />
            <Tile label={t("owner.tiles.logbookOff")} value={o.logbook.off} />
            <Tile label={t("owner.tiles.sending")} value={o.logbook.sending} />
            <Tile label={t("owner.tiles.conversations")} value={totals.conversations} />
            <Tile label={t("owner.tiles.minutes")} value={Math.round(totals.seconds / 60)} />
            <Tile label={t("owner.tiles.notes")} value={totals.notes} />
            <Tile label={t("owner.tiles.listItems")} value={totals.listItems} />
            <Tile label={t("owner.tiles.errands")} value={totals.errands} />
          </ul>

          {Object.keys(o.accounts.byMethod).length > 0 ? (
            <section className="owner-section" aria-labelledby="owner-methods">
              <h2 id="owner-methods">{t("owner.methods.title")}</h2>
              <ul className="owner-methods">
                {Object.entries(o.accounts.byMethod)
                  .sort((a, b) => b[1] - a[1])
                  .map(([method, n]) => (
                    <li key={method}>
                      <strong>{n}</strong> {method}
                    </li>
                  ))}
              </ul>
            </section>
          ) : null}

          <section className="owner-section" aria-labelledby="owner-active">
            <h2 id="owner-active">{t("owner.active.title")}</h2>
            <div className="lb-table-wrap">
              <table>
                <thead>
                  <tr>
                    <th scope="col">{t("owner.active.day")}</th>
                    <th scope="col">{t("owner.active.accounts")}</th>
                    {o.directory ? <th scope="col">{t("owner.active.new")}</th> : null}
                  </tr>
                </thead>
                <tbody>
                  {[...o.logbook.activeByDay].reverse().map((d, i) => (
                    <tr key={d.day}>
                      <td>{d.day}</td>
                      <td>
                        <span className="owner-bar" style={{ inlineSize: `${Math.min(100, d.accounts * 12)}px` }} aria-hidden="true" /> {d.accounts}
                      </td>
                      {o.directory ? <td>{o.accounts.newByDay[o.accounts.newByDay.length - 1 - i]?.count ?? 0}</td> : null}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <ToolTable tools={totals.tools} />
        </>
      ) : null}

      <section className="owner-section" aria-labelledby="owner-accounts">
        <h2 id="owner-accounts">{t("owner.accounts.title")}</h2>
        {accounts.resource.status === "error" ? <ErrorState error={accounts.resource.error} onRetry={reload} /> : null}
        {list ? (
          list.accounts.length === 0 ? (
            <Empty>{t("owner.accounts.none")}</Empty>
          ) : (
            <div className="lb-table-wrap">
              <table>
                <thead>
                  <tr>
                    <th scope="col">{t("owner.accounts.email")}</th>
                    <th scope="col">{t("owner.accounts.method")}</th>
                    <th scope="col">{t("owner.accounts.created")}</th>
                    <th scope="col">{t("owner.accounts.lastSignIn")}</th>
                    <th scope="col">{t("owner.accounts.logbook")}</th>
                    <th scope="col">{t("owner.accounts.lastDay")}</th>
                    <th scope="col">{t("owner.accounts.activeDays")}</th>
                    <th scope="col">{t("owner.accounts.conversations")}</th>
                    <th scope="col">{t("owner.accounts.done")}</th>
                    <th scope="col">{t("owner.accounts.failed")}</th>
                    <th scope="col">
                      <span className="visually-hidden">{t("owner.accounts.open")}</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {list.accounts.map((account) => {
                    const sum = outcomes(account.period.tools);
                    return (
                      <tr key={account.userId}>
                        <td className="owner-email">
                          {account.email ?? <span className="owner-muted">{t("owner.accounts.noEmail")}</span>}
                          {account.name ? <div className="owner-muted">{account.name}</div> : null}
                        </td>
                        <td>{account.method ?? t("owner.never")}</td>
                        <td>{date(account.createdAt) ?? t("owner.never")}</td>
                        <td>{date(account.lastSignInAt) ?? t("owner.never")}</td>
                        <td>{t(`owner.logbook.${account.logbook}`)}</td>
                        <td>{account.lastDay ?? t("owner.never")}</td>
                        <td>{account.period.activeDays}</td>
                        <td>{account.period.conversations}</td>
                        <td>{sum.done}</td>
                        <td>{sum.failed + sum.unsure}</td>
                        <td>
                          <button type="button" className="button button-quiet" onClick={() => setOpen(account)}>
                            {t("owner.accounts.open")}
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )
        ) : accounts.resource.status === "error" ? null : (
          <Loading />
        )}
      </section>
    </>
  );
}

function Tile({ label, value }: { label: string; value: string | number }) {
  return (
    <li className="owner-tile">
      <span className="owner-tile-value">{value}</span>
      <span className="owner-tile-label">{label}</span>
    </li>
  );
}

function ToolTable({ tools }: { tools: Record<string, Outcomes> }) {
  const { t } = useI18n();
  const rows = toolRows(tools);
  return (
    <section className="owner-section" aria-labelledby="owner-tools">
      <h2 id="owner-tools">{t("owner.tools.title")}</h2>
      <p className="fine-print">{t("owner.tools.lead")}</p>
      {rows.length === 0 ? (
        <Empty>{t("owner.tools.none")}</Empty>
      ) : (
        <div className="lb-table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">{t("owner.tools.tool")}</th>
                <th scope="col">{t("owner.tools.total")}</th>
                <th scope="col">{t("owner.tools.done")}</th>
                <th scope="col">{t("owner.tools.declined")}</th>
                <th scope="col">{t("owner.tools.unsure")}</th>
                <th scope="col">{t("owner.tools.failed")}</th>
                <th scope="col">{t("owner.tools.undone")}</th>
                <th scope="col">{t("owner.tools.failRate")}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.tool} className={row.failRate >= 0.2 ? "owner-warn" : undefined}>
                  <td className="lb-tool">{row.tool}</td>
                  <td>{row.total}</td>
                  <td>{row.done}</td>
                  <td>{row.declined}</td>
                  <td>{row.unsure}</td>
                  <td>{row.failed}</td>
                  <td>{row.undone}</td>
                  <td>{Math.round(row.failRate * 100)}%</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function AccountDetail({ account, onBack }: { account: OwnerAccount; onBack: () => void }) {
  const { t } = useI18n();
  const load = useCallback((signal: AbortSignal) => api.ownerAccountLogbook(account.userId, signal), [account.userId]);
  const { resource, reload } = useResource(load);
  const view = resource.data;
  const tools: Record<string, Outcomes> = {};
  for (const day of view?.days ?? []) {
    for (const [tool, o] of Object.entries(day.tools)) {
      const row = tools[tool] ?? (tools[tool] = { done: 0, declined: 0, unsure: 0, failed: 0, undone: 0 });
      row.done += o.done;
      row.declined += o.declined;
      row.unsure += o.unsure;
      row.failed += o.failed;
      row.undone += o.undone;
    }
  }
  return (
    <>
      <PageHeader
        title={account.email ?? account.name ?? t("owner.detail.title")}
        lead={[account.name, account.method, date(account.createdAt)].filter(Boolean).join(" · ")}
        actions={
          <button type="button" className="button button-quiet" onClick={onBack}>
            {t("owner.detail.back")}
          </button>
        }
      />
      {resource.status === "loading" ? <Loading /> : null}
      {resource.status === "error" ? <ErrorState error={resource.error} onRetry={reload} /> : null}
      {view ? (
        view.days.length === 0 ? (
          <Empty>{t("owner.detail.noDays")}</Empty>
        ) : (
          <>
            <section className="owner-section" aria-labelledby="owner-days">
              <h2 id="owner-days">{t("owner.detail.days")}</h2>
              <div className="lb-table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th scope="col">{t("owner.active.day")}</th>
                      <th scope="col">{t("owner.accounts.conversations")}</th>
                      <th scope="col">{t("owner.detail.minutes")}</th>
                      <th scope="col">{t("owner.tools.done")}</th>
                      <th scope="col">{t("owner.tools.failRate")}</th>
                      <th scope="col">{t("owner.detail.notes")}</th>
                      <th scope="col">{t("owner.detail.listItems")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {[...view.days].reverse().map((day) => {
                      const sum = outcomes(day.tools);
                      return (
                        <tr key={day.day}>
                          <td>{day.day}</td>
                          <td>{day.conversations.count}</td>
                          <td>{Math.round(day.conversations.seconds / 60)}</td>
                          <td>{sum.done}</td>
                          <td>{sum.failed + sum.unsure}</td>
                          <td>{notes(day)}</td>
                          <td>{day.lists.added_voice + day.lists.added_typed}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </section>
            <ToolTable tools={tools} />
          </>
        )
      ) : null}
    </>
  );
}

function outcomes(tools: Record<string, Outcomes>): Outcomes {
  const sum = { done: 0, declined: 0, unsure: 0, failed: 0, undone: 0 };
  for (const o of Object.values(tools)) {
    sum.done += o.done;
    sum.declined += o.declined;
    sum.unsure += o.unsure;
    sum.failed += o.failed;
    sum.undone += o.undone;
  }
  return sum;
}

function notes(day: DaySummary): number {
  const s = day.notes.by_source;
  return s.voice + s.typed + s.shared + s.imported;
}

/** An ISO time as its day, or null. */
function date(iso: string | null): string | null {
  return iso ? iso.slice(0, 10) : null;
}

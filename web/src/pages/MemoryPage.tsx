import { type KeyboardEvent, type ReactNode, useCallback, useEffect, useRef, useState } from "react";
import { useLocation } from "react-router";
import { api, ApiError } from "../api/client.js";
import { useResource } from "../api/useResource.js";
import { useSession } from "../auth/session.js";
import { DoddyFigure } from "../components/Brand.js";
import { saveFile } from "../components/DocumentItem.js";
import { PageHeader } from "../components/PageHeader.js";
import { Empty, ErrorState, errorText, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";
import { IPHONE_SYNCS_MEMORY } from "../memory/config.js";
import type { ConversationDetail, ConversationSummary, MemoryOverview, NoteView } from "../memory/schema.js";

/**
 * Memory (ADR-595, docs/product/CLOUD_MEMORY.md): the notes and conversations a person chose to keep
 * on Doddy's server, as text, read back from GET /v1/web/memory…. Nothing is shown that the server
 * didn't send, and every state is honest: loading, the server can't be reached, nothing kept, and
 * what is kept. The iPhone can't send anything yet (IPHONE_SYNCS_MEMORY), so the copy never points
 * at an app switch that isn't built.
 */

const PAGE = 30;

type Tab = "notes" | "conversations";

export function MemoryPage() {
  const { t } = useI18n();
  const { resource, reload } = useResource(api.memory);
  const [toast, setToast] = useState<string | null>(null);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(toastTimer.current), []);
  const say = useCallback((message: string) => {
    setToast(message);
    clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(null), 5000);
  }, []);

  const overview = resource.data;
  let content: ReactNode;
  if (overview) {
    const failed = resource.status === "error";
    content = (
      <>
        {failed ? <ErrorState error={resource.error} onRetry={reload} /> : null}
        {!overview.notes && !overview.conversations ? (
          <KeptNothing />
        ) : (
          <div className={failed ? "lb-dimmed" : undefined}>
            <MemoryBody overview={overview} say={say} onChanged={reload} />
          </div>
        )}
      </>
    );
  } else if (resource.status === "error") content = <ErrorState error={resource.error} onRetry={reload} />;
  else content = <Loading />;

  return (
    <>
      <PageHeader title={t("memory.title")} lead={t("memory.lead")} />
      {content}
      <div className="lb-toast" role="status" aria-live="polite" hidden={!toast}>
        {toast}
      </div>
    </>
  );
}

/** Both kinds are off: one calm card. It never points at an app switch until the app has one. */
export function KeptNothing({ title }: { title?: string }) {
  const { t } = useI18n();
  return (
    <section className="lb-empty" aria-labelledby="memory-h-off">
      <DoddyFigure pose="shush" size={120} className="lb-empty-pose" />
      <div className="lb-empty-body">
        <h2 id="memory-h-off">{title ?? t("memory.off.title")}</h2>
        <p>{IPHONE_SYNCS_MEMORY ? t("memory.off.body") : t("memory.off.soon")}</p>
      </div>
    </section>
  );
}

function MemoryBody({ overview, say, onChanged }: { overview: MemoryOverview; say: (message: string) => void; onChanged: () => void }) {
  const { t, dateTime } = useI18n();
  const location = useLocation();
  const [tab, setTab] = useState<Tab>(location.hash.includes("conversations") ? "conversations" : "notes");
  const tabRefs = { notes: useRef<HTMLButtonElement>(null), conversations: useRef<HTMLButtonElement>(null) };
  const choose = (next: Tab, focus = false) => {
    setTab(next);
    if (focus) tabRefs[next].current?.focus();
  };
  const onTabKey = (event: KeyboardEvent) => {
    if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
      event.preventDefault();
      choose(tab === "notes" ? "conversations" : "notes", true);
    }
  };

  return (
    <>
      <p className="memory-summary">
        <strong>{t("memory.summary", { notes: overview.noteCount, conversations: overview.conversationCount })}</strong>
        {overview.lastSyncedAt ? <span>{t("memory.lastSent", { time: dateTime(overview.lastSyncedAt) })}</span> : null}
      </p>

      <div className="lb-tabs" role="tablist" aria-label={t("memory.tabs")}>
        {(["notes", "conversations"] as const).map((id) => (
          <button
            key={id}
            type="button"
            role="tab"
            className="lb-tab"
            id={`memory-tab-${id}`}
            ref={tabRefs[id]}
            aria-controls="memory-panel"
            aria-selected={tab === id}
            tabIndex={tab === id ? 0 : -1}
            onClick={() => choose(id)}
            onKeyDown={onTabKey}
          >
            {t(`memory.tab.${id}`)}
          </button>
        ))}
      </div>
      <div className="lb-panel" role="tabpanel" id="memory-panel" aria-labelledby={`memory-tab-${tab}`}>
        {tab === "notes" ? (
          overview.notes ? (
            <NotesTab />
          ) : (
            <Empty>{t("memory.kindOff.notes")}</Empty>
          )
        ) : overview.conversations ? (
          <ConversationsTab say={say} onChanged={onChanged} />
        ) : (
          <Empty>{t("memory.kindOff.conversations")}</Empty>
        )}
      </div>

      <PrivacyPanel say={say} onChanged={onChanged} />
    </>
  );
}

/** A page of a list from the server, a "show more" that appends the next, and a reload when the key changes. */
function usePaged<T>(load: (offset: number, signal: AbortSignal) => Promise<{ items: T[]; next: number | null; unreadable: number }>, key: string, delayMs = 0) {
  const { expired } = useSession();
  const [state, setState] = useState<{ status: "loading" | "ready" | "error"; items: T[]; next: number | null; unreadable: number; error?: ApiError }>({ status: "loading", items: [], next: null, unreadable: 0 });
  const loadRef = useRef(load);
  loadRef.current = load;
  const [more, setMore] = useState(false);

  const fail = useCallback(
    (error: unknown) => {
      if (error instanceof ApiError && error.code === "unauthenticated") {
        expired();
        return;
      }
      setState((previous) => ({ ...previous, status: "error", error: error instanceof ApiError ? error : new ApiError("unreadable", String(error), 0) }));
    },
    [expired],
  );

  useEffect(() => {
    const controller = new AbortController();
    setState({ status: "loading", items: [], next: null, unreadable: 0 });
    const timer = setTimeout(() => {
      loadRef
        .current(0, controller.signal)
        .then((page) => {
          if (!controller.signal.aborted) setState({ status: "ready", items: page.items, next: page.next, unreadable: page.unreadable });
        })
        .catch((error: unknown) => {
          if (!controller.signal.aborted) fail(error);
        });
    }, delayMs);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
    // `key` is what changes the list (a search, a deletion); `load` is read through the ref.
  }, [key, delayMs, fail]);

  const loadMore = async () => {
    if (state.next === null || more) return;
    setMore(true);
    try {
      const page = await loadRef.current(state.next, new AbortController().signal);
      setState((previous) => ({ status: "ready", items: [...previous.items, ...page.items], next: page.next, unreadable: previous.unreadable + page.unreadable }));
    } catch (error) {
      fail(error);
    } finally {
      setMore(false);
    }
  };

  const remove = (match: (item: T) => boolean) => setState((previous) => ({ ...previous, items: previous.items.filter((item) => !match(item)) }));
  return { ...state, more, loadMore, remove };
}

function NotesTab() {
  const { t, dateTime } = useI18n();
  const [q, setQ] = useState("");
  const query = q.trim();
  const list = usePaged<NoteView>(
    async (offset, signal) => {
      const page = query ? await api.searchMemoryNotes({ q: query, limit: PAGE, offset }, signal) : await api.memoryNotes({ limit: PAGE, offset }, signal);
      return { items: page.notes, next: page.nextOffset, unreadable: page.unreadable };
    },
    query,
    query ? 250 : 0,
  );

  return (
    <>
      <label className="field-label" htmlFor="memory-search">
        {t("memory.search")}
      </label>
      <input id="memory-search" className="memory-search" type="search" value={q} maxLength={200} onChange={(event) => setQ(event.target.value)} autoComplete="off" />
      {list.status === "loading" ? <Loading /> : null}
      {list.status === "error" && list.error ? <ErrorState error={list.error} /> : null}
      {list.unreadable > 0 ? (
        <p className="notice" role="note">
          {t("memory.unreadable", { n: list.unreadable })}
        </p>
      ) : null}
      {list.status === "ready" && list.items.length === 0 ? <Empty>{query ? t("memory.notes.none") : t("memory.notes.empty")}</Empty> : null}
      {list.items.length > 0 ? (
        <ul className="memory-list">
          {list.items.map((note) => (
            <li key={note.id} className="memory-note">
              <p className="memory-note-text">{note.text}</p>
              <p className="memory-meta">
                {note.capturedAt ? <time dateTime={note.capturedAt}>{dateTime(note.capturedAt)}</time> : null}
                <span>{t(`memory.source.${note.source}`)}</span>
                {note.kind ? <span className="pill">{t(`logbook.kind.${note.kind}`)}</span> : null}
              </p>
            </li>
          ))}
        </ul>
      ) : null}
      {list.next !== null ? (
        <button type="button" className="button button-quiet" onClick={() => void list.loadMore()} disabled={list.more}>
          {t("memory.more")}
        </button>
      ) : null}
    </>
  );
}

function ConversationsTab({ say, onChanged }: { say: (message: string) => void; onChanged: () => void }) {
  const { t } = useI18n();
  const list = usePaged<ConversationSummary>(async (offset, signal) => {
    const page = await api.memoryConversations({ limit: PAGE, offset }, signal);
    return { items: page.conversations, next: page.nextOffset, unreadable: page.unreadable };
  }, "conversations");

  return (
    <>
      {list.status === "loading" ? <Loading /> : null}
      {list.status === "error" && list.error ? <ErrorState error={list.error} /> : null}
      {list.unreadable > 0 ? (
        <p className="notice" role="note">
          {t("memory.unreadable", { n: list.unreadable })}
        </p>
      ) : null}
      {list.status === "ready" && list.items.length === 0 ? <Empty>{t("memory.conversations.empty")}</Empty> : null}
      {list.items.length > 0 ? (
        <ul className="memory-list">
          {list.items.map((conversation) => (
            <ConversationItem
              key={conversation.id}
              conversation={conversation}
              onDeleted={() => {
                list.remove((c) => c.id === conversation.id);
                say(t("memory.conv.deleted"));
                onChanged();
              }}
              fail={(error) => say(errorText(error, t))}
            />
          ))}
        </ul>
      ) : null}
      {list.next !== null ? (
        <button type="button" className="button button-quiet" onClick={() => void list.loadMore()} disabled={list.more}>
          {t("memory.more")}
        </button>
      ) : null}
    </>
  );
}

function ConversationItem({ conversation, onDeleted, fail }: { conversation: ConversationSummary; onDeleted: () => void; fail: (error: ApiError) => void }) {
  const { t, dateTime } = useI18n();
  const { expired } = useSession();
  const [open, setOpen] = useState(false);
  const [detail, setDetail] = useState<ConversationDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);

  const handle = (caught: unknown) => {
    if (caught instanceof ApiError && caught.code === "unauthenticated") {
      expired();
      return;
    }
    fail(caught instanceof ApiError ? caught : new ApiError("network", String(caught), 0));
  };

  const toggle = async () => {
    if (open) {
      setOpen(false);
      return;
    }
    setOpen(true);
    if (detail) return;
    setLoading(true);
    try {
      setDetail(await api.memoryConversation(conversation.id));
    } catch (caught) {
      setOpen(false);
      handle(caught);
    } finally {
      setLoading(false);
    }
  };

  const remove = async () => {
    setBusy(true);
    try {
      await api.deleteMemoryConversation(conversation.id);
      onDeleted();
    } catch (caught) {
      handle(caught);
      setBusy(false);
    }
  };

  const regionId = `conversation-${conversation.id}`;
  return (
    <li className="memory-conversation">
      <div className="memory-conversation-head">
        <div>
          <p className="memory-note-text">{conversation.preview || "…"}</p>
          <p className="memory-meta">
            <time dateTime={conversation.startedAt}>{dateTime(conversation.startedAt)}</time>
            <span>{t("memory.conv.turns", { n: conversation.turnCount })}</span>
            {conversation.endedBy ? <span>{t(`logbook.ended.${conversation.endedBy}`)}</span> : null}
          </p>
        </div>
        <button type="button" className="button button-quiet button-small" aria-expanded={open} aria-controls={regionId} onClick={() => void toggle()}>
          {open ? t("memory.conv.close") : t("memory.conv.open")}
        </button>
      </div>
      {open ? (
        <div id={regionId} className="memory-transcript">
          {loading ? <Loading /> : null}
          {detail ? (
            <>
              <ol className="memory-turns">
                {detail.turns.map((turn, index) => (
                  <li key={index} className={`memory-turn memory-turn-${turn.role}`}>
                    <span className="memory-turn-who">{turn.role === "user" ? t("memory.conv.you") : t("memory.conv.doddy")}</span>
                    <span>{turn.text}</span>
                  </li>
                ))}
              </ol>
              {asking ? (
                <p className="memory-confirm" role="alert">
                  {t("memory.conv.deleteConfirm")}{" "}
                  <button type="button" className="button button-small lb-danger is-armed" onClick={() => void remove()} disabled={busy}>
                    {t("memory.conv.deleteYes")}
                  </button>{" "}
                  <button type="button" className="button button-quiet button-small" onClick={() => setAsking(false)} disabled={busy}>
                    {t("memory.conv.deleteNo")}
                  </button>
                </p>
              ) : (
                <button type="button" className="button button-quiet button-small lb-danger" onClick={() => setAsking(true)}>
                  {t("memory.conv.delete")}
                </button>
              )}
            </>
          ) : null}
        </div>
      ) : null}
    </li>
  );
}

function PrivacyPanel({ say, onChanged }: { say: (message: string) => void; onChanged: () => void }) {
  const { t } = useI18n();
  const { expired } = useSession();
  const [armed, setArmed] = useState(false);
  const [busy, setBusy] = useState<"download" | "delete" | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);

  const fail = (caught: unknown) => {
    if (caught instanceof ApiError && caught.code === "unauthenticated") {
      expired();
      return;
    }
    say(errorText(caught instanceof ApiError ? caught : new ApiError("network", String(caught), 0), t));
  };

  const onDownload = async () => {
    setBusy("download");
    try {
      await saveFile(await api.memoryFile(), `doddy-memory-${new Date().toISOString().slice(0, 10)}.json`);
      say(t("memory.downloaded"));
    } catch (caught) {
      fail(caught);
    } finally {
      setBusy(null);
    }
  };

  const onDelete = async () => {
    clearTimeout(timer.current);
    if (!armed) {
      setArmed(true);
      timer.current = setTimeout(() => setArmed(false), 5000);
      return;
    }
    setArmed(false);
    setBusy("delete");
    try {
      // "Deleted" is said only after the server answers with how many of each it removed.
      const done = await api.deleteMemory();
      say(done.deletedNotes + done.deletedConversations > 0 ? t("memory.deletedAll", { notes: done.deletedNotes, conversations: done.deletedConversations }) : t("memory.deletedNone"));
      onChanged();
    } catch (caught) {
      fail(caught);
    } finally {
      setBusy(null);
    }
  };

  return (
    <section className="lb-privacy memory-privacy" aria-labelledby="memory-h-privacy">
      <DoddyFigure pose="shush" size={110} className="lb-privacy-pose" />
      <div className="lb-privacy-body">
        <h2 id="memory-h-privacy" className="lb-privacy-title">
          {t("memory.privacy.title")}
        </h2>
        <ul className="lb-plain memory-privacy-list">
          {(["memory.privacy.p1", "memory.privacy.p2", "memory.privacy.p3", "memory.privacy.p4"] as const).map((key) => (
            <li key={key}>{t(key)}</li>
          ))}
        </ul>
        <div className="lb-privacy-actions">
          <button type="button" className="button button-quiet button-small" onClick={() => void onDownload()} disabled={busy !== null}>
            {t("memory.download")}
          </button>
          <button type="button" className={`button button-quiet button-small lb-danger ${armed ? "is-armed" : ""}`} onClick={() => void onDelete()} disabled={busy !== null}>
            {armed ? t("memory.deleteAgain") : t("memory.delete")}
          </button>
        </div>
      </div>
    </section>
  );
}

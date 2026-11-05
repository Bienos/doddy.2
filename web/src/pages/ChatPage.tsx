import { type FormEvent, type KeyboardEvent, useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import { Link, useLocation } from "react-router";
import { api, ApiError } from "../api/client.js";
import { useResource } from "../api/useResource.js";
import { useSession } from "../auth/session.js";
import { DoddyFigure } from "../components/Brand.js";
import { errorText } from "../components/States.js";
import { RichText } from "../chat/RichText.js";
import { suggestionsFor } from "../chat/suggestions.js";
import { dayGroup, type DayGroup, newId, type StoredTurn, type Thread, useThreads } from "../chat/threads.js";
import { useI18n } from "../i18n/i18n.js";
import type { MessageKey } from "../i18n/messages.js";
import { IPHONE_SENDS_LOGBOOK, LOGBOOK_ENABLED } from "../logbook/config.js";
import { IPHONE_SYNCS_MEMORY, MEMORY_ENABLED } from "../memory/config.js";
import type { AccountPart, ChatContext, ChatSource } from "../memory/schema.js";

/**
 * Doddy Web's chat (ADR-604), laid out like ChatGPT in Doddy's colours: the list of chats on the
 * left, the conversation in the middle, the message box at the bottom. Each message goes to
 * POST /v1/web/chat, where Claude answers from what Doddy's server holds for this person (kept
 * notes and conversations, Logbook's counts, connected apps, documents, receipts) and cites it.
 * The chat can only read and answer: no tools, nothing changed or sent. The list of chats is kept
 * in this browser only (chat/threads.ts); the server stores none of it.
 */

/** What the server accepts as earlier turns: whole texts of 1 to 2000 characters, ten at most. */
const HISTORY_TURNS = 10;
const forHistory = (turns: StoredTurn[]) =>
  turns
    .filter((turn) => turn.text.trim() !== "")
    .slice(-HISTORY_TURNS)
    .map((turn) => ({ role: turn.role === "user" ? ("user" as const) : ("assistant" as const), text: [...turn.text].slice(0, 2000).join("") }));

/** The browser's time zone, so "today" is the person's; left out when it isn't a plain IANA name. */
function browserTimeZone(): string | undefined {
  try {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    return zone && /^[A-Za-z][A-Za-z0-9_+-]*(\/[A-Za-z0-9_+-]+){0,2}$/.test(zone) && zone.length <= 64 ? zone : undefined;
  } catch {
    return undefined;
  }
}

/** A question that got no answer: why, shown under it until it is asked again. */
type Hitch = { kind: "error"; error: ApiError } | { kind: "stopped" };

const PAGE_OF_PART: Record<AccountPart, string | null> = {
  logbook: LOGBOOK_ENABLED ? "/logbook" : null,
  talk: MEMORY_ENABLED ? "/memory" : null,
  apps: "/apps",
  documents: "/documents",
  activity: "/activity",
};

const GROUPS: DayGroup[] = ["today", "yesterday", "week", "month", "older"];

function narrowScreen(): boolean {
  try {
    return window.matchMedia?.("(max-width: 900px)").matches === true;
  } catch {
    return false;
  }
}

export function ChatPage() {
  const { t, language } = useI18n();
  const { state, expired } = useSession();
  const owner = state.status === "signedIn" ? state.session.id : "";
  const { threads, kept, addTurn, dropLast, remove, removeAll } = useThreads(owner);
  const context = useResource(api.chatContext);
  const ready = context.resource.data?.ready !== false;

  const [activeId, setActiveId] = useState<string>(() => newId());
  const [text, setText] = useState("");
  const [pending, setPending] = useState<string | null>(null);
  const [hitches, setHitches] = useState<Record<string, Hitch | undefined>>({});
  const [fresh, setFresh] = useState<string | null>(null);
  const [listOpen, setListOpen] = useState(() => !narrowScreen());
  const [seesOpen, setSeesOpen] = useState(false);
  const [confirmAll, setConfirmAll] = useState(false);

  const abort = useRef<AbortController | null>(null);
  const stopping = useRef(false);
  const input = useRef<HTMLTextAreaElement>(null);
  const bottom = useRef<HTMLDivElement>(null);
  const heading = useRef<HTMLHeadingElement>(null);
  const location = useLocation();
  const timeZone = useMemo(browserTimeZone, []);
  const listId = useId();
  const seesId = useId();

  const thread: Thread | undefined = threads.find((th) => th.id === activeId);
  const turns = thread?.turns ?? [];
  const busy = pending !== null;
  const hitch = hitches[activeId];
  const empty = turns.length === 0 && pending !== activeId;

  // After a link inside the app the page's heading takes focus, like every other page.
  useEffect(() => {
    if (location.key !== "default") heading.current?.focus({ preventScroll: true });
  }, [location.key]);
  useEffect(() => () => abort.current?.abort(), []);
  useEffect(() => {
    // jsdom has no scrollIntoView.
    bottom.current?.scrollIntoView?.({ block: "end" });
  }, [turns.length, pending, hitch, activeId]);
  useEffect(() => {
    if (!seesOpen) return;
    context.reload();
    const onKey = (event: globalThis.KeyboardEvent) => {
      if (event.key === "Escape") setSeesOpen(false);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
    // Read again each time the panel opens (reload is stable).
  }, [seesOpen]);

  const setHitch = useCallback((id: string, value: Hitch | undefined) => setHitches((all) => ({ ...all, [id]: value })), []);

  const ask = useCallback(
    async (threadId: string, message: string, earlier: StoredTurn[]) => {
      const controller = new AbortController();
      abort.current = controller;
      stopping.current = false;
      setPending(threadId);
      setHitch(threadId, undefined);
      try {
        const reply = await api.chat({ message, history: forHistory(earlier), locale: language, ...(timeZone ? { timeZone } : {}) }, controller.signal);
        const at = Date.now();
        addTurn(threadId, { role: "doddy", text: reply.text, sources: reply.sources, at });
        setFresh(`${threadId}:${at}`);
      } catch (caught) {
        if (controller.signal.aborted) {
          if (stopping.current) setHitch(threadId, { kind: "stopped" });
          return;
        }
        if (caught instanceof ApiError && caught.code === "unauthenticated") {
          expired();
          return;
        }
        setHitch(threadId, { kind: "error", error: caught instanceof ApiError ? caught : new ApiError("network", String(caught), 0) });
      } finally {
        if (abort.current === controller) abort.current = null;
        setPending(null);
      }
    },
    [addTurn, expired, language, setHitch, timeZone],
  );

  const send = (message: string) => {
    const words = message.trim();
    if (!words || busy || !ready) return;
    const earlier = turns;
    addTurn(activeId, { role: "user", text: words, at: Date.now() });
    setText("");
    if (input.current) input.current.style.height = "";
    void ask(activeId, words, earlier);
  };

  const onSubmit = (event: FormEvent) => {
    event.preventDefault();
    send(text);
  };

  const onKey = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      send(text);
    }
  };

  const grow = (area: HTMLTextAreaElement) => {
    area.style.height = "auto";
    area.style.height = `${Math.min(area.scrollHeight, 200)}px`;
  };

  const stop = () => {
    stopping.current = true;
    abort.current?.abort();
  };

  /** The last question asked again: after an error or a stop, or to get another answer. */
  const askAgain = () => {
    if (busy || !thread) return;
    let all = thread.turns;
    if (all[all.length - 1]?.role === "doddy") {
      dropLast(thread.id);
      all = all.slice(0, -1);
    }
    const question = all[all.length - 1];
    if (question?.role !== "user") return;
    void ask(thread.id, question.text, all.slice(0, -1));
  };

  const startNew = () => {
    if (busy) return;
    setActiveId(newId());
    setText("");
    if (narrowScreen()) setListOpen(false);
    input.current?.focus();
  };

  const open = (id: string) => {
    setActiveId(id);
    if (narrowScreen()) setListOpen(false);
  };

  const removeThread = (id: string) => {
    remove(id);
    if (id === activeId) setActiveId(newId());
  };

  const groups = useMemo(() => {
    const now = Date.now();
    const by = new Map<DayGroup, Thread[]>();
    for (const th of threads) {
      const group = dayGroup(th.updatedAt, now);
      by.set(group, [...(by.get(group) ?? []), th]);
    }
    return GROUPS.filter((g) => by.has(g)).map((g) => ({ group: g, threads: by.get(g)! }));
  }, [threads]);

  const suggestions = suggestionsFor(context.resource.data);
  const lastDoddy = turns.length > 0 && turns[turns.length - 1]!.role === "doddy" ? turns.length - 1 : -1;

  const composer = (
    <form className="chat-composer" onSubmit={onSubmit}>
      <div className={`chat-box ${!ready ? "is-off" : ""}`}>
        <label className="visually-hidden" htmlFor="chat-input">
          {t("chat.input")}
        </label>
        <textarea
          id="chat-input"
          ref={input}
          className="chat-input"
          rows={1}
          maxLength={2000}
          placeholder={t("chat.placeholder")}
          value={text}
          disabled={!ready}
          onChange={(event) => {
            setText(event.target.value);
            grow(event.target);
          }}
          onKeyDown={onKey}
        />
        {busy ? (
          <button type="button" className="chat-send is-stop" onClick={stop} aria-label={t("chat.stop")} title={t("chat.stop")}>
            <IconStop />
          </button>
        ) : (
          <button type="submit" className="chat-send" disabled={!ready || text.trim() === ""} aria-label={t("chat.send")} title={t("chat.send")}>
            <IconSend />
          </button>
        )}
      </div>
      <p className="chat-fine">{t("chat.disclaimer")}</p>
    </form>
  );

  return (
    <div className={`chat ${listOpen ? "is-list-open" : ""}`}>
      <aside id={listId} className="chat-side" aria-label={t("chat.history")}>
        <div className="chat-side-top">
          <button type="button" className="chat-new" onClick={startNew} disabled={busy}>
            <IconNew />
            <span>{t("chat.new")}</span>
          </button>
          <button type="button" className="chat-icon chat-side-close" onClick={() => setListOpen(false)} aria-label={t("chat.hideList")} title={t("chat.hideList")}>
            <IconSidebar />
          </button>
        </div>
        <div className="chat-history">
          {groups.length === 0 ? <p className="chat-history-empty">{t("chat.historyEmpty")}</p> : null}
          {groups.map(({ group, threads: list }) => (
            <section key={group} aria-label={t(`chat.group.${group}` as MessageKey)}>
              <h2 className="chat-group">{t(`chat.group.${group}` as MessageKey)}</h2>
              <ul className="chat-threads">
                {list.map((th) => (
                  <li key={th.id} className={`chat-thread ${th.id === activeId ? "is-active" : ""}`}>
                    <button type="button" className="chat-thread-open" onClick={() => open(th.id)} aria-current={th.id === activeId ? "true" : undefined}>
                      {th.title}
                    </button>
                    <button
                      type="button"
                      className="chat-icon chat-thread-delete"
                      onClick={() => removeThread(th.id)}
                      disabled={pending === th.id}
                      aria-label={t("chat.delete", { title: th.title })}
                      title={t("chat.delete", { title: th.title })}
                    >
                      <IconTrash />
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </div>
        <div className="chat-side-foot">
          <p className="chat-kept">{kept ? t("chat.keptHere") : t("chat.notKept")}</p>
          {threads.length > 0 ? (
            confirmAll ? (
              <div className="chat-confirm" role="group" aria-label={t("chat.deleteAll.confirm")}>
                <span>{t("chat.deleteAll.confirm")}</span>
                <button
                  type="button"
                  className="button button-small"
                  onClick={() => {
                    abort.current?.abort();
                    removeAll();
                    setHitches({});
                    setActiveId(newId());
                    setConfirmAll(false);
                  }}
                >
                  {t("chat.deleteAll.yes")}
                </button>
                <button type="button" className="button button-quiet button-small" onClick={() => setConfirmAll(false)}>
                  {t("chat.deleteAll.no")}
                </button>
              </div>
            ) : (
              <button type="button" className="chat-link-button" onClick={() => setConfirmAll(true)}>
                {t("chat.deleteAll")}
              </button>
            )
          ) : null}
        </div>
      </aside>
      {listOpen ? <div className="chat-backdrop" aria-hidden="true" onClick={() => setListOpen(false)} /> : null}

      <section className={`chat-main ${empty ? "is-empty" : ""}`} aria-labelledby="chat-heading">
        <header className="chat-top">
          {!listOpen ? (
            <button type="button" className="chat-icon" onClick={() => setListOpen(true)} aria-label={t("chat.showList")} title={t("chat.showList")} aria-controls={listId} aria-expanded={false}>
              <IconSidebar />
            </button>
          ) : null}
          <h1 id="chat-heading" className="chat-title" tabIndex={-1} ref={heading}>
            {t("chat.title")}
          </h1>
          <div className="chat-sees-wrap">
            <button type="button" className="chat-sees-button" aria-expanded={seesOpen} aria-controls={seesId} onClick={() => setSeesOpen((v) => !v)}>
              {t("chat.sees")}
              <IconChevron />
            </button>
            <div id={seesId} className="chat-sees" hidden={!seesOpen}>
              <h2>{t("chat.sees.title")}</h2>
              <Sees context={context.resource.data} failed={context.resource.status === "error" ? context.resource.error : undefined} />
              <p className="chat-fine">{t("chat.sees.foot")}</p>
            </div>
          </div>
          {!listOpen ? (
            <button type="button" className="chat-icon" onClick={startNew} disabled={busy} aria-label={t("chat.new")} title={t("chat.new")}>
              <IconNew />
            </button>
          ) : null}
        </header>

        <div className="chat-scroll">
          {empty ? (
            <div className="chat-welcome">
              <DoddyFigure pose="wave" size={84} />
              <h2 className="chat-welcome-title">{t("chat.welcome")}</h2>
              <p className="chat-welcome-lead">{ready ? t("chat.welcome.lead") : t("chat.notReady")}</p>
            </div>
          ) : (
            <ol className="chat-log" aria-live="polite">
              {turns.map((turn, index) =>
                turn.role === "user" ? (
                  <li key={`${turn.at}-${index}`} className="chat-turn chat-turn-user">
                    <span className="visually-hidden">{t("chat.you")}: </span>
                    <div className="chat-bubble">{turn.text}</div>
                  </li>
                ) : (
                  <li key={`${turn.at}-${index}`} className={`chat-turn chat-turn-doddy ${fresh === `${activeId}:${turn.at}` ? "is-fresh" : ""}`}>
                    <Avatar />
                    <div className="chat-answer">
                      <span className="visually-hidden">{t("chat.doddy")}: </span>
                      <RichText className="chat-text" text={turn.text} />
                      {turn.sources && turn.sources.length > 0 ? <Sources sources={turn.sources} /> : null}
                      <Actions text={turn.text} onAgain={index === lastDoddy && !busy ? askAgain : undefined} />
                    </div>
                  </li>
                ),
              )}
              {pending === activeId ? (
                <li className="chat-turn chat-turn-doddy" role="status">
                  <Avatar />
                  <div className="chat-answer">
                    <span className="chat-dots" aria-hidden="true">
                      <i />
                      <i />
                      <i />
                    </span>
                    <span className="visually-hidden">{t("chat.writing")}</span>
                  </div>
                </li>
              ) : null}
              {hitch && pending !== activeId ? (
                <li className="chat-turn chat-turn-doddy">
                  <Avatar />
                  <div className={`chat-answer ${hitch.kind === "error" ? "chat-error" : "chat-stopped"}`} role={hitch.kind === "error" ? "alert" : undefined}>
                    <p>{hitch.kind === "error" ? errorText(hitch.error, t) : t("chat.stopped")}</p>
                    <button type="button" className="button button-quiet button-small" onClick={askAgain} disabled={busy}>
                      {t("chat.retry")}
                    </button>
                  </div>
                </li>
              ) : null}
            </ol>
          )}
          <div ref={bottom} />
        </div>

        {composer}

        {empty && ready ? (
          <ul className="chat-suggestions" aria-label={t("chat.welcome")}>
            {suggestions.map((key) => (
              <li key={key}>
                <button type="button" className="chat-suggestion" onClick={() => send(t(key))} disabled={busy}>
                  {t(key)}
                </button>
              </li>
            ))}
          </ul>
        ) : null}
      </section>
    </div>
  );
}

/** Doddy's face from the app icon, beside each of his answers. */
function Avatar() {
  return <img className="chat-avatar" src="/favicon.png" width={32} height={32} alt="" decoding="async" />;
}

function Actions({ text, onAgain }: { text: string; onAgain: (() => void) | undefined }) {
  const { t } = useI18n();
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const timer = setTimeout(() => setCopied(false), 2000);
    return () => clearTimeout(timer);
  }, [copied]);
  const copy = () => {
    void navigator.clipboard
      ?.writeText(text)
      .then(() => setCopied(true))
      .catch(() => {});
  };
  return (
    <div className="chat-actions">
      <button type="button" className="chat-icon chat-icon-small" onClick={copy} aria-label={copied ? t("chat.copied") : t("chat.copy")} title={copied ? t("chat.copied") : t("chat.copy")}>
        {copied ? <IconCheck /> : <IconCopy />}
      </button>
      {onAgain ? (
        <button type="button" className="chat-icon chat-icon-small" onClick={onAgain} aria-label={t("chat.again")} title={t("chat.again")}>
          <IconAgain />
        </button>
      ) : null}
    </div>
  );
}

const sourceLabel = (source: ChatSource): MessageKey =>
  source.kind === "account" ? (`chat.source.${source.part}` as MessageKey) : source.kind === "note" ? "chat.source.note" : "chat.source.conversation";

function Sources({ sources }: { sources: ChatSource[] }) {
  const { t, dateTime } = useI18n();
  const names = [...new Set(sources.map((s) => t(sourceLabel(s))))];
  return (
    <details className="chat-sources">
      <summary>
        <span>{t("chat.sources", { n: sources.length })}</span>
        <span className="chat-source-names">{names.join(" · ")}</span>
      </summary>
      <ul>
        {sources.map((source) => (
          <li key={source.kind === "account" ? `account-${source.part}` : `${source.kind}-${source.id}`}>
            <span className="pill">{t(sourceLabel(source))}</span>
            {source.kind === "account" ? (
              PAGE_OF_PART[source.part] ? (
                <Link to={PAGE_OF_PART[source.part]!}>{t("chat.source.open")}</Link>
              ) : null
            ) : source.kind === "note" ? (
              <>
                <span className="chat-source-text">{source.text}</span>
                {source.capturedAt ? <time dateTime={source.capturedAt}>{dateTime(source.capturedAt)}</time> : null}
              </>
            ) : (
              <>
                <time dateTime={source.startedAt}>{dateTime(source.startedAt)}</time>
                <ol className="memory-turns">
                  {source.turns.map((line, i) => (
                    <li key={i} className={`memory-turn memory-turn-${line.role}`}>
                      <span className="memory-turn-who">{line.role === "user" ? t("memory.conv.you") : t("memory.conv.doddy")}</span>
                      <span>{line.text}</span>
                    </li>
                  ))}
                </ol>
              </>
            )}
          </li>
        ))}
      </ul>
    </details>
  );
}

/** Each part the chat can read, in words; never a number the server didn't send. */
function Sees({ context, failed }: { context: ChatContext | undefined; failed: ApiError | undefined }) {
  const { t } = useI18n();
  if (!context) return <p className="chat-fine">{failed ? errorText(failed, t) : t("common.loading")}</p>;
  const memory = context.memory;
  const kept = (on: boolean, n: number, key: MessageKey) =>
    !memory.configured ? t("chat.sees.notSetUp") : on ? t(key, { n }) : IPHONE_SYNCS_MEMORY ? t("chat.sees.off") : t("chat.sees.offSoon");
  const rows: { label: MessageKey; value: string; on: boolean }[] = [
    { label: "chat.sees.notes", value: kept(memory.notes, memory.noteCount, "chat.sees.count.notes"), on: memory.configured && memory.notes },
    { label: "chat.sees.conversations", value: kept(memory.conversations, memory.conversationCount, "chat.sees.count.conversations"), on: memory.configured && memory.conversations },
    {
      label: "chat.sees.logbook",
      value: context.logbook.enabled
        ? context.logbook.days > 0
          ? t("chat.sees.days", { n: context.logbook.days })
          : t("chat.sees.onNoDays")
        : IPHONE_SENDS_LOGBOOK
          ? t("chat.sees.off")
          : t("chat.sees.offSoon"),
      on: context.logbook.enabled,
    },
    { label: "chat.sees.apps", value: context.apps.connected.length > 0 ? context.apps.connected.join(", ") : t("chat.sees.appsNone"), on: context.apps.connected.length > 0 },
    { label: "chat.sees.documents", value: context.documents.count > 0 ? t("chat.sees.documentsCount", { n: context.documents.count }) : t("chat.sees.none"), on: context.documents.count > 0 },
    { label: "chat.sees.activity", value: context.activity.count > 0 ? t("chat.sees.activityCount", { n: context.activity.count }) : t("chat.sees.none"), on: context.activity.count > 0 },
  ];
  return (
    <dl className="chat-sees-list">
      {rows.map((row) => (
        <div key={row.label} className={`chat-sees-row ${row.on ? "is-on" : ""}`}>
          <dt>
            <span className="chat-sees-dot" aria-hidden="true" />
            {t(row.label)}
          </dt>
          <dd>{row.value}</dd>
        </div>
      ))}
    </dl>
  );
}

// ---------------------------------------------------------------- icons (decorative; every button has its own name)

const svg = { width: 20, height: 20, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 1.9, strokeLinecap: "round", strokeLinejoin: "round", "aria-hidden": true, focusable: false } as const;

function IconNew() {
  return (
    <svg {...svg}>
      <path d="M12 20h9" />
      <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" />
    </svg>
  );
}
function IconSidebar() {
  return (
    <svg {...svg}>
      <rect x="3" y="4" width="18" height="16" rx="3" />
      <path d="M9 4v16" />
    </svg>
  );
}
function IconSend() {
  return (
    <svg {...svg} strokeWidth={2.4}>
      <path d="M12 19V5" />
      <path d="m5 12 7-7 7 7" />
    </svg>
  );
}
function IconStop() {
  return (
    <svg {...svg} fill="currentColor" stroke="none">
      <rect x="7" y="7" width="10" height="10" rx="2" />
    </svg>
  );
}
function IconCopy() {
  return (
    <svg {...svg} width={18} height={18}>
      <rect x="9" y="9" width="12" height="12" rx="2.5" />
      <path d="M5 15V5a2 2 0 0 1 2-2h10" />
    </svg>
  );
}
function IconCheck() {
  return (
    <svg {...svg} width={18} height={18}>
      <path d="m5 12 5 5 9-10" />
    </svg>
  );
}
function IconAgain() {
  return (
    <svg {...svg} width={18} height={18}>
      <path d="M20 12a8 8 0 1 1-2.3-5.7" />
      <path d="M20 4v5h-5" />
    </svg>
  );
}
function IconTrash() {
  return (
    <svg {...svg} width={17} height={17}>
      <path d="M4 7h16" />
      <path d="M10 11v6M14 11v6" />
      <path d="M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12" />
      <path d="M9 7V4h6v3" />
    </svg>
  );
}
function IconChevron() {
  return (
    <svg {...svg} width={16} height={16}>
      <path d="m6 9 6 6 6-6" />
    </svg>
  );
}

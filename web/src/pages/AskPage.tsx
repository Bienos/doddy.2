import { type FormEvent, type KeyboardEvent, useEffect, useRef, useState } from "react";
import { api, ApiError } from "../api/client.js";
import { useResource } from "../api/useResource.js";
import { useSession } from "../auth/session.js";
import { PageHeader } from "../components/PageHeader.js";
import { ErrorState, errorText, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";
import type { ChatSource } from "../memory/schema.js";
import { KeptNothing } from "./MemoryPage.js";

/**
 * Ask Doddy on the web (ADR-595): a question about your own notes and conversations, answered by
 * Claude from the best-matching ones on Doddy's server (POST /v1/web/chat). It can only answer: no
 * tools, nothing saved or changed. Nothing about the chat is stored; the page keeps the turns in
 * memory and sends the last few with each question. Every answer shows the sources it cites, so
 * what it says can be checked against what is kept.
 */

interface Turn {
  role: "user" | "doddy";
  text: string;
  sources?: ChatSource[];
  /** A question that got no answer: why, and the text to send again. */
  error?: ApiError;
}

/** What the server accepts as an earlier turn: whole texts of 1 to 2000 characters, six at most. */
const forHistory = (turns: Turn[]): { role: "user" | "assistant"; text: string }[] =>
  turns
    .filter((turn) => !turn.error && turn.text.trim() !== "")
    .slice(-6)
    .map((turn) => ({ role: turn.role === "user" ? ("user" as const) : ("assistant" as const), text: [...turn.text].slice(0, 2000).join("") }));

export function AskPage() {
  const { t } = useI18n();
  const { resource, reload } = useResource(api.memory);
  const overview = resource.data;
  return (
    <>
      <PageHeader title={t("ask.title")} lead={t("ask.lead")} />
      {overview ? (
        !overview.notes && !overview.conversations ? (
          <KeptNothing title={t("ask.off.title")} />
        ) : (
          <Chat />
        )
      ) : resource.status === "error" ? (
        <ErrorState error={resource.error} onRetry={reload} />
      ) : (
        <Loading />
      )}
    </>
  );
}

function Chat() {
  const { t, language, dateTime } = useI18n();
  const { expired } = useSession();
  const [turns, setTurns] = useState<Turn[]>([]);
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const bottom = useRef<HTMLDivElement>(null);
  const abort = useRef<AbortController | null>(null);
  useEffect(() => () => abort.current?.abort(), []);
  useEffect(() => {
    // jsdom has no scrollIntoView.
    bottom.current?.scrollIntoView?.({ block: "end" });
  }, [turns, busy]);

  const ask = async (message: string, earlier: Turn[]) => {
    setBusy(true);
    const controller = new AbortController();
    abort.current = controller;
    try {
      const reply = await api.chat({ message, history: forHistory(earlier), locale: language }, controller.signal);
      setTurns((previous) => [...previous, { role: "doddy", text: reply.text, sources: reply.sources }]);
    } catch (caught) {
      if (controller.signal.aborted) return;
      if (caught instanceof ApiError && caught.code === "unauthenticated") {
        expired();
        return;
      }
      const error = caught instanceof ApiError ? caught : new ApiError("network", String(caught), 0);
      setTurns((previous) => [...previous, { role: "doddy", text: "", error }]);
    } finally {
      setBusy(false);
    }
  };

  const send = (event?: FormEvent) => {
    event?.preventDefault();
    const message = text.trim();
    if (!message || busy) return;
    const earlier = turns;
    setTurns([...earlier, { role: "user", text: message }]);
    setText("");
    void ask(message, earlier);
  };

  /** Asks the last question again after an error: the failed answer is dropped, the question stays. */
  const retry = () => {
    const lastQuestion = [...turns].reverse().find((turn) => turn.role === "user");
    if (!lastQuestion || busy) return;
    const withoutError = turns.slice(0, -1);
    setTurns(withoutError);
    void ask(lastQuestion.text, withoutError.slice(0, -1));
  };

  const onKey = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) send();
  };

  return (
    <section className="ask" aria-label={t("ask.title")}>
      {turns.length === 0 ? <p className="ask-hint says">{t("ask.hint")}</p> : null}
      <ol className="ask-turns" aria-live="polite">
        {turns.map((turn, index) => (
          <li key={index} className={`ask-turn ask-turn-${turn.role}`}>
            <span className="ask-who">{turn.role === "user" ? t("ask.you") : t("ask.doddy")}</span>
            {turn.error ? (
              <div className="state state-error" role="alert">
                <p>{errorText(turn.error, t)}</p>
                {index === turns.length - 1 ? (
                  <button type="button" className="button button-quiet button-small" onClick={retry} disabled={busy}>
                    {t("ask.retry")}
                  </button>
                ) : null}
              </div>
            ) : (
              <p className="ask-text">{turn.text}</p>
            )}
            {turn.sources && turn.sources.length > 0 ? (
              <details className="ask-sources">
                <summary>{t("ask.sources", { n: turn.sources.length })}</summary>
                <ul>
                  {turn.sources.map((source) => (
                    <li key={`${source.kind}-${source.id}`}>
                      {source.kind === "note" ? (
                        <>
                          <span className="pill">{t("ask.source.note")}</span>
                          <span className="ask-source-text">{source.text}</span>
                          {source.capturedAt ? <time dateTime={source.capturedAt}>{dateTime(source.capturedAt)}</time> : null}
                        </>
                      ) : (
                        <>
                          <span className="pill">{t("ask.source.conversation")}</span>
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
            ) : null}
          </li>
        ))}
        {busy ? (
          <li className="ask-turn ask-turn-doddy" role="status">
            <span className="ask-who">{t("ask.doddy")}</span>
            <p className="ask-text">{t("ask.thinking")}</p>
          </li>
        ) : null}
      </ol>
      <div ref={bottom} />

      <form className="ask-form" onSubmit={send}>
        <label className="field-label" htmlFor="ask-input">
          {t("ask.input")}
        </label>
        <textarea id="ask-input" className="ask-input" rows={3} maxLength={2000} value={text} onChange={(event) => setText(event.target.value)} onKeyDown={onKey} />
        <div className="ask-actions">
          <button type="submit" className="button" disabled={busy || text.trim() === ""}>
            {busy ? t("ask.sending") : t("ask.send")}
          </button>
          {turns.length > 0 ? (
            <button type="button" className="button button-quiet" onClick={() => setTurns([])} disabled={busy}>
              {t("ask.clear")}
            </button>
          ) : null}
        </div>
        <p className="fine-print">{t("ask.disclaimer")}</p>
      </form>
    </section>
  );
}

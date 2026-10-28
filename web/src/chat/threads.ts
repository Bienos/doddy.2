import { useCallback, useEffect, useRef, useState } from "react";
import type { ChatSource } from "../memory/schema.js";

/**
 * The chat's history, like ChatGPT's list of chats (ADR-604), kept **only in this browser**
 * (localStorage), never on Doddy's server. It belongs to one browser sign-in: it carries that
 * session's id and is wiped when someone else signs in here, at Sign out, and when the session
 * ends. Storage may be blocked (private windows) or full: then the chats last for this visit only,
 * and the page says nothing was kept rather than pretending it was.
 */

export interface StoredTurn {
  role: "user" | "doddy";
  text: string;
  sources?: ChatSource[];
  at: number;
}

export interface Thread {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  turns: StoredTurn[];
}

const STORAGE_KEY = "doddy.web.chats.v1";
export const MAX_THREADS = 40;
export const MAX_TURNS_PER_THREAD = 80;
const TITLE_LENGTH = 48;

interface Saved {
  owner: string;
  threads: Thread[];
}

export function newId(): string {
  const random = globalThis.crypto?.randomUUID?.();
  return random ?? `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

/** A thread's name: its first question, on one line, cut to fit the list. */
export function titleFor(text: string): string {
  const line = text.replace(/\s+/g, " ").trim();
  const chars = [...line];
  return chars.length > TITLE_LENGTH ? `${chars.slice(0, TITLE_LENGTH - 1).join("").trimEnd()}…` : line;
}

const isTurn = (value: unknown): value is StoredTurn => {
  if (!value || typeof value !== "object") return false;
  const turn = value as Record<string, unknown>;
  return (turn.role === "user" || turn.role === "doddy") && typeof turn.text === "string" && typeof turn.at === "number" && (turn.sources === undefined || Array.isArray(turn.sources));
};

const isThread = (value: unknown): value is Thread => {
  if (!value || typeof value !== "object") return false;
  const t = value as Record<string, unknown>;
  return typeof t.id === "string" && typeof t.title === "string" && typeof t.createdAt === "number" && typeof t.updatedAt === "number" && Array.isArray(t.turns) && t.turns.every(isTurn);
};

/** The chats this sign-in kept here, newest first. Another sign-in's chats are deleted, never shown. */
export function loadThreads(owner: string): Thread[] {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const saved = JSON.parse(raw) as Partial<Saved>;
    if (saved.owner !== owner || !Array.isArray(saved.threads)) {
      window.localStorage.removeItem(STORAGE_KEY);
      return [];
    }
    return saved.threads.filter(isThread).sort((a, b) => b.updatedAt - a.updatedAt);
  } catch {
    return [];
  }
}

/** Keeps the newest chats that fit. Returns whether the browser kept them. */
export function saveThreads(owner: string, threads: Thread[]): boolean {
  let keep = threads
    .filter((t) => t.turns.length > 0)
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, MAX_THREADS)
    .map((t) => ({ ...t, turns: t.turns.slice(-MAX_TURNS_PER_THREAD) }));
  for (let attempt = 0; attempt < 4; attempt += 1) {
    try {
      if (keep.length === 0) window.localStorage.removeItem(STORAGE_KEY);
      else window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ owner, threads: keep } satisfies Saved));
      return true;
    } catch {
      // Full: drop the older half and try again.
      if (keep.length <= 1) return false;
      keep = keep.slice(0, Math.ceil(keep.length / 2));
    }
  }
  return false;
}

/** Deletes every chat kept in this browser (Sign out, a session that ended, "Delete all chats"). */
export function clearThreads(): void {
  try {
    window.localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Storage blocked: nothing was kept.
  }
}

/** The list of chats for one sign-in, saved on every change. */
export function useThreads(owner: string) {
  // The list carries the sign-in it belongs to, so it is never saved under another one.
  const [list, setList] = useState<{ owner: string; threads: Thread[] }>(() => ({ owner, threads: loadThreads(owner) }));
  const [kept, setKept] = useState(true);
  const first = useRef(true);

  // Another sign-in in the same tab reads its own list (and wipes the one before).
  useEffect(() => {
    if (list.owner !== owner) setList({ owner, threads: loadThreads(owner) });
  }, [owner, list.owner]);

  useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    if (list.owner === owner) setKept(saveThreads(list.owner, list.threads));
  }, [owner, list]);

  const setThreads = useCallback((change: (all: Thread[]) => Thread[]) => setList((current) => ({ owner: current.owner, threads: change(current.threads) })), []);
  const threads = list.owner === owner ? list.threads : [];

  /** Adds a turn to a thread, making the thread if it is new. */
  const addTurn = useCallback((id: string, turn: StoredTurn) => {
    setThreads((all) => {
      const existing = all.find((t) => t.id === id);
      const thread: Thread = existing
        ? { ...existing, updatedAt: turn.at, turns: [...existing.turns, turn] }
        : { id, title: titleFor(turn.text), createdAt: turn.at, updatedAt: turn.at, turns: [turn] };
      return [thread, ...all.filter((t) => t.id !== id)];
    });
  }, [setThreads]);

  /** Drops a thread's last turn (an answer asked again). */
  const dropLast = useCallback((id: string) => {
    setThreads((all) => all.map((t) => (t.id === id ? { ...t, turns: t.turns.slice(0, -1) } : t)));
  }, [setThreads]);

  const remove = useCallback((id: string) => setThreads((all) => all.filter((t) => t.id !== id)), [setThreads]);
  const removeAll = useCallback(() => {
    clearThreads();
    setThreads(() => []);
  }, [setThreads]);

  return { threads, kept, addTurn, dropLast, remove, removeAll };
}

export type DayGroup = "today" | "yesterday" | "week" | "month" | "older";

/** Which heading a chat sits under in the list, by the person's own calendar days. */
export function dayGroup(updatedAt: number, now: number): DayGroup {
  const startOfToday = new Date(now);
  startOfToday.setHours(0, 0, 0, 0);
  const days = Math.floor((startOfToday.getTime() - new Date(updatedAt).setHours(0, 0, 0, 0)) / 86_400_000);
  if (days <= 0) return "today";
  if (days === 1) return "yesterday";
  if (days < 7) return "week";
  if (days < 30) return "month";
  return "older";
}

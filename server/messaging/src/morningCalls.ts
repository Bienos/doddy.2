import { randomUUID } from "node:crypto";
import { lang, type Language } from "./calls.js";
import type { TextCipher } from "./crypto.js";
import { inTransaction, type Db } from "./db.js";
import { log } from "./log.js";
import { localDate, zonedToUtc } from "./news/schedule.js";
import { localClock, parseClock } from "./quietHours.js";
import { sealReason } from "./scheduledCalls.js";

// A morning call (decision 2026-11-14-morning-call): "dzwoń do mnie codziennie o 8 z planem dnia". The person approves
// the exact schedule once, on a card (morningCallApprovalHash: the number, the time, the days, the zone, the quiet-hours
// choice and the language). It is a standing permission to call them, so it is stored apart (morning_calls) and each
// day, when it is due, this worker turns it into a normal scheduled call (scheduled_calls, kind 'morning'). From there
// placeDueCall checks everything a booked call gets checked for: the number and consent, the schedule still active
// and bound to that number, quiet hours where the person is now, the hourly and daily caps, too late; an unknown
// outcome is never placed again. Stopping is one request (DELETE /v1/calls/morning) and works at once.
//
// What the call knows about the day is only what Doddy's server already holds for the person: the calls they booked
// for later that day, notes waiting in the app, results of tasks they handed over, new stories On my radar found, and
// when the daily news comes. Their calendar and reminders are on the iPhone and never reach this server, so the
// call says so instead of guessing; there is no weather (the server has no place for the person).

/** A morning call may ring from 05:00 to 11:59 on the person's clock. Mirrored in doddy_rules.yaml (contact_policy). */
export const MORNING_CALL_EARLIEST = "05:00";
export const MORNING_CALL_LATEST = "11:59";

/** "HH:MM" from 05:00 to 11:59. */
export function isMorningTime(time: string): boolean {
  const m = parseClock(time);
  return m !== undefined && m >= parseClock(MORNING_CALL_EARLIEST)! && m <= parseClock(MORNING_CALL_LATEST)!;
}

/** ISO weekdays as digits, ascending, each at most once: "12345", "1234567", "6". */
export const isDays = (days: string) => days !== "" && /^1?2?3?4?5?6?7?$/.test(days);

/** The ISO weekday (Monday 1 … Sunday 7) of the calendar date y-m-d. */
const isoWeekday = (y: number, m: number, d: number) => ((new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7) + 1;

/**
 * The next instant strictly after `after` when the wall clock in `zone` shows `time` on one of `days`. Read on the
 * zone's own clock (news/schedule.ts zonedToUtc), so 08:00 stays 08:00 across a change to or from summer time.
 */
export function nextMorningCallAt(after: Date, time: string, days: string, zone: string): Date {
  const [hh, mm] = time.split(":").map(Number) as [number, number];
  const [y, m, d] = localDate(after, zone).split("-").map(Number) as [number, number, number];
  for (let add = 0; add <= 8; add++) {
    const day = new Date(Date.UTC(y, m - 1, d + add));
    const [dy, dm, dd] = [day.getUTCFullYear(), day.getUTCMonth() + 1, day.getUTCDate()];
    if (!days.includes(String(isoWeekday(dy, dm, dd)))) continue;
    const at = zonedToUtc(dy, dm, dd, hh, mm, zone);
    if (at > after) return at;
  }
  throw new Error("a schedule with no day");
}

/** Every call of the schedule from `from` up to (not including) `to`. */
export function morningCallsBetween(from: Date, to: Date, time: string, days: string, zone: string): Date[] {
  const out: Date[] = [];
  let at = nextMorningCallAt(new Date(from.getTime() - 1), time, days, zone);
  while (at < to && out.length < 16) {
    out.push(at);
    at = nextMorningCallAt(at, time, days, zone);
  }
  return out;
}

/** What Doddy's server holds for the person that matters today. Counts and times only: never a reason, a note or a headline. */
export interface MorningFacts {
  /** Doddy's calls the person booked for later the same day, as local times. */
  laterCalls: string[];
  /** Notes from calls and texts waiting in the app for the person to confirm. */
  notesWaiting: number;
  /** Tasks handed over to Doddy whose result is ready and not saved yet. */
  errandsReady: number;
  /** Stories On my radar found in the last day that the person hasn't seen. */
  radarNew: number;
  /** When today's daily news comes, if later today. */
  newsAt?: string;
}

export const NO_FACTS: MorningFacts = { laterCalls: [], notesWaiting: 0, errandsReady: 0, radarNew: 0 };

type Queryable = { query: Db["query"] };

/** Reads the facts at `now`, for the day as it is in `zone`. */
export async function morningFacts(db: Queryable, accountId: string, now: Date, zone: string): Promise<MorningFacts> {
  const [y, m, d] = localDate(now, zone).split("-").map(Number) as [number, number, number];
  const endOfDay = zonedToUtc(y, m, d + 1, 0, 0, zone);
  const { rows: [r] } = await db.query<{ later: Date[]; notes: number; errands: number; radar: number; news_at: Date | null }>(
    `SELECT
       ARRAY(SELECT call_at FROM scheduled_calls WHERE account_id = $1 AND kind = 'once' AND state = 'scheduled'
               AND call_at > $2 AND call_at < $3 ORDER BY call_at LIMIT 5) AS later,
       (SELECT count(*)::int FROM call_notes WHERE account_id = $1) AS notes,
       (SELECT count(*)::int FROM errands WHERE account_id = $1 AND state = 'done' AND acknowledged_at IS NULL
          AND result_ciphertext IS NOT NULL) AS errands,
       (SELECT count(*)::int FROM radar_hits WHERE account_id = $1 AND seen_at IS NULL
          AND found_at > $2::timestamptz - interval '1 day') AS radar,
       (SELECT next_run_at FROM news_settings WHERE account_id = $1 AND enabled AND next_run_at > $2 AND next_run_at < $3) AS news_at`,
    [accountId, now, endOfDay]);
  return {
    laterCalls: (r?.later ?? []).map((t) => localClock(t, zone)),
    notesWaiting: r?.notes ?? 0,
    errandsReady: r?.errands ?? 0,
    radarNew: r?.radar ?? 0,
    ...(r?.news_at ? { newsAt: localClock(r.news_at, zone) } : {}),
  };
}

/** 1 notatka, 2 notatki, 5 notatek, 12 notatek, 22 notatki. */
function plForm(n: number, one: string, few: string, many: string): string {
  if (n === 1) return one;
  const tens = n % 100;
  return n % 10 >= 2 && n % 10 <= 4 && (tens < 12 || tens > 14) ? few : many;
}

const joinList = (items: string[], and: string) =>
  items.length <= 1 ? items.join("") : `${items.slice(0, -1).join(", ")} ${and} ${items[items.length - 1]}`;

/**
 * The plan Doddy says first on a morning call, in one line, written here from `facts` and never by a model (DOD-02):
 * the day and date, then only what the server holds, then that the calendar is on the iPhone. It goes to the phone
 * agent as the call's reason (doddy_call_reason), so it has no new lines and no braces.
 */
export function morningPlan(facts: MorningFacts, day: Date, zone: string, language: Language): string {
  const pl = language === "pl";
  const date = new Intl.DateTimeFormat(pl ? "pl-PL" : "en-GB", { timeZone: zone, weekday: "long", day: "numeric", month: "long" }).format(day);
  const lines: string[] = [pl ? `Dziś ${date}.` : `Today is ${date}.`];
  const { laterCalls: calls, notesWaiting: notes, errandsReady: errands, radarNew: radar } = facts;
  if (calls.length) {
    lines.push(pl ? `Zadzwonię do Ciebie dziś jeszcze o ${joinList(calls, "i")}.` : `I'll call you again today at ${joinList(calls, "and")}.`);
  }
  if (notes > 0) {
    lines.push(pl
      ? plForm(notes, "W aplikacji czeka 1 notatka do potwierdzenia.", `W aplikacji czekają ${notes} notatki do potwierdzenia.`,
        `W aplikacji czeka ${notes} notatek do potwierdzenia.`)
      : notes === 1 ? "1 note waits in the app for you to confirm." : `${notes} notes wait in the app for you to confirm.`);
  }
  if (errands > 0) {
    lines.push(pl
      ? errands === 1 ? "W aplikacji czeka gotowy wynik zadania, które mi przekazano." : `Gotowe wyniki zadań w aplikacji: ${errands}.`
      : errands === 1 ? "A task you handed over has its result ready in the app." : `${errands} tasks you handed over have results ready in the app.`);
  }
  if (radar > 0) {
    lines.push(pl
      ? plForm(radar, "Na radarze jest 1 nowy artykuł.", `Na radarze są ${radar} nowe artykuły.`, `Na radarze jest ${radar} nowych artykułów.`)
      : radar === 1 ? "1 new story is on your radar." : `${radar} new stories are on your radar.`);
  }
  if (facts.newsAt) lines.push(pl ? `Wiadomości dnia przyślę o ${facts.newsAt}.` : `Your daily news comes at ${facts.newsAt}.`);
  if (lines.length === 1) lines.push(pl ? "Poza tym nic od Ciebie u mnie dziś nie czeka." : "Nothing else is waiting for you with me today.");
  lines.push(pl
    ? "Twojego kalendarza i przypomnień nie widzę, są tylko na iPhonie. Chcesz coś dodać albo o coś zapytać?"
    : "I can't see your calendar or reminders: they are only on your iPhone. Anything you'd like to add or ask?");
  return lines.join(" ").replace(/[\r\n]+/g, " ").replace(/[{}]/g, "");
}

export interface MorningCallDeps {
  db: Db;
  cipher?: TextCipher;
  now?: () => Date;
}

interface DueMorning {
  id: string; account_id: string; local_time: string; days: string; time_zone: string; allow_quiet_hours: boolean;
  language: string; approval_hash: Buffer; next_call_at: Date;
}

const isoSecond = (d: Date) => d.toISOString().replace(/\.\d{3}Z$/, "Z");

/**
 * Turns at most one due morning call into that day's scheduled call, with the plan written now, and moves the schedule
 * to its next day. Returns whether one was handled. placeDueCall then checks and places it like any booked call; if
 * the worker was down past the late limit, that call ends as missed with one notice, and the schedule goes on from the
 * next day (never a pile of calls for the days that were missed).
 */
export async function prepareMorningCall(deps: MorningCallDeps): Promise<boolean> {
  const { db, cipher } = deps;
  if (!cipher) return false;
  const now = deps.now?.() ?? new Date();
  const { rows: [candidate] } = await db.query<{ id: string; account_id: string }>(
    "SELECT id, account_id FROM morning_calls WHERE state = 'active' AND next_call_at <= $1 ORDER BY next_call_at LIMIT 1", [now]);
  if (!candidate) return false;
  return inTransaction(db, async (c) => {
    // The lock a booking, a stop and placing a call take (scheduledCalls.ts), so a stop can't slip in between.
    await c.query("SELECT pg_advisory_xact_lock(hashtext('outbound_calls:' || $1))", [candidate.account_id]);
    const { rows: [m] } = await c.query<DueMorning>(
      `SELECT id, account_id, local_time, days, time_zone, allow_quiet_hours, language, approval_hash, next_call_at
       FROM morning_calls WHERE id = $1 AND state = 'active' AND next_call_at <= $2 FOR UPDATE`, [candidate.id, now]);
    if (!m) return true; // another worker made it, or it was stopped meanwhile
    const at = m.next_call_at;
    let facts = NO_FACTS;
    try {
      facts = await morningFacts(c, m.account_id, now, m.time_zone);
    } catch (err) {
      // A plan with less in it is better than a schedule stuck on one account.
      log("morning facts failed", { id: m.id, error: err instanceof Error ? err.name : "unknown" });
    }
    const id = randomUUID();
    const plan = morningPlan(facts, at, m.time_zone, lang(m.language));
    // One call per schedule and local day, even if two workers race (the idempotency key is unique per account).
    await c.query(
      `INSERT INTO scheduled_calls (id, account_id, call_at, call_at_text, reason_ciphertext, reason_key_version, time_zone,
         allow_quiet_hours, language, approval_hash, idempotency_key, state, kind, morning_call_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'scheduled', 'morning', $12)
       ON CONFLICT (account_id, idempotency_key) DO NOTHING`,
      [id, m.account_id, at, isoSecond(at), sealReason(cipher, m.account_id, id, plan), cipher.keyVersion, m.time_zone,
        m.allow_quiet_hours, m.language, m.approval_hash, `morning-call:${m.id}:${localDate(at, m.time_zone)}`, m.id]);
    const next = nextMorningCallAt(now > at ? now : at, m.local_time, m.days, m.time_zone);
    await c.query("UPDATE morning_calls SET next_call_at = $2, updated_at = now() WHERE id = $1", [m.id, next]);
    log("morning call prepared", { id: m.id, call: id });
    return true;
  });
}
